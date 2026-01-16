package main

import "core:log"
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

    breakpoint: bool,
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

    // TODO: is this really needed?
    apu.dmc_bits_remaining = 8
    apu.dmc_sample_buffer_is_empty = true

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

    nes.breakpoint = false
}

// Generally equivalent to 1 CPU cycle
nes_tick :: proc(nes: ^NES) {
    // 3 PPU cycles for every CPU cycle
    ppu_tick(nes.ppu, nes.ppu_bus)
    ppu_tick(nes.ppu, nes.ppu_bus)
    ppu_tick(nes.ppu, nes.ppu_bus)

    apu_tick(nes.apu)
    cpu_tick(nes.cpu, nes.cpu_bus)
}

// Ticks the system enough to run one full CPU instruction
nes_debug_run_cpu_instruction :: proc(nes: ^NES) {
    // Finish with the current instruction in case this function was called mid-instruction
    for nes.cpu.instruction != nil {
        nes_tick(nes)
    }

    nes_tick(nes) // Run for 1 cycle to decode instruction

    // Print CPU state before the instruction is executed
    log.infof("------------------ CPU STATE ------------------")
    log.infof("P = %02X (%08b) | PC = %04X (%s)", byte(nes.cpu.P), byte(nes.cpu.P), nes.cpu.PC - 1, nes.cpu.instruction.mnemonic)
    log.infof("A = %02X | X = %02X | Y = %02X | S = %02X", nes.cpu.A, nes.cpu.X, nes.cpu.Y, nes.cpu.S)
    log.infof("-----------------------------------------------")

    for nes.cpu.instruction != nil { // Execture the rest of the instruction
        nes_tick(nes)
    }
}
