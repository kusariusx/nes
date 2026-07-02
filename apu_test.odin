package main

import "core:testing"

@(test)
test_ntsc_apu_uses_ntsc_dmc_and_noise_tables :: proc(t: ^testing.T) {
    apu := APU{timing = console_timing_for_mode(.NTSC)}

    apu_write_register(&apu, 0x4010, 0x0F)
    testing.expect_value(t, apu.dmc_timer_period, u16(54))

    apu_write_register(&apu, 0x400E, 0x0F)
    testing.expect_value(t, apu.noise_timer_period, u16(4067))
}

@(test)
test_pal_apu_uses_pal_dmc_and_noise_tables :: proc(t: ^testing.T) {
    apu := APU{timing = console_timing_for_mode(.PAL)}

    apu_write_register(&apu, 0x4010, 0x0F)
    testing.expect_value(t, apu.dmc_timer_period, u16(50))

    apu_write_register(&apu, 0x400E, 0x0F)
    testing.expect_value(t, apu.noise_timer_period, u16(3777))
}

@(test)
test_pal_apu_exposes_pal_frame_counter_thresholds :: proc(t: ^testing.T) {
    timing := console_timing_for_mode(.PAL)

    testing.expect_value(t, timing.apu_frame_counter_step_1, u16(4156))
    testing.expect_value(t, timing.apu_frame_counter_step_2, u16(8313))
    testing.expect_value(t, timing.apu_frame_counter_step_3, u16(12469))
    testing.expect_value(t, timing.apu_frame_counter_step_4, u16(16626))
    testing.expect_value(t, timing.apu_frame_counter_step_5, u16(20782))
}
