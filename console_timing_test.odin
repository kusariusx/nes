package main

import "core:math"
import "core:testing"

@(test)
test_console_timing_profiles :: proc(t: ^testing.T) {
    ntsc := console_timing_for_mode(.NTSC)
    pal := console_timing_for_mode(.PAL)

    testing.expect_value(t, ntsc.cpu_frequency_hz, u64(1_789_773))
    testing.expect_value(t, ntsc.ppu_scanlines_per_frame, u16(262))
    testing.expect_value(t, ntsc.ppu_pre_render_scanline, u16(261))
    testing.expect_value(t, ntsc.ppu_skip_odd_frame_dot, true)

    testing.expect_value(t, pal.cpu_frequency_hz, u64(1_662_607))
    testing.expect_value(t, pal.ppu_scanlines_per_frame, u16(312))
    testing.expect_value(t, pal.ppu_pre_render_scanline, u16(311))
    testing.expect_value(t, pal.ppu_skip_odd_frame_dot, false)
}

@(test)
test_pal_scheduler_advances_16_ppu_dots_per_5_cpu_ticks :: proc(t: ^testing.T) {
    timing := console_timing_for_mode(.PAL)
    state := Console_Tick_Scheduler{}
    total := 0

    for _ in 0 ..< 5 {
        total += console_timing_next_ppu_tick_count(&state, timing)
    }

    testing.expect_value(t, total, 16)
}

@(test)
test_nes_init_accepts_pal_nes20_rom_in_manual_mode :: proc(t: ^testing.T) {
    rom_data := make([]u8, 16 + PRG_ROM_BANK_SIZE)
    defer delete(rom_data)

    rom_data[0] = 'N'
    rom_data[1] = 'E'
    rom_data[2] = 'S'
    rom_data[3] = 0x1A
    rom_data[4] = 1
    rom_data[7] = 0x08
    rom_data[12] = 0x01

    nes, err_init := nes_init(rom_data, .PAL)
    testing.expect_value(t, err_init, nil)
    testing.expect(t, nes != nil)

    if nes != nil {
        defer nes_free(nes)
        testing.expect_value(t, nes.timing.mode, Console_Mode.PAL)
    }
}

@(test)
test_pal_audio_budget_tracks_fractional_sample_counts :: proc(t: ^testing.T) {
    budget := audio_frame_budget_init(console_timing_for_mode(.PAL), AUDIO_SAMPLE_RATE)
    total := 0

    for _ in 0 ..< 1000 {
        total += audio_frame_budget_next(&budget)
    }

    expected := f64(AUDIO_SAMPLE_RATE) * 1000.0 / console_timing_for_mode(.PAL).target_fps
    testing.expect(t, math.abs(f64(total) - expected) < 1.0)
}

@(test)
test_ntsc_audio_budget_stays_close_to_profile_rate :: proc(t: ^testing.T) {
    budget := audio_frame_budget_init(console_timing_for_mode(.NTSC), AUDIO_SAMPLE_RATE)
    total := 0

    for _ in 0 ..< 1000 {
        total += audio_frame_budget_next(&budget)
    }

    expected := f64(AUDIO_SAMPLE_RATE) * 1000.0 / console_timing_for_mode(.NTSC).target_fps
    testing.expect(t, math.abs(f64(total) - expected) < 1.0)
}
