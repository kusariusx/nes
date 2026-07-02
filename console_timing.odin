package main

import "core:math"

Console_Mode :: enum {
    NTSC,
    PAL,
}

Console_Timing :: struct {
    mode: Console_Mode,
    cpu_frequency_hz: u64,
    target_fps: f64,
    master_clocks_per_cpu_cycle: u8,
    master_clocks_per_ppu_dot: u8,
    ppu_dots_per_scanline: u16,
    ppu_visible_scanlines: u16,
    ppu_post_render_scanline: u16,
    ppu_vblank_start_scanline: u16,
    ppu_pre_render_scanline: u16,
    ppu_scanlines_per_frame: u16,
    ppu_skip_odd_frame_dot: bool,
    apu_dmc_periods: [16]u16,
    apu_noise_periods: [16]u16,
    apu_frame_counter_step_1: u16,
    apu_frame_counter_step_2: u16,
    apu_frame_counter_step_3: u16,
    apu_frame_counter_step_4: u16,
    apu_frame_counter_step_5: u16,
}

Console_Tick_Scheduler :: struct {
    ppu_master_clock_remainder: u8,
}

Audio_Frame_Budget :: struct {
    samples_per_frame: f64,
    remainder: f64,
}

audio_frame_budget_init :: proc(timing: Console_Timing, sample_rate: int) -> Audio_Frame_Budget {
    return Audio_Frame_Budget{
        samples_per_frame = f64(sample_rate) / timing.target_fps,
    }
}

audio_frame_budget_next :: proc(budget: ^Audio_Frame_Budget) -> int {
    whole, frac := math.modf(budget.samples_per_frame + budget.remainder)
    budget.remainder = frac
    return int(whole)
}

console_timing_next_ppu_tick_count :: proc(state: ^Console_Tick_Scheduler, timing: Console_Timing) -> int {
    state.ppu_master_clock_remainder += timing.master_clocks_per_cpu_cycle

    ticks := 0
    for state.ppu_master_clock_remainder >= timing.master_clocks_per_ppu_dot {
        state.ppu_master_clock_remainder -= timing.master_clocks_per_ppu_dot
        ticks += 1
    }

    return ticks
}

console_timing_for_mode :: proc(mode: Console_Mode) -> Console_Timing {
    switch mode {
    case .NTSC:
        return Console_Timing{
            mode = .NTSC,
            cpu_frequency_hz = 1_789_773,
            target_fps = 60.0988,
            master_clocks_per_cpu_cycle = 12,
            master_clocks_per_ppu_dot = 4,
            ppu_dots_per_scanline = 341,
            ppu_visible_scanlines = 240,
            ppu_post_render_scanline = 240,
            ppu_vblank_start_scanline = 241,
            ppu_pre_render_scanline = 261,
            ppu_scanlines_per_frame = 262,
            ppu_skip_odd_frame_dot = true,
            apu_dmc_periods = APU_DMC_Period_Lookup_NTSC,
            apu_noise_periods = APU_Noise_Period_Lookup_NTSC,
            apu_frame_counter_step_1 = 3728,
            apu_frame_counter_step_2 = 7456,
            apu_frame_counter_step_3 = 11185,
            apu_frame_counter_step_4 = 14914,
            apu_frame_counter_step_5 = 18640,
        }
    case .PAL:
        return Console_Timing{
            mode = .PAL,
            cpu_frequency_hz = 1_662_607,
            target_fps = 50.0070,
            master_clocks_per_cpu_cycle = 16,
            master_clocks_per_ppu_dot = 5,
            ppu_dots_per_scanline = 341,
            ppu_visible_scanlines = 240,
            ppu_post_render_scanline = 240,
            ppu_vblank_start_scanline = 241,
            ppu_pre_render_scanline = 311,
            ppu_scanlines_per_frame = 312,
            ppu_skip_odd_frame_dot = false,
            apu_dmc_periods = APU_DMC_Period_Lookup_PAL,
            apu_noise_periods = APU_Noise_Period_Lookup_PAL,
            apu_frame_counter_step_1 = 4156,
            apu_frame_counter_step_2 = 8313,
            apu_frame_counter_step_3 = 12469,
            apu_frame_counter_step_4 = 16626,
            apu_frame_counter_step_5 = 20782,
        }
    }
    return {}
}
