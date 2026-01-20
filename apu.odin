package main

APU_DMC_Rate_Lookup := []u16{428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54}

APU_Length_Counter_Lookup := []u8 { 
    10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
}

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
    dmc_dma_halt_pending: bool,
    dmc_dma_dummy_read_address: u16,
    dmc_dma_halt_on_read: bool, // false means halt on write
    dmc_dma_active: bool,
    dmc_dma_cycle: u8,
    dmc_dma_aborted: bool,
    dmc_dma_sample_just_finished: bool,
    dmc_dma_sample_just_finished_prev: bool,

    dmc_toggle_delay: u8,
    dmc_toggle_pending_value: u8,
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

    triangle_length_counter: u8,
    triangle_length_counter_halt: bool,
}

apu_read_register :: proc(a: ^APU, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x4015: // Status
        a.will_clear_frame_interrupt = true

        status := APU_Status_Bits{
            pulse1 = 0,
            pulse2 = 0,
            triangle = a.triangle_length_counter > 0 ? 1 : 0,
            noise = 0,
            dmc = a.dmc_bytes_remaining > 0 ? 1 : 0,
            frame_interrupt = a.status.frame_interrupt,
            dmc_interrupt = a.status.dmc_interrupt,
        }

        return u8(status), 0b11011111 // Bit 5 is open bus
    case 0x4017: // Frame counter
    }

    return 0, 0
}

apu_write_register :: proc(a: ^APU, address: u16, value: u8) {
    switch address {
    case 0x4008: // Triangle channel length counter
        a.triangle_length_counter_halt = value >> 7 == 1
    case 0x400B:
        if a.status.triangle == 1 {
            a.triangle_length_counter = APU_Length_Counter_Lookup[value >> 3]
        }
    case 0x4010: 
        a.dmc_flags = value

        rate := value & 0xF
        a.dmc_rate = APU_DMC_Rate_Lookup[rate]

        if value & 0b10000000 == 0 {
            a.status.dmc_interrupt = 0
        }

        trace(.APU, "set DMC flags to %02X and rate to %v", value, a.dmc_rate)
    case 0x4011:
        a.dmc_output = value & 0x7F
    case 0x4012:
        a.dmc_sample_address = 0xC000 + u16(value) * 64
        trace(.APU, "set sample address to %04X", a.dmc_sample_address)
    case 0x4013:
        a.dmc_sample_length = u16(value) * 16 + 1
        trace(.APU, "set sample length to %v", a.dmc_sample_length)
    case 0x4015: // Status
        status := APU_Status_Bits(value)

        if status.triangle == 0 {
            a.triangle_length_counter = 0
        }

        a.dmc_toggle_pending_value = status.dmc
        a.dmc_toggle_delay = 2
        status.dmc = a.status.dmc // Preserve original bit

        status.frame_interrupt = a.status.frame_interrupt
        status.dmc_interrupt = 0

        a.status = status
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
        // 
        // Note: !dmc_dma_aborted condition is needed to prevent DMA re-trigger loop - when DMA is aborted, dmc_dma_cycle
        // is set to 0, leading to APU trying to start another DMA because the buffer is still empty.
        if a.dmc_sample_buffer_is_empty && !a.dmc_dma_aborted {
            regular_reload_dma := a.dmc_bytes_remaining > 0 && a.dmc_dma_cycle == 0
            
            // If DMC was disabled on a cycle preceding regular DMA schedule (dmc_toggle_delay == 1), DMA must be aborted.
            // Aborted DMA will still halt the CPU for 1 cycle in case it is not postponed due to landing on a write cycle.
            // Additionally, if the last bit of the DMC sample was processed on a preceding cycle, DMA must also be in aborted state.
            aborted_reload_dma := (regular_reload_dma && a.dmc_toggle_delay == 1 && a.dmc_toggle_pending_value == 0) || a.dmc_dma_sample_just_finished_prev

            if regular_reload_dma || aborted_reload_dma {
                trace(.APU, "requesting reload DMA")

                a.dmc_dma_pending = true
                a.dmc_dma_halt_on_read = false
            }

            a.dmc_dma_aborted = aborted_reload_dma
        }
    }

    // Tick DMC timer according to rate
    if a.dmc_rate_counter == 0 {
        trace(.APU, "DMC rate tick, rate = %v", a.dmc_rate)

        a.dmc_rate_counter = a.dmc_rate

        if !a.dmc_is_silence {
            trace(.APU, "DMC is not silenced, changing output according to delta")

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
            trace(.APU, "DMC sample completed")

            a.dmc_bits_remaining = 8

            if a.dmc_sample_buffer_is_empty {
                trace(.APU, "sample buffer is empty, silencing DMC")

                a.dmc_is_silence = true
            } else {
                trace(.APU, "buffer is not empty, emptying sample buffer into shifter")

                a.dmc_is_silence = false
                a.dmc_shifter = a.dmc_sample_buffer
                a.dmc_sample_buffer_is_empty = true
            }
        }
    }

    a.dmc_rate_counter -= 1

    // Things that need to happen "every APU cycle" (every other CPU cycle)
    if a.is_read_cycle {
        a.dmc_dma_sample_just_finished_prev = a.dmc_dma_sample_just_finished
        a.dmc_dma_sample_just_finished = false

        // Delayed DMC toggle
        if a.dmc_toggle_delay > 0 {
            a.dmc_toggle_delay -= 1
            if a.dmc_toggle_delay == 0 {
                a.status.dmc = a.dmc_toggle_pending_value

                if a.status.dmc == 0 {
                    a.dmc_bytes_remaining = 0
                } else if a.dmc_bytes_remaining == 0 {
                    trace(.APU, "restarting sample")
        
                    a.dmc_current_address = a.dmc_sample_address
                    a.dmc_bytes_remaining = a.dmc_sample_length
        
                    // Request first sample immediately
                    // Load DMA - halt CPU on read cycle
                    if a.dmc_sample_buffer_is_empty {
                        trace(.APU, "requesting load DMA")
        
                        a.dmc_dma_pending = true
                        a.dmc_dma_halt_on_read = true
                    }
                }

                // Reset once we toggled the DMC
                a.dmc_dma_aborted = false
            }
        }

        if a.will_clear_frame_interrupt || frame_counter_interrupt_inhibit == 1 {
            trace(.APU, "clearing frame interrupt flag")

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

    // Frame counter
    switch a.frame_counter {
    case 3728:
    case 7456:
        if !a.is_read_cycle {
            if !a.triangle_length_counter_halt && a.triangle_length_counter > 0 {
                a.triangle_length_counter -= 1
            }
        }
    case 11185:
    case 14914:
        if frame_counter_mode == 0 {
            trace(.APU, "setting frame interrupt flag")
            
            a.frame_counter = 0xFFFF // Set to 0xFFFF so it wraps around to 0 on next tick
            a.status.frame_interrupt = 1

            if !a.is_read_cycle {
                if !a.triangle_length_counter_halt && a.triangle_length_counter > 0 {
                    a.triangle_length_counter -= 1
                }
            }
        }
    case 18640:
        if frame_counter_mode == 1 {
            a.frame_counter = 0xFFFF

            if !a.is_read_cycle {
                if !a.triangle_length_counter_halt && a.triangle_length_counter > 0 {
                    a.triangle_length_counter -= 1
                }
            }
        }
    case 0:
        if a.is_read_cycle && frame_counter_mode == 0 && frame_counter_interrupt_inhibit == 0 {
            trace(.APU, "setting frame interrupt flag")
            
            a.status.frame_interrupt = 1
        }
    }
}
