package main

APU_Status_Bits :: bit_field u8 {
    pulse1:          u8 | 1,
    pulse2:          u8 | 1,
    triangle:        u8 | 1,
    noise:           u8 | 1,
    dmc:             u8 | 1,
    _:               u8 | 1, // Open bus on this bit
    frame_interrupt: u8 | 1,
    dmc_interrupt:   u8 | 1,
}

APU :: struct {
    frame_counter_flags: u8,
    frame_counter: u16, // Count APU cycles

    is_read_cycle: bool,

    will_clear_frame_interrupt: bool,

    reset_frame_counter_delay: u8,

    status: APU_Status_Bits,
}

apu_read_register :: proc(a: ^APU, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x4015: // Status
        a.will_clear_frame_interrupt = true
        return u8(a.status), 0b11011111 // Bit 5 is open bus
    case 0x4017: // Frame counter
    }

    return 0, 0
}

apu_write_register :: proc(a: ^APU, address: u16, value: u8) {
    switch address {
    case 0x4015: // Status
    case 0x4017: // Frame counter
        a.frame_counter_flags = value
        a.reset_frame_counter_delay = 3
    }
}

apu_tick :: proc(a: ^APU) {
    a.is_read_cycle = !a.is_read_cycle
    
    frame_counter_mode := a.frame_counter_flags >> 7
    frame_counter_interrupt_inhibit := (a.frame_counter_flags >> 6) & 1

    if a.is_read_cycle {
        if a.will_clear_frame_interrupt || frame_counter_interrupt_inhibit == 1 {
            a.status.frame_interrupt = 0
            a.will_clear_frame_interrupt = false
        }

        if a.reset_frame_counter_delay > 0 {
            a.reset_frame_counter_delay -= 1
            if a.reset_frame_counter_delay == 0 {
                a.frame_counter = 0
            }
        }

        a.frame_counter += 1
    }

    // Tick frame counter
    switch a.frame_counter {
    case 3728:
    case 7456:
    case 11185:
    case 14914:
        if frame_counter_mode == 0 {
            a.frame_counter = 0xFFFF // Set to 0xFFFF so it wraps around to 0 on next tick
            a.status.frame_interrupt = 1
        }
    case 18640:
        if frame_counter_mode == 1 {
            a.frame_counter = 0xFFFF
        }
    case 0:
        if frame_counter_mode == 0 && frame_counter_interrupt_inhibit == 0 {
            a.status.frame_interrupt = 1
        }
    }
}
