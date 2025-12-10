package main

import "core:fmt"
import "core:mem"

NES :: struct {
    ppu: ^PPU,
    apu: ^APU,
    cpu: ^CPU,

    cpu_bus: ^NES_CPU_Bus,
    ppu_bus: ^NES_PPU_Bus,

    rom: ^ROM,
    mapper: Mapper,

    io: ^IO,
}

NES_Init_Error :: union #shared_nil {
    mem.Allocator_Error,
    Parsing_Error,
    Mapper_Initialization_Error,
}

nes_init :: proc(rom_data: []byte) -> (nes: ^NES, err: NES_Init_Error) {
    ppu := new(PPU) or_return
	apu := new(APU) or_return
    cpu := new(CPU) or_return
	
	ppu_bus := new(NES_PPU_Bus) or_return
    cpu_bus := new(NES_CPU_Bus) or_return

    io := new(IO) or_return

    rom := rom_parse(rom_data) or_return

    mapper, err_mapper := mapper_init(rom, ppu_bus.vram[:])
    if err_mapper != nil {
        rom_free(rom)
        return nil, err_mapper
    }

	ppu_bus.cpu_bus = cpu_bus
    ppu_bus.rom = rom
    ppu_bus.mapper = mapper
    
	cpu_bus.ppu = ppu
    cpu_bus.ppu_bus = ppu_bus
    cpu_bus.apu = apu
    cpu_bus.rom = rom
    cpu_bus.mapper = mapper
    cpu_bus.io = io

    return new_clone(NES{
        rom = rom,
        mapper = mapper,
        ppu = ppu,
        apu = apu,
        cpu = cpu,
        ppu_bus = ppu_bus,
        cpu_bus = cpu_bus,
        io = io,
    })
}

nes_free :: proc(nes: ^NES) {
    if nes.rom != nil {
        rom_free(nes.rom)
    }

    if nes.mapper != nil {
        mapper_free(nes.mapper)
    }

    free(nes.ppu)
    free(nes.apu)
    free(nes.cpu)

    free(nes.ppu_bus)
    free(nes.cpu_bus)

    free(nes.io)

    free(nes)
}

nes_attach_peripheral :: proc(nes: ^NES, p: Peripheral, port: IO_Port) {
    nes.io.ports[port] = p
}

// Resets the state of the hardware but leaves ROM and mapper in place
nes_reset :: proc(nes: ^NES) {
    cpu_reset(nes.cpu, nes.cpu_bus)
}

nes_tick :: proc(nes: ^NES) {
    // 3 PPU cycles for every CPU cycle
    ppu_tick(nes.ppu, nes.ppu_bus)
    ppu_tick(nes.ppu, nes.ppu_bus)
    ppu_tick(nes.ppu, nes.ppu_bus)

    // Tick APU every other CPU cycle
    if nes.cpu.is_read_cycle {
        apu_tick(nes.apu)
    }

    cpu_tick(nes.cpu, nes.cpu_bus)
}

nes_print_state :: proc(nes: ^NES) {
    cpu := nes.cpu
    mnemonic := "??"
    if cpu.instruction != nil {
        mnemonic = cpu.instruction.mnemonic
    }

    fmt.printfln("%04X: %s", u16(cpu.PC), mnemonic)
    fmt.printfln(
        "A=%02X X=%02X Y=%02X S=%02X P=%02X",
        cpu.A,
        cpu.X,
        cpu.Y,
        cpu.S,
        byte(cpu.P),
    )

    fmt.printfln(
        "N=%d V=%d B=%d D=%d I=%d Z=%d C=%d\n",
        cpu.P.N,
        cpu.P.V,
        cpu.P.B,
        cpu.P.D,
        cpu.P.I,
        cpu.P.Z,
        cpu.P.C,
    )
}
