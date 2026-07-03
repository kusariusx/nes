# PAL Timing Support Design

## Goal

Add PAL console timing support to the emulator while preserving NTSC behavior, with mode selection controlled by a single manual `Console_Mode` enum.

## Requirements

- The user selects the console mode manually; ROM metadata does not auto-select the mode.
- The normal selection surface is a single app-level constant near startup code.
- The implementation covers hardware speed and timing only.
- PAL-specific visual behavior such as emphasis-bit reinterpretation, palette differences, and border behavior is out of scope.
- Dendy timing is out of scope.
- No git commits are made as part of this work.

## Current Constraints

- `nes_tick` currently hardcodes `3` PPU ticks per CPU tick, which matches NTSC only.
- `ppu.odin` hardcodes NTSC frame geometry:
  - visible scanlines `0..239`
  - post-render scanline `240`
  - VBlank start at `241`
  - pre-render scanline `261`
  - frame wrap at `262`
  - odd-frame skipped dot on the pre-render scanline
- `apu.odin` and `apu_lookup.odin` hardcode NTSC-only frame counter, DMC, and noise timing.
- `main.odin`, `ui.odin`, and `blip_buffer.odin` hardcode NTSC frame rate and audio pacing.
- `nes.odin` currently rejects NES 2.0 ROMs that declare PAL timing.

## Selected Approach

Introduce a central runtime timing profile derived from a two-value `Console_Mode` enum. The mode is selected once, resolved into a `Console_Timing` record once, and then consumed by `NES`, `PPU`, `APU`, `UI`, and audio code. This keeps the PAL/NTSC decision authoritative in one place and avoids scattering mode checks throughout the emulator.

## Core Types

Add a small timing/configuration layer with:

- `Console_Mode :: enum { NTSC, PAL }`
- `Console_Timing :: struct { ... }`

`Console_Timing` should hold the mode-specific values that are currently compile-time constants or hardcoded branches:

- `cpu_frequency_hz`
- `target_fps`
- `master_clocks_per_cpu_cycle`
- `master_clocks_per_ppu_dot`
- `ppu_dots_per_scanline`
- `ppu_visible_scanlines`
- `ppu_post_render_scanline`
- `ppu_vblank_start_scanline`
- `ppu_pre_render_scanline`
- `ppu_scanlines_per_frame`
- `ppu_skip_odd_frame_dot`
- PAL or NTSC DMC period lookup table
- PAL or NTSC noise period lookup table
- PAL or NTSC APU frame-counter thresholds

The timing profile should be stored on `NES` and referenced by subsystems that need it.

## Exact Timing Values

### NTSC profile

- CPU frequency: `1_789_773 Hz`
- Master clocks per CPU cycle: `12`
- Master clocks per PPU dot: `4`
- PPU dots per scanline: `341`
- Visible scanlines: `240`
- Post-render scanline: `240`
- VBlank start scanline: `241`
- Pre-render scanline: `261`
- Total scanlines per frame: `262`
- Odd-frame skipped dot: enabled when rendering is active
- Frame rate: `60.0988 Hz`
- DMC periods: `428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54`
- Noise periods: `4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068`
- APU frame counter thresholds:
  - mode 0: `3728`, `7456`, `11185`, `14914`
  - mode 1 terminal step: `18640`

### PAL profile

- CPU frequency: `1_662_607 Hz`
- Master clocks per CPU cycle: `16`
- Master clocks per PPU dot: `5`
- PPU dots per scanline: `341`
- Visible scanlines: `240`
- Post-render scanline: `240`
- VBlank start scanline: `241`
- Pre-render scanline: `311`
- Total scanlines per frame: `312`
- Odd-frame skipped dot: disabled
- Frame rate: `50.0070 Hz`
- DMC periods: `398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118, 98, 78, 66, 50`
- Noise periods: `4, 8, 14, 30, 60, 88, 118, 148, 188, 236, 354, 472, 708, 944, 1890, 3778`
- APU frame counter thresholds:
  - mode 0: `4156`, `8313`, `12469`, `16626`
  - mode 1 terminal step: `20782`

## Subsystem Design

### Startup and NES construction

- Add a single app-level constant in `main.odin`, for example `DEFAULT_CONSOLE_MODE :: Console_Mode.NTSC`.
- Pass the selected mode into `nes_init`.
- `nes_init` resolves the mode into a `Console_Timing` record and stores it on the `NES` instance.
- Existing tests and call sites should pass `Console_Mode.NTSC` explicitly unless they are testing PAL behavior.

### ROM metadata handling

- Keep parsing iNES and NES 2.0 timing fields exactly as today.
- Stop rejecting PAL NES 2.0 ROMs during initialization.
- Stop treating Dendy metadata as a hard failure for manual mode selection.
- ROM timing metadata becomes informational only for this feature.
- If a ROM declares PAL, multi-region, or Dendy timing and the selected manual mode differs, log the mismatch for debugging, but continue initialization.

### CPU to PPU scheduling

Replace the fixed `3` PPU ticks per CPU tick with an accumulator driven by hardware divisors.

Per CPU tick:

- add `timing.master_clocks_per_cpu_cycle` to an accumulator
- while the accumulator is at least `timing.master_clocks_per_ppu_dot`, tick the PPU once and subtract one PPU-dot worth of master clocks
- tick APU once
- tick CPU once

This preserves the exact NTSC behavior automatically and produces the PAL `3.2` average dot ratio without floating-point error or scattered PAL-specific branches.

### PPU frame geometry

Replace hardcoded NTSC frame constants in `ppu.odin` with fields read from `Console_Timing`.

The PPU must use the timing profile for:

- pre-render scanline detection
- VBlank start scanline
- frame completion scanline
- odd-frame skipped dot policy

The framebuffer remains `256x240` in both modes for this change. PAL-specific presentation differences such as the authentic 239-line picture and PAL border behavior are not part of this feature.

### APU timing

Move the DMC and noise period tables out of NTSC-only globals or select them through the timing profile.

`apu_update_frame_counter` must use timing-profile thresholds instead of hardcoded NTSC values:

- mode 0 quarter-frame and half-frame step points
- mode 1 terminal step point
- frame IRQ cadence derived from those thresholds

The write-reset behavior of `$4017` remains unchanged because the PAL source states that behavior is assumed to match NTSC.

### UI and audio pacing

Replace compile-time NTSC audio constants with runtime timing derived from the selected profile.

Required changes:

- compute `cpu_cycles_per_sample` from `timing.cpu_frequency_hz`
- compute target samples per frame from `AUDIO_SAMPLE_RATE / timing.target_fps`
- stop assuming that samples per frame are an integer
- carry fractional sample error across frames so PAL queues alternating sample counts that match the long-run average
- stop using a compile-time fixed audio buffer size tied to NTSC FPS
- make `Blip_Buffer` runtime-sized or sized from a safe maximum and pass the active sample count into prepare/clear/queue operations

This keeps audio output synchronized to PAL timing instead of dragging PAL emulation back toward NTSC pacing.

## Out of Scope

The following items are explicitly excluded from this feature:

- Dendy as a selectable execution mode
- PAL-specific PPUMASK emphasis-bit swapping
- PAL border color and overscan behavior
- PAL-specific DMC register-conflict behavior on the 2A07
- Other non-timing PAL hardware quirks beyond the timing values listed above

## Testing Strategy

Add focused tests that lock down the new behavior without rewriting the existing suite.

### Timing profile tests

- Verify NTSC profile fields match existing behavior.
- Verify PAL profile fields match the PAL values listed in this document.

### Scheduler tests

- Factor the CPU-to-PPU scheduler math behind a small helper or directly testable state update.
- Verify NTSC advances exactly `3` PPU dots per CPU tick.
- Verify PAL advances the correct accumulated number of PPU dots across multiple CPU ticks, such as `16` PPU dots after `5` CPU ticks.

### PPU timing tests

- Verify PAL mode wraps frames after `312` scanlines.
- Verify PAL mode uses scanline `311` as pre-render and does not perform the odd-frame skipped dot.
- Verify NTSC behavior remains unchanged.

### APU timing tests

- Verify PAL mode selects the PAL DMC period table.
- Verify PAL mode selects the PAL noise period table.
- Verify PAL frame-counter step thresholds are used.

### Initialization tests

- Verify a ROM with NES 2.0 PAL timing metadata can initialize successfully when mode is manually selected.
- Verify existing NTSC test ROM paths still initialize and run under explicit NTSC mode.

## Implementation Notes

- Prefer small, direct changes over large refactors.
- Keep public naming and style aligned with the existing project.
- Avoid introducing a generic auto-detection mode.
- Keep all PAL behavior sourced from one timing profile rather than repeated `if mode == .PAL` checks.

## Risks and Mitigations

- Risk: PAL scheduling changes could regress NTSC behavior.
  - Mitigation: keep NTSC explicit in tests and make scheduler math data-driven.
- Risk: audio pacing drift could appear because PAL samples-per-frame is fractional.
  - Mitigation: carry fractional sample remainder across frames and verify queue sizes over multiple frames.
- Risk: PAL support could accidentally widen scope into visual-format differences.
  - Mitigation: keep framebuffer shape and video-format quirks out of this change.

## Approval State

This document reflects the approved design discussed interactively on 2026-04-04.