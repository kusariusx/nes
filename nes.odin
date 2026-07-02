package main

import "core:log"
import "core:mem"

NES :: struct {
    ppu: ^PPU,
    apu: ^APU,
    cpu: ^CPU,

    cpu_bus: ^CPU_Bus,
    ppu_bus: ^PPU_Bus,

    rom: ^ROM,
    mapper: Mapper,

    io: ^IO,

    timing: Console_Timing,

    ppu_master_clock_remainder: u8,

    breakpoint: bool,
}

NES_Init_Error :: union #shared_nil {
    mem.Allocator_Error,
    Parsing_Error,
    Mapper_Initialization_Error,
}

nes_init :: proc(rom_data: []byte, mode: Console_Mode) -> (nes: ^NES, err: NES_Init_Error) {
    rom := rom_parse(rom_data) or_return

    // Log a warning if the ROM's timing metadata does not match the selected mode
    if nes_20_data, ok := rom.header.format_specific_flags.(NES_20_Header_Data); ok {
        rom_timing := nes_20_data.flags_12.timing_mode
        switch rom_timing {
        case 1: // PAL
            if mode != .PAL {
                log.warnf("ROM specifies PAL timing but console is configured as %v", mode)
            }
        case 3: // Dendy
            log.warnf("ROM specifies Dendy timing; running in %v mode", mode)
        }
    }

    timing := console_timing_for_mode(mode)

    // Allocate components
    ppu := new(PPU) or_return
	apu := new(APU) or_return
    cpu := new(CPU) or_return
	ppu_bus := new(PPU_Bus) or_return
    cpu_bus := new(CPU_Bus) or_return
    io := new(IO) or_return

    // Allocate NES instance holding all components together
    nes = new_clone(NES{rom = rom, ppu = ppu, apu = apu, cpu = cpu, ppu_bus = ppu_bus, cpu_bus = cpu_bus, io = io, timing = timing}) or_return
    nes.mapper = mapper_init(nes) or_return

    ppu.timing = timing
    apu.timing = timing

    // Initialize links between components
    ppu_bus^ = {
        cpu = cpu,
        cpu_bus = cpu_bus,
        rom = rom,
        mapper = nes.mapper,
    }

    cpu_bus^ = {
        ppu = ppu,
        ppu_bus = ppu_bus,
        apu = apu,
        rom = rom,
        mapper = nes.mapper,
        io = io,
    }

    return nes, nil
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
    apu_reset(nes.apu)

    nes.breakpoint = false
}

// Generally equivalent to 1 CPU cycle
nes_tick :: proc(nes: ^NES) {
    scheduler := Console_Tick_Scheduler{ppu_master_clock_remainder = nes.ppu_master_clock_remainder}
    ppu_ticks := console_timing_next_ppu_tick_count(&scheduler, nes.timing)
    nes.ppu_master_clock_remainder = scheduler.ppu_master_clock_remainder

    for _ in 0 ..< ppu_ticks {
        ppu_tick(nes.ppu, nes.ppu_bus)
    }

    apu_tick(nes.apu)
    cpu_tick(nes.cpu, nes.cpu_bus)

    if nes.cpu.is_read_cycle { // Peripherals cannot be strobed on 2 consecutive cycles
        peripheral_strobe(nes.io.ports[.Port_1])
        peripheral_strobe(nes.io.ports[.Port_2])
        peripheral_strobe(nes.io.ports[.Expansion_Port])
    }
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

    for nes.cpu.instruction != nil { // Execute the rest of the instruction
        nes_tick(nes)
    }
}
