package main

APU_HIGH_PASS_FILTER_DECAY :: 0.996

APU_Status_Bits :: bit_field u8 {
    // Technically these flags control the length counters
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
    frame_counter_reset_delay: u8,

    dmc_dma_pending: bool,
    dmc_dma_halt_pending: bool,
    dmc_dma_dummy_read_address: u16,
    dmc_dma_halt_on_read: bool, // false means halt on write
    dmc_dma_cycle: u8,
    dmc_dma_aborted: bool,
    dmc_dma_sample_just_finished: bool,
    dmc_dma_sample_just_finished_prev: bool,

    dmc_toggle_delay: u8,
    dmc_toggle_pending_value: u8,
    dmc_irq_enabled: bool,
    dmc_loop: bool,
    dmc_timer_period: u16, // Remember the rate instead of decoding it from rate index every time we need it
    dmc_timer_counter: u16,
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

    pulse1_length_counter: u8,
    pulse1_length_counter_halt: bool, // Doubles as envelope loop flag
    pulse1_output: u8,
    pulse1_timer_period: u16,
    pulse1_timer_counter: u16,
    pulse1_duty_cycle: u8,
    pulse1_duty_cycle_position: u8,
    pulse1_envelope_period_volume: u8,
    pulse1_envelope_divider_counter: u8,
    pulse1_envelope_decay_counter: u8,
    pulse1_envelope_start: bool,
    pulse1_envelope_constant_volume: bool,
    pulse1_sweep_enabled: bool,
    pulse1_sweep_divider_period: u8,
    pulse1_sweep_divider_counter: u8,
    pulse1_sweep_negate: bool,
    pulse1_sweep_shift_count: u8,
    pulse1_sweep_reload: bool,
    pulse1_sweep_target_period: u16,

    pulse2_length_counter: u8,
    pulse2_length_counter_halt: bool, // Doubles as envelope loop flag
    pulse2_output: u8,
    pulse2_timer_period: u16,
    pulse2_timer_counter: u16,
    pulse2_duty_cycle: u8,
    pulse2_duty_cycle_position: u8,
    pulse2_envelope_period_volume: u8,
    pulse2_envelope_divider_counter: u8,
    pulse2_envelope_decay_counter: u8,
    pulse2_envelope_start: bool,
    pulse2_envelope_constant_volume: bool,
    pulse2_sweep_enabled: bool,
    pulse2_sweep_divider_period: u8,
    pulse2_sweep_divider_counter: u8,
    pulse2_sweep_negate: bool,
    pulse2_sweep_shift_count: u8,
    pulse2_sweep_reload: bool,
    pulse2_sweep_target_period: u16,

    triangle_length_counter: u8,
    triangle_length_counter_halt: bool, // Doubles as control flag
    triangle_output: u8,
    triangle_timer_period: u16,
    triangle_timer_counter: u16,
    triangle_linear_counter_reload: bool,
    triangle_linear_counter: u8,
    triangle_linear_counter_reload_value: u8,
    triangle_sequencer_position: u8,

    noise_length_counter: u8,
    noise_length_counter_halt: bool,
    noise_output: u8,
    noise_timer_period: u16,
    noise_timer_counter: u16,
    noise_mode: bool,
    noise_envelope_period_volume: u8,
    noise_envelope_divider_counter: u8,
    noise_envelope_decay_counter: u8,
    noise_envelope_start: bool,
    noise_envelope_constant_volume: bool,
    noise_lfsr: u16, // 15-bits wide

    mixer_output: f32,
    mixer_hpf_capacitor: f32,
}

apu_read_register :: proc(a: ^APU, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x4015: // Status
        a.will_clear_frame_interrupt = true

        status := APU_Status_Bits{
            pulse1 = a.pulse1_length_counter > 0 ? 1 : 0,
            pulse2 = a.pulse2_length_counter > 0 ? 1 : 0,
            triangle = a.triangle_length_counter > 0 ? 1 : 0,
            noise = a.noise_length_counter > 0 ? 1 : 0,
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
    case 0x4000:
        a.pulse1_duty_cycle = value >> 6
        a.pulse1_length_counter_halt = value & 0b00100000 != 0
        a.pulse1_envelope_constant_volume = value & 0b00010000 != 0
        a.pulse1_envelope_period_volume = value & 0xF
    case 0x4001:
        a.pulse1_sweep_enabled = value >> 7 == 1
        a.pulse1_sweep_divider_period = (value >> 4) & 0b111
        a.pulse1_sweep_negate = value & 0b00001000 != 0
        a.pulse1_sweep_shift_count = value & 0b111

        a.pulse1_sweep_reload = true
    case 0x4002:
        a.pulse1_timer_period = (a.pulse1_timer_period & 0xFF00) | u16(value) // Replace low byte of the timer
    case 0x4003:
        if a.status.pulse1 == 1 {
            a.pulse1_length_counter = APU_Length_Counter_Lookup[value >> 3]
        }

        // Replace high 3 bits of the timer
        a.pulse1_timer_period = (u16(value & 0b111) << 8) | (a.pulse1_timer_period & 0xFF)
        
        a.pulse1_timer_counter = a.pulse1_timer_period + 1 // The period of the timer is T + 1, not T!
        a.pulse1_duty_cycle_position = 0 // Restart sequencer
        a.pulse1_envelope_start = true
    case 0x4004:
        a.pulse2_duty_cycle = value >> 6
        a.pulse2_length_counter_halt = value & 0b00100000 != 0
        a.pulse2_envelope_constant_volume = value & 0b00010000 != 0
        a.pulse2_envelope_period_volume = value & 0xF
    case 0x4005:
        a.pulse2_sweep_enabled = value >> 7 == 1
        a.pulse2_sweep_divider_period = (value >> 4) & 0b111
        a.pulse2_sweep_negate = value & 0b00001000 != 0
        a.pulse2_sweep_shift_count = value & 0b111

        a.pulse2_sweep_reload = true
    case 0x4006:
        a.pulse2_timer_period = (a.pulse2_timer_period & 0xFF00) | u16(value)
    case 0x4007:
        if a.status.pulse2 == 1 {
            a.pulse2_length_counter = APU_Length_Counter_Lookup[value >> 3]
        }

        a.pulse2_timer_period = (u16(value & 0b111) << 8) | (a.pulse2_timer_period & 0xFF)
        
        a.pulse2_timer_counter = a.pulse2_timer_period + 1
        a.pulse2_duty_cycle_position = 0
        a.pulse2_envelope_start = true
    case 0x4008:
        a.triangle_length_counter_halt = value >> 7 == 1
        a.triangle_linear_counter_reload_value = value & 0b1111111
    case 0x400A:
        a.triangle_timer_period = (a.triangle_timer_period & 0xFF00) | u16(value)
    case 0x400B:
        if a.status.triangle == 1 {
            a.triangle_length_counter = APU_Length_Counter_Lookup[value >> 3]
        }

        a.triangle_timer_period = (u16(value & 0b111) << 8) | (a.triangle_timer_period & 0xFF)

        a.triangle_linear_counter_reload = true
    case 0x400C:
        a.noise_length_counter_halt = value & 0b00100000 != 0
        a.noise_envelope_constant_volume = value & 0b00010000 != 0
        a.noise_envelope_period_volume = value & 0xF
    case 0x400E:
        a.noise_mode = value & 0b10000000 != 0
        a.noise_timer_period = APU_Noise_Period_Lookup[value & 0xF] - 1
    case 0x400F:
        if a.status.noise == 1 {
            a.noise_length_counter = APU_Length_Counter_Lookup[value >> 3]
        }

        a.noise_envelope_start = true
    case 0x4010: 
        a.dmc_irq_enabled = value & 0b10000000 != 0
        a.dmc_loop = value & 0b01000000 != 0

        rate := value & 0xF
        a.dmc_timer_period = APU_DMC_Period_Lookup[rate]

        if !a.dmc_irq_enabled {
            a.status.dmc_interrupt = 0
        }

        trace(.APU, "set DMC flags to %02X and rate to %v", value, a.dmc_timer_period)
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

        // Force length counter to 0 when channel is disabled
        if status.pulse1 == 0 { a.pulse1_length_counter = 0 }
        if status.pulse2 == 0 { a.pulse2_length_counter = 0 }
        if status.triangle == 0 { a.triangle_length_counter = 0 }
        if status.noise == 0 { a.noise_length_counter = 0 }

        a.dmc_toggle_pending_value = status.dmc
        a.dmc_toggle_delay = 2

        status.dmc = a.status.dmc // Preserve original bit because the toggle is delayed
        status.frame_interrupt = a.status.frame_interrupt // Preserve frame interrupt
        status.dmc_interrupt = 0 // DMC interrupt is clean on read

        a.status = status
    case 0x4017: // Frame counter
        a.frame_counter_flags = value
        a.frame_counter_reset_delay = 3

        if a.frame_counter_flags >> 7 == 1 {
            apu_tick_length_counters(a)
            apu_tick_envelopes(a)
            apu_tick_sweeps(a)
            apu_tick_linear_counter(a)
        }
    }
}

apu_tick :: proc(a: ^APU) {
    a.is_read_cycle = !a.is_read_cycle

    apu_update_dmc(a)    
    apu_update_triangle(a)
    apu_update_noise(a)

    // Things that need to happen "every APU cycle" (every other CPU cycle)
    if a.is_read_cycle {
        a.dmc_dma_sample_just_finished_prev = a.dmc_dma_sample_just_finished
        a.dmc_dma_sample_just_finished = false

        // Delayed DMC toggle
        if a.dmc_toggle_delay > 0 {
            a.dmc_toggle_delay -= 1
            if a.dmc_toggle_delay == 0 {
                apu_toggle_dmc(a)
            }
        }
        
        apu_update_pulse(a)
        apu_mix_output(a)        
    }

    apu_update_frame_counter(a)
}

apu_update_frame_counter :: proc(a: ^APU) {
    frame_counter_mode := a.frame_counter_flags >> 7
    frame_counter_interrupt_inhibit := (a.frame_counter_flags >> 6) & 1

    if a.is_read_cycle {
        if a.will_clear_frame_interrupt || frame_counter_interrupt_inhibit == 1 {
            trace(.APU, "clearing frame interrupt flag")

            a.status.frame_interrupt = 0
            a.will_clear_frame_interrupt = false
        }

        if a.frame_counter_reset_delay > 0 {
            a.frame_counter_reset_delay -= 1
            if a.frame_counter_reset_delay == 0 {
                a.frame_counter = 0
            }
        }

        a.frame_counter += 1
    }

    switch a.frame_counter {
    case 3728:
        if !a.is_read_cycle {
            apu_tick_envelopes(a)
            apu_tick_linear_counter(a)
        }
    case 7456:
        if !a.is_read_cycle { 
            // Length counters are ticked on write/put cycles
            apu_tick_length_counters(a)
            apu_tick_envelopes(a)
            apu_tick_sweeps(a)
            apu_tick_linear_counter(a)
        }
    case 11185:
        if !a.is_read_cycle {
            apu_tick_envelopes(a)
            apu_tick_linear_counter(a)
        }
    case 14914:
        if frame_counter_mode == 0 { // 4-step mode
            trace(.APU, "setting frame interrupt flag")
            
            a.status.frame_interrupt = 1

            if !a.is_read_cycle {
                apu_tick_length_counters(a)
                apu_tick_envelopes(a)
                apu_tick_sweeps(a)
                apu_tick_linear_counter(a)

                // Set to 0xFFFF so it wraps around to 0 on next tick
                a.frame_counter = 0xFFFF
            }
        }
    case 18640:
        if frame_counter_mode == 1 { // 5-step mode
            if !a.is_read_cycle {
                apu_tick_length_counters(a)
                apu_tick_envelopes(a)
                apu_tick_sweeps(a)
                apu_tick_linear_counter(a)

                a.frame_counter = 0xFFFF
            }
        }
    case 0:
        if a.is_read_cycle && frame_counter_mode == 0 && frame_counter_interrupt_inhibit == 0 {
            trace(.APU, "setting frame interrupt flag")
            
            a.status.frame_interrupt = 1
        }
    }
}

apu_tick_length_counters :: proc(a: ^APU) {
    if !a.pulse1_length_counter_halt && a.pulse1_length_counter > 0 {
        a.pulse1_length_counter -= 1
        trace(.APU, "ticking pulse 1 length counter, now holds %d", a.pulse1_length_counter)
    }

    if !a.pulse2_length_counter_halt && a.pulse2_length_counter > 0 {
        a.pulse2_length_counter -= 1
        trace(.APU, "ticking pulse 2 length counter, now holds %d", a.pulse2_length_counter)
    }

    if !a.triangle_length_counter_halt && a.triangle_length_counter > 0 {
        a.triangle_length_counter -= 1
        trace(.APU, "ticking triangle length counter, now holds %d", a.triangle_length_counter)
    }

    if !a.noise_length_counter_halt && a.noise_length_counter > 0 {
        a.noise_length_counter -= 1
        trace(.APU, "ticking noise length counter, now holds %d", a.noise_length_counter)
    }
}

apu_tick_envelopes :: proc(a: ^APU) {
    // Pulse 1
    if !a.pulse1_envelope_start {
        if a.pulse1_envelope_divider_counter == 0 {
            a.pulse1_envelope_divider_counter = a.pulse1_envelope_period_volume + 1

            if a.pulse1_envelope_decay_counter > 0 {
                a.pulse1_envelope_decay_counter -= 1
            } else if a.pulse1_length_counter_halt {
                a.pulse1_envelope_decay_counter = 15
            }
        } else {
            a.pulse1_envelope_divider_counter -= 1
        }
    } else {
        a.pulse1_envelope_start = false
        a.pulse1_envelope_decay_counter = 15
        a.pulse1_envelope_divider_counter = a.pulse1_envelope_period_volume
    }

    // Pulse 2
    if !a.pulse2_envelope_start {
        if a.pulse2_envelope_divider_counter == 0 {
            a.pulse2_envelope_divider_counter = a.pulse2_envelope_period_volume + 1

            if a.pulse2_envelope_decay_counter > 0 {
                a.pulse2_envelope_decay_counter -= 1
            } else if a.pulse2_length_counter_halt {
                a.pulse2_envelope_decay_counter = 15
            }
        } else {
            a.pulse2_envelope_divider_counter -= 1
        }
    } else {
        a.pulse2_envelope_start = false
        a.pulse2_envelope_decay_counter = 15
        a.pulse2_envelope_divider_counter = a.pulse2_envelope_period_volume
    }

    // Noise
    if !a.noise_envelope_start {
        if a.noise_envelope_divider_counter == 0 {
            a.noise_envelope_divider_counter = a.noise_envelope_period_volume + 1

            if a.noise_envelope_decay_counter > 0 {
                a.noise_envelope_decay_counter -= 1
            } else if a.noise_length_counter_halt {
                a.noise_envelope_decay_counter = 15
            }
        } else {
            a.noise_envelope_divider_counter -= 1
        }
    } else {
        a.noise_envelope_start = false
        a.noise_envelope_decay_counter = 15
        a.noise_envelope_divider_counter = a.noise_envelope_period_volume
    }
}

apu_tick_sweeps :: proc(a: ^APU) {
    // Pulse 1
    pulse1_change_amount := a.pulse1_timer_period >> a.pulse1_sweep_shift_count
    if a.pulse1_sweep_negate {
        // Pulse1 uses one's complement, meaning it subtracts the value + 1
        if pulse1_change_amount + 1 > a.pulse1_timer_period {
            a.pulse1_sweep_target_period = 0
        } else {
            a.pulse1_sweep_target_period = a.pulse1_timer_period - pulse1_change_amount - 1
        }
    } else {
        a.pulse1_sweep_target_period = a.pulse1_timer_period + pulse1_change_amount
    }

    if a.pulse1_sweep_divider_counter == 0 && a.pulse1_sweep_enabled && a.pulse1_sweep_shift_count > 0 {
        muting := a.pulse1_timer_period < 8 || a.pulse1_sweep_target_period > 0x7FF
        if !muting {
            a.pulse1_timer_period = a.pulse1_sweep_target_period
        }
    }

    if a.pulse1_sweep_divider_counter == 0 || a.pulse1_sweep_reload {
        a.pulse1_sweep_divider_counter = a.pulse1_sweep_divider_period
        a.pulse1_sweep_reload = false
    } else {
        a.pulse1_sweep_divider_counter -= 1
    }

    // Pulse 2
    pulse2_change_amount := a.pulse2_timer_period >> a.pulse2_sweep_shift_count
    if a.pulse2_sweep_negate {
        // Pulse2 uses two's complement, meaning just subtracts the value
        if pulse2_change_amount > a.pulse2_timer_period {
            a.pulse2_sweep_target_period = 0
        } else {
            a.pulse2_sweep_target_period = a.pulse2_timer_period - pulse2_change_amount
        }
    } else {
        a.pulse2_sweep_target_period = a.pulse2_timer_period + pulse2_change_amount
    }

    if a.pulse2_sweep_divider_counter == 0 && a.pulse2_sweep_enabled && a.pulse2_sweep_shift_count > 0 {
        muting := a.pulse2_timer_period < 8 || a.pulse2_sweep_target_period > 0x7FF
        if !muting {
            a.pulse2_timer_period = a.pulse2_sweep_target_period
        }
    }

    if a.pulse2_sweep_divider_counter == 0 || a.pulse2_sweep_reload {
        a.pulse2_sweep_divider_counter = a.pulse2_sweep_divider_period
        a.pulse2_sweep_reload = false
    } else {
        a.pulse2_sweep_divider_counter -= 1
    }
}

apu_tick_linear_counter :: proc(a: ^APU) {
    if a.triangle_linear_counter_reload {
        a.triangle_linear_counter = a.triangle_linear_counter_reload_value
    } else if a.triangle_linear_counter > 0 {
        a.triangle_linear_counter -= 1
    }

    if !a.triangle_length_counter_halt {
        a.triangle_linear_counter_reload = false
    }
}

apu_update_pulse :: proc(a: ^APU) {
    // Pulse 1
    if a.pulse1_timer_counter == 0 {
        a.pulse1_timer_counter = a.pulse1_timer_period
        a.pulse1_duty_cycle_position = (a.pulse1_duty_cycle_position + 1) & 0x7 // Tick sequencer
    } else {
        a.pulse1_timer_counter -= 1
    }

    if a.pulse1_length_counter == 0 || a.pulse1_timer_period < 8 || a.pulse1_sweep_target_period > 0x7FF {
        a.pulse1_output = 0
    } else {
        pulse1_volume := a.pulse1_envelope_constant_volume ? a.pulse1_envelope_period_volume : a.pulse1_envelope_decay_counter
        a.pulse1_output = APU_Pulse_Duty_Cycle_Lookup[a.pulse1_duty_cycle][a.pulse1_duty_cycle_position] * pulse1_volume
    }

    // Pulse 2
    if a.pulse2_timer_counter == 0 {
        a.pulse2_timer_counter = a.pulse2_timer_period
        a.pulse2_duty_cycle_position = (a.pulse2_duty_cycle_position + 1) & 0x7
    } else {
        a.pulse2_timer_counter -= 1
    }

    if a.pulse2_length_counter == 0 || a.pulse2_timer_period < 8 || a.pulse2_sweep_target_period > 0x7FF {
        a.pulse2_output = 0
    } else {
        pulse2_volume := a.pulse2_envelope_constant_volume ? a.pulse2_envelope_period_volume : a.pulse2_envelope_decay_counter
        a.pulse2_output = APU_Pulse_Duty_Cycle_Lookup[a.pulse2_duty_cycle][a.pulse2_duty_cycle_position] * pulse2_volume
    }
}

apu_update_triangle :: proc(a: ^APU) {
    if a.triangle_linear_counter > 0 && a.triangle_length_counter > 0 {
        if a.triangle_timer_counter == 0 {
            a.triangle_timer_counter = a.triangle_timer_period
            a.triangle_sequencer_position = (a.triangle_sequencer_position + 1) & 0x1F
        } else {
            a.triangle_timer_counter -= 1
        }

        a.triangle_output = APU_Triangle_Sequence_Lookup[a.triangle_sequencer_position]
    }
}

apu_update_noise :: proc(a: ^APU) {
    if a.noise_timer_counter == 0 {
        a.noise_timer_counter = a.noise_timer_period
        
        feedback_bit: u8 = a.noise_mode ? 6 : 1
        feedback := (a.noise_lfsr & 1) ~ ((a.noise_lfsr >> feedback_bit) & 1)
        a.noise_lfsr = (feedback << 14) | (a.noise_lfsr >> 1)
    } else {
        a.noise_timer_counter -= 1
    }

    if a.noise_length_counter == 0 || a.noise_lfsr & 1 == 1 {
        a.noise_output = 0
    } else {
        a.noise_output = a.noise_envelope_constant_volume ? a.noise_envelope_period_volume : a.noise_envelope_decay_counter
    }
}

apu_update_dmc :: proc(a: ^APU) {
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

    if a.dmc_timer_counter == 0 {
        trace(.APU, "DMC rate tick, rate = %v", a.dmc_timer_period)

        a.dmc_timer_counter = a.dmc_timer_period

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
    
    a.dmc_timer_counter -= 1
}

apu_toggle_dmc :: proc(a: ^APU) {
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

apu_mix_output :: proc(a: ^APU) {
    pulse_output := APU_Mixer_Pulse_Lookup[a.pulse1_output + a.pulse2_output]
    triangle_noise_dmc_output := APU_Mixer_Triangle_Noise_DMC_Lookup[3 * a.triangle_output + 2 * a.noise_output + a.dmc_output]

    raw_output := pulse_output + triangle_noise_dmc_output

    // Apply high-pass filter to prevent sudden signal changes
    filtered_output := raw_output - a.mixer_hpf_capacitor
    a.mixer_hpf_capacitor = raw_output - filtered_output * APU_HIGH_PASS_FILTER_DECAY

    a.mixer_output = filtered_output
}
