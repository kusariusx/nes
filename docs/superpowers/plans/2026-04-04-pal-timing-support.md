# PAL Timing Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual NTSC or PAL console timing selection with accurate PAL CPU to PPU scheduling, PAL PPU frame geometry, PAL APU timing tables, and mode-aware UI and audio pacing without changing non-timing video behavior.

**Architecture:** Introduce a central `Console_Timing` profile resolved from a two-value `Console_Mode` enum. Store that profile on the NES and copy or reference it from subsystems that need it. Replace NTSC-only constants in the scheduler, PPU, APU, and UI/audio paths with data from the timing profile while keeping the framebuffer at `256x240` in both modes.

**Tech Stack:** Odin, SDL2, existing emulator test harness, Makefile-based build and test commands.

---

## File Structure

**Create:**

- `console_timing.odin` — central mode enum, timing profile struct, profile lookup, scheduler helper, and audio sample-budget helper.
- `console_timing_test.odin` — timing profile, scheduler, and PAL init regression tests.
- `apu_test.odin` — PAL APU table-selection tests.

**Modify:**

- `nes.odin` — accept a selected console mode, store resolved timing, remove PAL hard-failure behavior, and switch `nes_tick` to timing-driven PPU scheduling.
- `main.odin` — add the single app-level mode constant and pass it into `nes_init`.
- `ppu.odin` — replace hardcoded NTSC frame geometry and odd-frame skip logic with timing-profile fields.
- `apu.odin` — replace NTSC-only DMC, noise, and frame-counter timing assumptions with timing-profile values.
- `apu_lookup.odin` — split NTSC and PAL APU lookup tables.
- `ui.odin` — replace compile-time NTSC audio pacing constants with runtime timing-derived values and per-frame sample budgeting.
- `blip_buffer.odin` — make the blip buffer operate on a runtime sample count instead of a compile-time NTSC frame size.
- `cpu_test.odin` — pass explicit NTSC mode to existing tests.
- `ppu_test.odin` — add explicit timing to direct PPU tests if the struct gains a required field.

**Verification Commands:**

- `make test`
- `make build`

**Note:** Per user instruction, do not add git commit steps and do not create commits while executing this plan.

### Task 1: Add Console Mode and Timing Profile Plumbing

**Files:**

- Create: `console_timing.odin`
- Create: `console_timing_test.odin`
- Modify: `nes.odin`
- Modify: `main.odin`
- Modify: `cpu_test.odin`

- [ ] **Step 1: Write the failing timing-profile and PAL-init tests**

```odin
package main

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
```

- [ ] **Step 2: Run the tests to verify they fail for the right reason**

Run: `make test`

Expected: FAIL with missing identifiers such as `Console_Mode`, `Console_Timing`, `console_timing_for_mode`, or a `nes_init` signature mismatch.

- [ ] **Step 3: Add the timing types and plumb the selected mode through NES initialization**

```odin
package main

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
```

```odin
NES :: struct {
    timing: Console_Timing,
    ppu_master_clock_remainder: u8,
    // existing fields
}

nes_init :: proc(rom_data: []byte, mode: Console_Mode) -> (nes: ^NES, err: NES_Init_Error) {
    rom := rom_parse(rom_data) or_return
    timing := console_timing_for_mode(mode)

    // existing allocation path

    nes = new_clone(NES{
        rom = rom,
        ppu = ppu,
        apu = apu,
        cpu = cpu,
        ppu_bus = ppu_bus,
        cpu_bus = cpu_bus,
        io = io,
        timing = timing,
    }) or_return

    ppu.timing = timing
    apu.timing = timing

    return nes, nil
}
```

```odin
DEFAULT_CONSOLE_MODE :: Console_Mode.NTSC

nes, err_init := nes_init(rom_data, DEFAULT_CONSOLE_MODE)
```

Also update existing tests to call `nes_init(rom_data, .NTSC)`.

- [ ] **Step 4: Run the tests to verify this plumbing passes before timing behavior changes**

Run: `make test`

Expected: PASS. The new timing-profile tests pass, PAL init no longer fails, and all existing CPU tests still pass under explicit NTSC mode.

### Task 2: Replace Fixed 3x PPU Scheduling and PPU NTSC Geometry

**Files:**

- Modify: `console_timing.odin`
- Modify: `nes.odin`
- Modify: `ppu.odin`
- Modify: `console_timing_test.odin`
- Modify: `ppu_test.odin`

- [ ] **Step 1: Write the failing scheduler and PAL PPU frame-timing tests**

```odin
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
test_pal_ppu_wraps_after_312_scanlines_without_odd_skip :: proc(t: ^testing.T) {
    cpu := CPU{}
    bus := PPU_Bus{cpu = &cpu}
    ppu := PPU{
        timing = console_timing_for_mode(.PAL),
        PPUMASK = {b = 1},
        is_rendering_enabled = true,
        is_odd_frame = true,
        scanline = 311,
        scanline_cycle = 340,
    }

    ppu_tick(&ppu, &bus)

    testing.expect_value(t, ppu.scanline, u16(0))
    testing.expect_value(t, ppu.scanline_cycle, u16(0))
    testing.expect_value(t, ppu.is_odd_frame, false)
}
```

- [ ] **Step 2: Run the tests to verify they fail because scheduling and scanline constants are still NTSC-only**

Run: `make test`

Expected: FAIL in the new scheduler or PAL frame-wrap tests, with NTSC timing still hardcoded in `nes_tick` or `ppu_tick`.

- [ ] **Step 3: Implement timing-driven scheduling and replace NTSC-only PPU geometry constants**

```odin
Console_Tick_Scheduler :: struct {
    ppu_master_clock_remainder: u8,
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
```

```odin
nes_tick :: proc(nes: ^NES) {
    scheduler := Console_Tick_Scheduler{ppu_master_clock_remainder = nes.ppu_master_clock_remainder}
    ppu_ticks := console_timing_next_ppu_tick_count(&scheduler, nes.timing)
    nes.ppu_master_clock_remainder = scheduler.ppu_master_clock_remainder

    for _ in 0 ..< ppu_ticks {
        ppu_tick(nes.ppu, nes.ppu_bus)
    }

    apu_tick(nes.apu)
    cpu_tick(nes.cpu, nes.cpu_bus)

    if nes.cpu.is_read_cycle {
        peripheral_strobe(nes.io.ports[.Port_1])
        peripheral_strobe(nes.io.ports[.Port_2])
        peripheral_strobe(nes.io.ports[.Expansion_Port])
    }
}
```

```odin
is_visible_or_pre_render_scanline := p.scanline == p.timing.ppu_pre_render_scanline ||
    (p.scanline >= 0 && p.scanline < p.timing.ppu_visible_scanlines)

is_pre_render_scanline := p.scanline == p.timing.ppu_pre_render_scanline

if p.scanline_cycle == p.timing.ppu_dots_per_scanline {
    p.scanline_cycle = 0
    p.scanline += 1

    if p.scanline == p.timing.ppu_scanlines_per_frame {
        p.scanline = 0
        p.framebuffer_index = 0
        p.is_odd_frame = !p.is_odd_frame
    }
}
```

Use `p.timing.ppu_skip_odd_frame_dot` to gate the skipped pre-render dot so that it remains NTSC-only.

- [ ] **Step 4: Run the tests to verify PAL scheduler and PPU timing are correct and NTSC still passes**

Run: `make test`

Expected: PASS. PAL scheduler tests pass, PAL frame wrap uses 312 scanlines, PAL does not skip the odd-frame dot, and existing NTSC tests remain green.

### Task 3: Add PAL APU Tables and Frame-Counter Timing

**Files:**

- Create: `apu_test.odin`
- Modify: `apu_lookup.odin`
- Modify: `apu.odin`

- [ ] **Step 1: Write the failing PAL APU timing-selection tests**

```odin
package main

import "core:testing"

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
```

- [ ] **Step 2: Run the tests to verify they fail while APU still uses NTSC-only globals**

Run: `make test`

Expected: FAIL in the new PAL APU tests because `apu_write_register` still reads NTSC-only lookup tables or frame-counter code is still hardcoded.

- [ ] **Step 3: Split the NTSC and PAL tables and make APU timing use the selected profile**

```odin
APU_DMC_Period_Lookup_NTSC := [16]u16{428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54}
APU_DMC_Period_Lookup_PAL  := [16]u16{398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118, 98, 78, 66, 50}

APU_Noise_Period_Lookup_NTSC := [16]u16{4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068}
APU_Noise_Period_Lookup_PAL  := [16]u16{4, 8, 14, 30, 60, 88, 118, 148, 188, 236, 354, 472, 708, 944, 1890, 3778}
```

```odin
APU :: struct {
    timing: Console_Timing,
    // existing fields
}

// DMC
a.dmc_timer_period = a.timing.apu_dmc_periods[rate]

// Noise
a.noise_timer_period = a.timing.apu_noise_periods[value & 0xF] - 1
```

```odin
switch a.frame_counter {
case a.timing.apu_frame_counter_step_1:
    // existing quarter-frame behavior
case a.timing.apu_frame_counter_step_2:
    // existing half-frame behavior
case a.timing.apu_frame_counter_step_3:
    // existing quarter-frame behavior
case a.timing.apu_frame_counter_step_4:
    // existing step 4 behavior
case a.timing.apu_frame_counter_step_5:
    // existing 5-step terminal behavior
}
```

- [ ] **Step 4: Run the tests to verify PAL APU tables and frame timing are selected correctly**

Run: `make test`

Expected: PASS. PAL DMC and noise tests pass, PAL frame-counter thresholds are visible through the timing profile, and existing NTSC behavior remains unchanged under explicit NTSC mode.

### Task 4: Make UI and Audio Pacing Runtime-Aware

**Files:**

- Modify: `console_timing.odin`
- Modify: `ui.odin`
- Modify: `blip_buffer.odin`
- Modify: `main.odin`
- Modify: `console_timing_test.odin`

- [ ] **Step 1: Write the failing runtime audio-budget tests**

```odin
import "core:math"

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
```

- [ ] **Step 2: Run the tests to verify they fail while audio is still tied to compile-time NTSC constants**

Run: `make test`

Expected: FAIL because `audio_frame_budget_init`, `audio_frame_budget_next`, or runtime sample-count support does not exist yet.

- [ ] **Step 3: Replace compile-time NTSC audio sizing with runtime helpers and a runtime blip-buffer sample count**

```odin
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
```

```odin
Blip_Buffer :: struct {
    buffer: []f32,
    integrator_sum: f32,
}

blip_buffer_init :: proc(sample_capacity: int) -> Blip_Buffer {
    return Blip_Buffer{buffer = make([]f32, sample_capacity + BLIP_BUFFER_STEP_WIDTH)}
}

blip_buffer_prepare :: proc(b: ^Blip_Buffer, sample_count: int) {
    sum := b.integrator_sum
    for i in 0 ..< sample_count {
        sum += b.buffer[i]
        b.buffer[i] = sum
        sum *= BLIP_BUFFER_HIGH_PASS
    }
    b.integrator_sum = sum
}

blip_buffer_clear :: proc(b: ^Blip_Buffer, sample_count: int) {
    copy(b.buffer[:BLIP_BUFFER_STEP_WIDTH], b.buffer[sample_count:sample_count + BLIP_BUFFER_STEP_WIDTH])
    mem.zero_slice(b.buffer[BLIP_BUFFER_STEP_WIDTH:])
}
```

```odin
UI :: struct {
    audio_cycle_counter: f64,
    audio_cycles_per_sample: f64,
    audio_frame_budget: Audio_Frame_Budget,
    audio_sample_capacity: int,
    // existing fields
}

ui.audio_cycles_per_sample = f64(nes.timing.cpu_frequency_hz) / f64(AUDIO_SAMPLE_RATE)
ui.audio_frame_budget = audio_frame_budget_init(nes.timing, AUDIO_SAMPLE_RATE)
ui.audio_sample_capacity = int(math.ceil(ui.audio_frame_budget.samples_per_frame)) + 1
ui.audio_blip_buffer = blip_buffer_init(ui.audio_sample_capacity)
```

```odin
sample_count := audio_frame_budget_next(&ui.audio_frame_budget)
blip_buffer_prepare(&ui.audio_blip_buffer, sample_count)
sdl.QueueAudio(ui.audio_device_id, &ui.audio_blip_buffer.buffer[0], u32(sample_count) * size_of(f32))
blip_buffer_clear(&ui.audio_blip_buffer, sample_count)
ui.audio_cycle_counter = 0.0
```

Also replace the breakpoint delay path in `main.odin` so it uses the selected mode’s frame rate instead of the old NTSC-only `TARGET_FPS` constant.

- [ ] **Step 4: Run the full verification commands**

Run: `make test`

Expected: PASS. Timing profile, scheduler, PAL init, PAL APU, and audio-budget tests all pass.

Run: `make build`

Expected: PASS. The emulator builds successfully with mode-aware runtime timing and audio pacing.

- [ ] **Step 5: Checkpoint only, no git commit**

Record that verification passed and leave the worktree uncommitted, per user instruction.

## Self-Review Checklist

- Every requirement from the design spec is covered by at least one task.
- No task depends on a type or helper that is never introduced.
- No step instructs the worker to commit changes.
- All verification commands match the existing Makefile.
- NTSC regression safety is preserved by passing explicit NTSC mode in existing tests.