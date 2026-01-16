package main

APU_DMC_Rate_Lookup := []u16{428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54}

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
    is_read_cycle: bool,
    
    status: APU_Status_Bits,

    frame_counter_flags: u8,
    frame_counter: u16, // Counter for APU cycles
    will_clear_frame_interrupt: bool,
    reset_frame_counter_delay: u8,

    dmc_dma_pending: bool,
    dmc_dma_halt_on_read: bool, // false means halt on write
    dmc_dma_active: bool,
    dmc_dma_cycle: u8,

    dmc_flags: u8,
    dmc_rate: u16, // Remember the rate instead of decoding it from rate index every time we need it
    dmc_rate_counter: u16,
    dmc_output: u8,
    dmc_is_silence: bool,
    dmc_sample_address: u16,
    dmc_sample_length: u16,
    dmc_current_address: u16,
    dmc_bytes_remaining: u16,
    dmc_sample_buffer: u8,
    dmc_sample_buffer_is_empty: bool,
    dmc_shifter: u8,
    dmc_bits_remaining: u8,
}

apu_read_register :: proc(a: ^APU, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x4015: // Status
        a.will_clear_frame_interrupt = true

        status := APU_Status_Bits{
            pulse1 = 0,
            pulse2 = 0,
            triangle = 0,
            noise = 0,
            dmc = a.dmc_bytes_remaining > 0 ? 1 : 0,
            frame_interrupt = a.status.frame_interrupt,
            dmc_interrupt = a.status.dmc_interrupt,
        }

        trace_apu("4015 read, returning %v", u8(status))

        return u8(status), 0b11011111 // Bit 5 is open bus
    case 0x4017: // Frame counter
    }

    return 0, 0
}

apu_write_register :: proc(a: ^APU, address: u16, value: u8) {
    switch address {
    case 0x4010: 
        a.dmc_flags = value

        rate := value & 0xF
        a.dmc_rate = APU_DMC_Rate_Lookup[rate]

        if value & 0b10000000 == 0 {
            a.status.dmc_interrupt = 0
        }

        trace_apu("set DMC flags to %02X and rate to %v", value, a.dmc_rate)
    case 0x4011:
        a.dmc_output = value & 0x7F
    case 0x4012:
        a.dmc_sample_address = 0xC000 + u16(value) * 64
        trace_apu("set sample address to %04X", a.dmc_sample_address)
    case 0x4013:
        a.dmc_sample_length = u16(value) * 16 + 1
        trace_apu("set sample length to %v", a.dmc_sample_length)
    case 0x4015: // Status
        trace_apu("4015 write, writing %v", value)

        a.status = APU_Status_Bits(value)

        a.status.dmc_interrupt = 0

        if a.status.dmc == 0 {
            a.dmc_bytes_remaining = 0
        } else if a.dmc_bytes_remaining == 0 {
            trace_apu("restarting sample on 4015 write")

            a.dmc_current_address = a.dmc_sample_address
            a.dmc_bytes_remaining = a.dmc_sample_length

            // Request first sample immediately
            // Load DMA - halt CPU on read cycle
            if a.dmc_sample_buffer_is_empty {
                trace_apu("requesting load DMA on 4015 write")

                a.dmc_dma_pending = true
                a.dmc_dma_halt_on_read = true
            }
        }
    case 0x4017: // Frame counter
        a.frame_counter_flags = value
        a.reset_frame_counter_delay = 3
    }
}

apu_tick :: proc(a: ^APU) {
    a.is_read_cycle = !a.is_read_cycle
    
    frame_counter_mode := a.frame_counter_flags >> 7
    frame_counter_interrupt_inhibit := (a.frame_counter_flags >> 6) & 1

    // DMC
    if a.status.dmc == 1 {
        // Request DMC DMA when buffer is empty
        // Reload DMA - halt CPU on write cycle
        if a.dmc_sample_buffer_is_empty && a.dmc_bytes_remaining > 0 && a.dmc_dma_cycle == 0 {
            trace_apu("requesting reload DMA")

            a.dmc_dma_pending = true
            a.dmc_dma_halt_on_read = false
        }
    }

    // Tick DMC timer according to rate
    if a.dmc_rate_counter == 0 {
        trace_apu("DMC rate tick, rate = %v", a.dmc_rate)

        a.dmc_rate_counter = a.dmc_rate

        if !a.dmc_is_silence {
            trace_apu("DMC is not silenced, changing output according to delta")

            direction := a.dmc_shifter & 1
            if direction == 1 && a.dmc_output <= 125 { // Output is capped to 0-127
                a.dmc_output += 2
            } else if direction == 0 && a.dmc_output >= 2 {
                a.dmc_output -= 2
            }
        }

        a.dmc_shifter >>= 1

        a.dmc_bits_remaining -= 1
        if a.dmc_bits_remaining == 0 { // New output cycle
            trace_apu("DMC sample completed")

            a.dmc_bits_remaining = 8

            if a.dmc_sample_buffer_is_empty {
                trace_apu("sample buffer is empty, silencing DMC")

                a.dmc_is_silence = true
            } else {
                trace_apu("buffer is not empty, emptying sample buffer into shifter")

                a.dmc_is_silence = false
                a.dmc_shifter = a.dmc_sample_buffer
                a.dmc_sample_buffer_is_empty = true
            }
        }
    }

    a.dmc_rate_counter -= 1

    // Frame counter
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
        if a.is_read_cycle && frame_counter_mode == 0 && frame_counter_interrupt_inhibit == 0 {
            a.status.frame_interrupt = 1
        }
    }
}
