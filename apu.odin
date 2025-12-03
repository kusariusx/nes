package main

APU :: struct {
    frame_counter_flags: u8,
    frame_counter_sequencer: u16, // Count APU cycles

    status: u8,
}

apu_read_register :: proc(a: ^APU, address: u16) -> (value: u8, handled: bool) {
    switch address {
    case 0x4015: // Status
        value := a.status

        a.status &= ~u8(1 << 6) // Clear frame interrupt flag

        return value, true
    case 0x4017: // Frame counter
    }

    return 0, false
}

apu_write_register :: proc(a: ^APU, address: u16, value: u8) {
    switch address {
    case 0x4015: // Status
    case 0x4017: // Frame counter
        a.frame_counter_flags = value
        a.frame_counter_sequencer = 0
    }
}

apu_tick :: proc(a: ^APU, cpu_bus: ^NES_CPU_Bus) {
    frame_counter_mode := a.frame_counter_flags >> 7
    frame_counter_interrupt_inhibit := (a.frame_counter_flags >> 6) & 1

    a.frame_counter_sequencer += 1

    // Tick frame counter
    switch a.frame_counter_sequencer {
    case 3728:
    case 7456:
    case 11185:
    case 14914:
        if frame_counter_mode == 0 {
            a.frame_counter_sequencer = 0xFFFF // Set to 0xFFFF so it wraps around to 0 on next tick

            if frame_counter_interrupt_inhibit == 0 {
                a.status |= 1 << 6 // Set frame interrupt flag
            }
        }
    case 18640:
        if frame_counter_mode == 1 {
            a.frame_counter_sequencer = 0xFFFF
        }
    case 0:
        if frame_counter_mode == 0 && frame_counter_interrupt_inhibit == 0 {
            a.status |= 1 << 6
        }
    }
}
