package main

import "core:simd"
import "base:intrinsics"

PPU_USE_OPTIMIZED_PROCS :: true

// IO bus decays to 0 after 3-30 milliseconds
PPU_IO_BUS_DECAY_TIME :: 16129 // Approximately 3 milliseconds

// Rendering is not enabled/disabled immediately after writing to PPUMASK - the effect is delayed by 3-4 cycles.
// Chose 4 to be able to pass some obscure PPU tests, but most of the software does not rely on this delay.
PPU_RENDERING_TOGGLE_DELAY :: 4

PPUCTRL_Bits :: bit_field u8 {
    NN: u8 | 2, // Base nametable address (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
    I:  u8 | 1, // VRAM address increment per CPU read/write of PPUDATA (0: add 1, going across; 1: add 32, going down)
    S:  u8 | 1, // Sprite pattern table address for 8x8 sprites (0: $0000; 1: $1000; ignored in 8x16 mode)
    B:  u8 | 1, // Background pattern table address (0: $0000; 1: $1000)
    H:  u8 | 1, // Sprite size (0: 8x8 pixels; 1: 8x16 pixels – see PPU OAM#Byte 1)
    P:  u8 | 1, // PPU master/slave select (0: read backdrop from EXT pins; 1: output color on EXT pins)
    V:  u8 | 1, // Vblank NMI enable (0: off, 1: on)
}

PPUMASK_Bits :: bit_field u8 {
    g: u8 | 1, // Greyscale (0: normal color, 1: greyscale)
    m: u8 | 1, // 1: Show background in leftmost 8 pixels of screen, 0: Hide
    M: u8 | 1, // 1: Show sprites in leftmost 8 pixels of screen, 0: Hide
    b: u8 | 1, // 1: Enable background rendering
    s: u8 | 1, // 1: Enable sprite rendering
    R: u8 | 1, // Emphasize red (green on PAL/Dendy)
    G: u8 | 1, // Emphasize green (red on PAL/Dendy)
    B: u8 | 1, // Emphasize blue
}

PPUSTATUS_Bits :: bit_field u8 {
    _: u8 | 5, // PPU open bus
    O: u8 | 1, // Sprite overflow flag
    S: u8 | 1, // Sprite 0 hit flag
    V: u8 | 1, // Vblank flag, cleared on read
}

PPU :: struct {
    PPUCTRL:   PPUCTRL_Bits,
    PPUMASK:   PPUMASK_Bits,
    PPUSTATUS: PPUSTATUS_Bits,
    OAMADDR:   u8, 
    OAMDATA:   u8,
    PPUSCROLL: u8, // X and Y scroll (first write - X, second write - Y) 
    PPUADDR:   u8, // VRAM address (14-bit value, bits 8-13 on first write, bits 0-7 on second write)
    PPUDATA:   u8,

    is_rendering_enabled: bool,
    rendering_toggle_delay: u8,

    ppudata_read_buffer: u8,
    io_bus_value: u8,
    io_bus_decay_counter: u16,

    // Internal PPU registers
    v: u16, // Current VRAM address (15 bits)
    t: u16, // Temporary VRAM address (15 bits)
    x: u8,  // Fine X scroll (3 bits)
    w: u8,  // First or second write toggle (1 bit)

    // Shift registers used for drawing.
    // Every dot/cycle, the high 8 bits of these are used to construct data for 1 pixel: 
    // 2-bit color and 2-bit palette number. After that, they are shifted right.
    bg_shifter_pattern_low: u16,  // Holds low bit of 2-bit color code for 16 pixels (2 tiles)
    bg_shifter_pattern_high: u16, // Holds high bit of 2-bit color code
    bg_shifter_palette_low: u16,  // Holds low bit of 2-bit palette number for 16 pixels
    bg_shifter_palette_high: u16, // Holds high bit of 2-bit palette number

    // Internal latches used to pre-fetch background data for the next tile.
    // Every 8 cycles, these latches are used to fill the low 8 bits of shift registers with data for the next tile.
    bg_next_tile_id: u8,           // Fetched from nametable
    bg_next_tile_palette: u8,      // Only 2 bits used - all pixels in a tile share the same palette
    bg_next_tile_pattern_low: u8,  // Low bits of 2-bit color codes
    bg_next_tile_pattern_high: u8, // High bits of 2-bit color codes

    is_odd_frame: bool,
    scanline_cycle: u16, // Current cycle/dot inside a scanline
    scanline: u16,       // Current scanline
    
    sprite_eval_sprite_byte: u8,
    sprite_eval_oam_data: u8,
    sprite_eval_found: u8, // How many sprites we have found for a scanline
    sprite_eval_secondary_oam_pos: u8,
    sprite_eval_done: bool,
    sprite_eval_pending_reads: u8, // To mark that we need to read 3 more OAM bytes during overflow phase
    sprite_eval_sprite_0_present: bool, // Is sprite 0 present during evaluation (will be drawn on the next scanline)

    sprite_0_on_current_scanline: bool,

    // Shifters for sprite drawing
    sprite_shifter_pattern_low: [8]u8, 
    sprite_shifter_pattern_high: [8]u8, 
    sprite_attributes: [8]u8,
    sprite_x_position: [8]u8, // These will be decrementing each rendering cycle; when 0 - sprite becomes active/visible

    // Latches to temporary store fetched sprite data
    sprite_y_position: u8,
    sprite_tile_number: u8,

    // This is used to indicate that VBL is "technically" already set, even though PPUSTATUS.V is not yet set.
    // This is needed to overcome sequential nature of the emulator - components run one by one in the same thread
    // (3 times PPU, 1 time CPU), while real hardware components run in parallel.
    // In concrete terms, this variable is needed to communicate to the CPU that VBL was set "simultaneously" while
    // it is running.
    // Most of the time, this variable is false. It is only true when PPU *reaches* the 1st cycle of 241st scanline, and
    // is set back to false when it is processed (when PPUSTATUS.V is actually set). From CPU's point of view, this
    // variable is true only in a narrow window when the *last* (of total 3) PPU cycle has reached the 1st cycle of 241st scanline. 
    // This variable is also used to implement VBL set suppression - it is set to false whenever PPUSTATUS is read.
    will_set_vbl: bool,

    // Same purpose and reasoning as above, but to let CPU know the VBL has been cleared simultaneously during its tick.
    will_clear_ppustatus: bool,

    // Same as above, but to let CPU know that the concurrent PPU cycle is about to be skipped.
    will_skip_cycle: bool,

    oam: [256]u8, // Object Attribute Memory
    secondary_oam: [32]u8,
    oam_corruption_seed: u8,
    oam_data_latch: u8,

    framebuffer_index: int,
    framebuffer: [256 * 240]u8,
}

ppu_read_register :: proc(p: ^PPU, b: ^PPU_Bus, reg: u8) -> u8 {
    is_visible_or_pre_render_scanline := p.scanline == 261 || (p.scanline >= 0 && p.scanline <= 239)

    switch reg {
    case 2: // PPUSTATUS
        value := p.PPUSTATUS

        if p.will_clear_ppustatus {
            value.S = 0
            value.O = 0

            // Special case: don't clear VBL since CPU has to know its actual value even when it was cleared
            // at the exact same cycle.
        }

        // Reading PPUSTATUS has some side effects
        p.PPUSTATUS.V = 0
        p.w = 0

        // Reading VBL suppresses setting it
        p.will_set_vbl = false

        // Only bits 5-7 of the value are loaded onto the bus, others are left unchanged
        p.io_bus_value = (p.io_bus_value & 0x1F) | (u8(value) & 0xE0)
    case 4: // OAMDATA
        // During rendering, the PPU's internal OAM data bus is continuously updated by sprite
        // evaluation/fetching logic. Reading $2004 returns whatever value is on that bus.
        if p.is_rendering_enabled && is_visible_or_pre_render_scanline {
            p.io_bus_value = p.oam_data_latch
        } else {
            // When not rendering, just return the value from OAM[OAMADDR]
            p.io_bus_value = ppu_read_oam(p, update_latch = false)
        }
    case 7: // PPUDATA
        // Read current data
        value := ppu_bus_read(b, p.v)
        result: u8

        // Special handling for palette RAM - these reads are unbuffered
        if p.v >= 0x3F00 && p.v <= 0x3FFF {
            // Return unbuffered data
            // Also, palette RAM holds 6-bit values and not 8-bit, so the high 2 bits are PPU open bus
            result = (p.io_bus_value & 0xC0) | (value & 0x3F)

            // When reading palette memory, the internal buffer is not filled with palette data,
            // but with data "underneath" the palette memory in PPU address space - this is usually the 
            // mirrored nametable. Subtract 0x1000 to mirror 0x3XXX addresses into 0x2XXX.
            p.ppudata_read_buffer = ppu_bus_read(b, p.v - 0x1000)
        } else {
            // Return data from the internal buffer, i.e. all reads are delayed
            result = p.ppudata_read_buffer

            // Update buffer with current read
            p.ppudata_read_buffer = value
        }

        // Increment v
        if p.is_rendering_enabled && is_visible_or_pre_render_scanline { // Bugged increment logic
            ppu_increment_coarse_x(p)
            ppu_increment_y(p)
        } else { // Regular increment logic
            p.v += p.PPUCTRL.I == 0 ? 1 : 32
        }

        ppu_bus_set_address(b, p.v)

        p.io_bus_value = result
    case:
        // Don't reset decay counter
        return p.io_bus_value
    }

    // We have loaded something onto the bus - reset decay counter
    p.io_bus_decay_counter = PPU_IO_BUS_DECAY_TIME
    return p.io_bus_value
}

ppu_write_register :: proc(p: ^PPU, b: ^PPU_Bus, reg: u8, value: u8) {
    // Regardless of the register (even read-only), value is loaded onto the I/O bus
    p.io_bus_value = value
    p.io_bus_decay_counter = PPU_IO_BUS_DECAY_TIME

    is_visible_scanline := p.scanline >= 0 && p.scanline <= 239
    is_visible_or_pre_render_scanline := is_visible_scanline || p.scanline == 261

    switch reg {
    case 0: // PPUCTRL
        p.PPUCTRL = PPUCTRL_Bits(value)

        // Update bits 10 and 11 of PPU's internal t register
        p.t = (p.t & 0xF3FF) | (u16(p.PPUCTRL.NN) << 10)
    case 1: // PPUMASK
        p.PPUMASK = PPUMASK_Bits(value)

        new_is_rendering_enabled := p.PPUMASK.b == 1 || p.PPUMASK.s == 1

        // Rendering was disabled during visible scanline - OAM corruption
        if is_visible_scanline && p.is_rendering_enabled && !new_is_rendering_enabled { 
            p.oam_corruption_seed = p.sprite_eval_secondary_oam_pos << 3
        }

        // Rendering was toggled
        if p.is_rendering_enabled != new_is_rendering_enabled {
            p.rendering_toggle_delay = PPU_RENDERING_TOGGLE_DELAY
        }
    case 3: // OAMADDR
        p.OAMADDR = value
    case 4: // OAMDATA
        if p.is_rendering_enabled && is_visible_or_pre_render_scanline {
            // Hardware bug - OAM is not writable during visible and pre-render scanline, and also OAMADDR
            // is incorrectly incremented by 4.
            p.OAMADDR = (p.OAMADDR + 4) & 0xFC
        } else {
            p.oam[p.OAMADDR] = value
            p.OAMADDR += 1 // Will wrap automatically since OAMADDR is u8
        }
    case 5: // PPUSCROLL
        // Note: I could've stored these values in separate variables - it would've been simpler.
        // But I want to emulate the original hardware behavior, so I'm using PPU internal registers to
        // store these values (in rather obscure format).

        // Note: t and v are 15-bit registers, but I'm using full 16-bit masks for clarity
        // Odin allows underscores in numeric literals - very convenient for separating bytes.

        if p.w == 0 { // First write (X scroll)
            p.x = value & 0b111 // Set fine X scroll
            p.t = (p.t & 0b11111111_11100000) | (u16(value) >> 3) // Set coarse X scroll
            p.w = 1 // Toggle w
        } else { // Second write (Y scroll)
            p.t = (p.t & 0b10001111_11111111) | (u16(value & 0b00000111) << 12) // Set fine Y scroll
            p.t = (p.t & 0b11111100_00011111) | (u16(value & 0b11111000) << 2) // Set coarse Y scroll
            p.w = 0 // Toggle w back
        }
    case 6: // PPUADDR
        if p.w == 0 { // First write (high byte)
            p.t = (p.t & 0b10000000_11111111) | (u16(value & 0b00111111) << 8) // Set bits 8-13 and clear bit 14
            p.w = 1 // Toggle w
        } else { // Second write (low byte)
            p.t = (p.t & 0b11111111_00000000) | u16(value) // Set bits 0-7
            p.v = p.t // Copy t into v
            p.w = 0 // Toggle w back

            ppu_bus_set_address(b, p.v)
        }
    case 7: // PPUDATA
        ppu_bus_write(b, p.v, value)

        // Increment v
        if p.is_rendering_enabled && is_visible_or_pre_render_scanline { // Bugged increment logic
            ppu_increment_coarse_x(p)
            ppu_increment_y(p)
        } else { // Regular increment logic
            p.v += p.PPUCTRL.I == 0 ? 1 : 32
        }

        ppu_bus_set_address(b, p.v)
    }
}

// PPU runs 3x faster than CPU, so for each CPU tick, we tick PPU 3 times
ppu_tick :: proc(p: ^PPU, b: ^PPU_Bus) {
    ppu_handle_delayed_events(p)

    // Handle skipped cycle
    if p.will_skip_cycle {
        p.scanline_cycle += 1
        p.will_skip_cycle = false
    }
   
    switch p.scanline {
    case 0 ..= 239, 261: // Visible scanlines and pre-render scanline
        // Joining visible and pre-render scanlines because a lot of identical things happen on both of them

        is_pre_render_scanline := p.scanline == 261
        is_visible_scanline := !is_pre_render_scanline

        is_rendering_cycle := p.scanline_cycle >= 1 && p.scanline_cycle <= 256

        if is_pre_render_scanline {
            switch p.scanline_cycle {
            case 0:
                p.will_clear_ppustatus = true
            case 1:
                p.will_clear_ppustatus = false

                // The three PPUSTATUS flags are automatically cleared on dot 1 of the pre-render scanline
                p.PPUSTATUS.V = 0
                p.PPUSTATUS.S = 0
                p.PPUSTATUS.O = 0
            case 338:
                // Pre-render scanline varies in length, could be 341 or 340 cycles long. All other scanlines are 341 cycles long.
                // Note: skipping condition does not depend on delayed rendering toggle, but on actual values in PPUMASK.
                if p.is_odd_frame && (p.PPUMASK.s == 1 || p.PPUMASK.b == 1) {
                    p.will_skip_cycle = true
                }
            }
        }

        // Regardless of whether rendering is enabled or disabled, reset secondary OAM position 
        // so that stale values do not pass onto the next frame.
        if p.scanline_cycle == 1 || p.scanline_cycle == 257 {
            p.sprite_eval_secondary_oam_pos = 0
        }

        if p.is_rendering_enabled {
            is_prefetch_cycle := p.scanline_cycle >= 321 && p.scanline_cycle <= 336

            // Handle OAM corruption - copy 8 OAM bytes into the first 8 bytes of OAM. Target bytes are determind by the
            // corruption "seed" set when rendering is disabled during visible scanline.
            // Corruption happens when rendering is "really" enabled and not in "pending toggle" state.
            if p.oam_corruption_seed != 0 && p.rendering_toggle_delay == 0 {
                copy(p.oam[p.oam_corruption_seed:p.oam_corruption_seed+8], p.oam[0:8])
                p.oam_corruption_seed = 0
            }

            // During idle/prefetch cycles, the PPU reads secondary_oam[0] onto the internal OAM data bus
            if p.scanline_cycle == 0 || is_prefetch_cycle {
                p.oam_data_latch = p.secondary_oam[0]
            }

            if is_visible_scanline && is_rendering_cycle {
                ppu_rendering(p, b)
                ppu_sprite_evaluation(p)
            }

            // Sprite fetching happens on both visible scanlines and pre-render scanline
            if p.scanline_cycle >= 257 && p.scanline_cycle <= 320 {
                ppu_sprite_fetching(p, b)
            }

            // Background fetching happens on both visible scanlines and pre-render scanline
            if is_rendering_cycle || is_prefetch_cycle {
                ppu_background_fetching(p, b)
            }
            
            switch p.scanline_cycle {
            case 256:
                ppu_increment_y(p)
            case 257:
                ppu_transfer_x(p)

                // After sprite evaluation and rendering, remember sprite 0 presense to be able 
                // to detect sprite 0 hit on the next scanline.
                p.sprite_0_on_current_scanline = p.sprite_eval_sprite_0_present
            case 280 ..= 304:
                if is_pre_render_scanline {
                    ppu_transfer_y(p)
                }
            }
        }

        // Decrement sprite X counters - this happens even when rendering is disabled
        if is_visible_scanline && is_rendering_cycle {
            #unroll for i in 0 ..< 8 {
                p.sprite_x_position[i] -= u8(p.sprite_x_position[i] > 0)
            }
        }
    case 240: // Post-render scanline
        // PPU is idle during this scanline
    case 241: // Start of VBlank (lasts during scanlines 241-260)
        if p.scanline_cycle == 0 {
            p.will_set_vbl = true
        } else if p.scanline_cycle == 1 && p.will_set_vbl {
            // Set VBlank flag on the second cycle of 241st scanline
            p.PPUSTATUS.V = 1
            p.will_set_vbl = false
        }
    }

    p.scanline_cycle += 1

    if p.scanline_cycle == 341 { // Scanline is completed
        p.scanline_cycle = 0
        p.scanline += 1

        if p.scanline == 262 { // Frame is completed
            p.scanline = 0
            p.framebuffer_index = 0
            p.is_odd_frame = !p.is_odd_frame
        }
    }

    // It is possible for PPU cycle to happen simultaneously with interrupt polling. Some IRQ sources
    // like MMC3 mapper (which observes 12th bit on the PPU's address bus) trigger an IRQ during the PPU cycle,
    // and we need to somehow let the CPU know that an IRQ line went up, even though CPU wasn't able to detect it
    // because of the sequential nature of the emulator (CPU runs strictly after the PPU, but in reality they all
    // run at the same time).
    b.cpu.just_polled_interrupts = false
}

ppu_handle_delayed_events :: proc(p: ^PPU) {
    // Handle IO bus value decay
    mask := u8(p.io_bus_decay_counter == 1) - 1 // 0 when decay counter reaches 0, 0xFF otherwise
    p.io_bus_decay_counter -= u16(p.io_bus_decay_counter > 0)
    p.io_bus_value &= mask // Mask with 0 when decay counter is 0, mask with 0xFF otherwise

    // Handle delayed rendering toggle
    should_toggle := p.rendering_toggle_delay == 1
    p.rendering_toggle_delay -= u8(p.rendering_toggle_delay > 0)
    p.is_rendering_enabled ~= should_toggle // When counter reaches zero, flip the flag by XOR'ing with 1
}

ppu_background_fetching :: proc(p: ^PPU, b: ^PPU_Bus) {
    switch p.scanline_cycle % 8 {
    case 1:
        when PPU_USE_OPTIMIZED_PROCS {
            ppu_load_background_shifters_optimized(p)
        } else {
            ppu_load_background_shifters(p)
        }

        p.bg_next_tile_id = ppu_fetch_background_nametable_byte(p, b)
    case 3:
        p.bg_next_tile_palette = ppu_fetch_background_attribute_byte(p, b)
    case 5:
        p.bg_next_tile_pattern_low = ppu_fetch_background_pattern_byte(p, b, p.bg_next_tile_id, LOW)
    case 7:
        p.bg_next_tile_pattern_high = ppu_fetch_background_pattern_byte(p, b, p.bg_next_tile_id, HIGH)
    case 0:
        ppu_increment_coarse_x(p)
    }

    when PPU_USE_OPTIMIZED_PROCS {
        ppu_shift_background_registers_optimized(p)
    } else {
        ppu_shift_background_registers(p)
    }
}

ppu_rendering :: proc(p: ^PPU, b: ^PPU_Bus) {
    is_background_enabled := p.PPUMASK.b == 1
    is_sprite_enabled := p.PPUMASK.s == 1

    pixel_x := p.scanline_cycle - 1

    color, palette: u16
    background_color, background_palette: u16
    sprite_color, sprite_palette, sprite_priority: u8

    // Handle disable flag and "show leftmost 8 pixels" flag, extract pixels
    if !is_background_enabled || (pixel_x < 8 && p.PPUMASK.m == 0) {
        background_color, background_palette = 0, 0
    } else {
        when PPU_USE_OPTIMIZED_PROCS {
            background_color, background_palette = ppu_get_background_pixel_optimized(p)
        } else {
            background_color, background_palette = ppu_get_background_pixel(p)
        }
    }

    if !is_sprite_enabled || (pixel_x < 8 && p.PPUMASK.M == 0) {
        sprite_color, sprite_palette, sprite_priority = 0, 0, 0
    } else {
        when PPU_USE_OPTIMIZED_PROCS {
            sprite_color, sprite_palette, sprite_priority = ppu_get_sprite_pixel_optimized(p)
        } else {
            sprite_color, sprite_palette, sprite_priority = ppu_get_sprite_pixel(p)
        }
    }

    // Sprite 0 hit detection
    if p.sprite_0_on_current_scanline && p.PPUSTATUS.S == 0 {
        possible_sprite_0_hit := // Sprite 0 is hit when...
            p.sprite_x_position[0] == 0 && // Sprite 0 is active
            is_sprite_enabled && // Sprite rendering is enabled - we need to check this because we read sprite data directly from shifters
            background_color != 0 && // Background is opaque (sprite pixel will be checked below)
            // Sprite 0 hit is not detected when rendering is disabled for leftmost 8 pixels.
            // We are either in the safe zone where this restriction does not apply (pixel_x >= 8),
            // Or both background and sprites are enabled in this zone.
            (pixel_x >= 8 || (p.PPUMASK.m == 1 && p.PPUMASK.M == 1)) &&
            pixel_x != 255 // Due to hardware specifics, sprite 0 hit cannot occur at X = 255

        if possible_sprite_0_hit {
            // If sprite 0 is present on the current scanline, it is guaranteed to be first in our shifters/latches
            sprite_0_bit_0 := p.sprite_shifter_pattern_low[0] >> 7
            sprite_0_bit_1 := p.sprite_shifter_pattern_high[0] >> 7
            sprite_0_color := (sprite_0_bit_1 << 1) | sprite_0_bit_0

            if sprite_0_color != 0 {
                p.PPUSTATUS.S = 1
            }
        }
    }

    // After pixel extraction and sprite 0 hit detection, shift active sprites
    #unroll for i in 0 ..< 8 {
        // Since there are no branches (the condition is encoded as a shift of 0 or 1), compiler is
        // able to efficiently vectorize this code. With explicit if's, the generated code is
        // completely unoptimized.
        shift := u8(p.sprite_x_position[i] == 0)
            
        p.sprite_shifter_pattern_low[i] <<= shift
        p.sprite_shifter_pattern_high[i] <<= shift
    }

    // Determine what pixel to draw
    if (sprite_color != 0 && sprite_priority == 0) || background_color == 0 { // Sprite pixel wins
        color, palette = u16(sprite_color), u16(sprite_palette)
    } else { // Background pixel wins
        color, palette = background_color, background_palette
    }

    // Calculate palette RAM address
    // If color is 0, it's transparent - use backdrop color
    palette_entry: u16
    if color == 0 {
        palette_entry = 0 // Backdrop color
    } else {
        palette_entry = (palette << 2) + color
    }

    color_index := ppu_bus_read_palette_ram(b, palette_entry)
    
    // Write to framebuffer
    p.framebuffer[p.framebuffer_index] = color_index
    p.framebuffer_index += 1
}

ppu_sprite_fetching :: proc(p: ^PPU, b: ^PPU_Bus) {
    sprite_idx := p.sprite_eval_secondary_oam_pos >> 2
    
    // When we have less than 8 sprites on a scanline, we still perform all this fetches but discard
    // those dummy sprites during rendering.
    switch p.scanline_cycle % 8 {
    case 1: // Read Y
        p.sprite_y_position = p.secondary_oam[p.sprite_eval_secondary_oam_pos]
        p.oam_data_latch = p.sprite_y_position
        p.sprite_eval_secondary_oam_pos += 1
        ppu_fetch_background_nametable_byte(p, b) // Dummy nametable fetch (at cycles 1-2)
    case 2: // Read tile number
        p.sprite_tile_number = p.secondary_oam[p.sprite_eval_secondary_oam_pos]
        p.oam_data_latch = p.sprite_tile_number
        p.sprite_eval_secondary_oam_pos += 1
    case 3: // Read attributes
        p.sprite_attributes[sprite_idx] = p.secondary_oam[p.sprite_eval_secondary_oam_pos]
        p.oam_data_latch = p.sprite_attributes[sprite_idx]
        p.sprite_eval_secondary_oam_pos += 1
        ppu_fetch_background_nametable_byte(p, b) // Dummy nametable fetch (at cycles 3-4)
    case 4: // Read X
        p.sprite_x_position[sprite_idx] = p.secondary_oam[p.sprite_eval_secondary_oam_pos]
        p.oam_data_latch = p.sprite_x_position[sprite_idx]

        // Not incrementing secondary OAM position because that would incorrectly increment sprite_idx
    case 5: // Fetch pattern low (takes 2 cycles)
        p.sprite_shifter_pattern_low[sprite_idx] = ppu_fetch_sprite_pattern_byte(p, b, sprite_idx, LOW)
    case 7: // Fetch pattern high (takes 2 cycles)
        p.sprite_shifter_pattern_high[sprite_idx] = ppu_fetch_sprite_pattern_byte(p, b, sprite_idx, HIGH)

        // After we are done with the current sprite, we can make a final increment
        p.sprite_eval_secondary_oam_pos += 1

        // Even for left-over sprites (those that cointain $FF data), we still have to do all memory fetches.
        // The data is then discarded.
        discard_sprite := sprite_idx >= p.sprite_eval_found

        is_pre_render_scanline := p.scanline == 261
        sprite_height := int(p.PPUCTRL.H == 0 ? 8 : 16)

        // Edge case - under some conditions it is possible to draw sprites on scanline 0, namely when sprites
        // are fetched during pre-render scanline and are in-range for scanline 261 & 0xFF = 5.
        // So, check whether sprite is in range, and replace its pattern with transparent data in case it isn't.
        if is_pre_render_scanline {
            sprite_y := int(p.sprite_y_position)
            sprite_in_range := 5 >= sprite_y && 5 < sprite_y + sprite_height

            if !sprite_in_range { // Clear stale pattern data - sprite should not be drawn
                discard_sprite = true
            }
        }

        if discard_sprite { 
            p.sprite_shifter_pattern_low[sprite_idx] = 0
            p.sprite_shifter_pattern_high[sprite_idx] = 0

            if sprite_idx == 0 { // In case we accidentally triggered a sprite 0 hit
                p.sprite_0_on_current_scanline = false
            }
        }
    }

    // OAM address is reset on every cycle of sprite fetching
    p.OAMADDR = 0
}

// Reads OAM byte from OAMADDR and updates internal OAM latch
ppu_read_oam :: proc(p: ^PPU, update_latch := true) -> u8 {
    oam_data := p.oam[p.OAMADDR]
    if p.OAMADDR % 4 == 2 { // Attribute bits 2-4 don't physically exist in OAM
        oam_data &= 0b11100011 
    }

    if update_latch {
        p.oam_data_latch = oam_data
    }

    return oam_data
}

ppu_sprite_evaluation :: proc(p: ^PPU) {
    is_odd_cycle := p.scanline_cycle % 2 == 1

    to_next_sprite :: proc(p: ^PPU) {
        p.OAMADDR += 4
        if p.OAMADDR >> 2 == 0 {
            p.sprite_eval_done = true
        }

        p.sprite_eval_sprite_byte = 0
    }

    to_next_byte :: proc(p: ^PPU) {
        p.OAMADDR += 1

        if p.sprite_eval_sprite_byte == 3 {
            if p.OAMADDR >> 2 == 0 {
                p.sprite_eval_done = true
            }

            p.sprite_eval_sprite_byte = 0
        } else {
            p.sprite_eval_sprite_byte += 1
        }
    }

    switch p.scanline_cycle {
    case 1: // Sprite evaluation has just started, reset state
        p.sprite_eval_sprite_byte = 0
        p.sprite_eval_found = 0
        p.sprite_eval_pending_reads = 0
        p.sprite_eval_done = false
        p.sprite_eval_sprite_0_present = false

        // We still have some stuff to do on cycle 1
        fallthrough
    case 1 ..= 64: // Secondary OAM clearing
        // The internal OAM data bus reads 0xFF during this phase (hardware forces reads to 0xFF)
        p.oam_data_latch = 0xFF

        if is_odd_cycle {
            // Dummy read from OAM
            // Note: since OAM is not accessed through the bus (i.e. read has no side effects), 
            // we can probably just do nothing here?
        } else {
            // Write 0xFF to secondary OAM
            p.secondary_oam[p.sprite_eval_secondary_oam_pos] = 0xFF
            p.sprite_eval_secondary_oam_pos = (p.sprite_eval_secondary_oam_pos + 1) & 0x1F
        }
    case 65 ..= 256: // Sprite evaluation
        sprite_height := u16(p.PPUCTRL.H == 0 ? 8 : 16)

        if p.sprite_eval_done {
            if is_odd_cycle {
                // Dummy read n-th sprite from OAM
                ppu_read_oam(p)
            } else {
                p.oam_data_latch = p.secondary_oam[p.sprite_eval_secondary_oam_pos]
                to_next_sprite(p)
            }

            // Just burn cycles until we reach cycle 257

            break
        }

        // On odd cycles, data is read from OAM
        if is_odd_cycle {
            p.sprite_eval_oam_data = ppu_read_oam(p)
            break
        }
        
        // Secondary OAM is full - overflow phase
        if p.sprite_eval_secondary_oam_pos == 32 {
            if p.sprite_eval_pending_reads > 0 {
                // Dummy read the OAM

                to_next_byte(p)
                p.sprite_eval_pending_reads -= 1
            } else {
                // Evaluate data as a Y position. Due to hardware bug leading to m being incremented together with n,
                // data will not always be the 0-th byte of a sprite, but we still evaluate it as such.
                sprite_y := u16(p.sprite_eval_oam_data)
                sprite_in_range := p.scanline >= sprite_y && p.scanline < sprite_y + sprite_height

                if sprite_in_range {
                    // Set overflow flag because we have found more than 8 in-range sprites
                    p.PPUSTATUS.O = 1

                    to_next_byte(p)

                    // Request to read 3 next OAM bytes without evaluating them, effectively skipping to the next sprite
                    p.sprite_eval_pending_reads = 3
                } else {
                    // Hardware bug - increment both n and m independently (no carry between them).
                    // This leads to random data (tile index, attributes, X position) being evaluated
                    // as Y position, leading to random changes in overflow flag.
                    new_n := ((p.OAMADDR >> 2) + 1) & 0x3F
                    new_m := ((p.OAMADDR & 0x03) + 1) & 0x03
                    p.OAMADDR = u8((new_n << 2) | new_m)
                    
                    p.sprite_eval_sprite_byte = (p.sprite_eval_sprite_byte + 1) & 0x03
                    
                    if new_n == 0 {
                        p.sprite_eval_done = true
                    }
                }
            }

            break
        }

        // Secondary OAM is not full - update state and write to secondary OAM
        switch p.sprite_eval_sprite_byte {
        case 0: // Started processing a new sprite (0-th byte, Y position)
            // We write Y to secondary OAM regardless of whether the sprite is in range or not.
            // If not in range, it will be just overwritten by the next sprite.
            p.secondary_oam[p.sprite_eval_secondary_oam_pos] = p.sprite_eval_oam_data

            sprite_y := u16(p.sprite_eval_oam_data)
            sprite_in_range := p.scanline >= sprite_y && p.scanline < sprite_y + sprite_height
            
            if sprite_in_range {
                p.sprite_eval_found += 1
                p.sprite_eval_secondary_oam_pos += 1

                if p.scanline_cycle == 66 {
                    p.sprite_eval_sprite_0_present = true
                }

                to_next_byte(p)
            } else {
                to_next_sprite(p)
            }
        case 1, 2, 3: // Processing tile index, attributes, or X position
            // Copy byte to secondary OAM
            p.secondary_oam[p.sprite_eval_secondary_oam_pos] = p.sprite_eval_oam_data
            p.sprite_eval_secondary_oam_pos += 1

            to_next_byte(p)
        }
    }
}

// Finds sprite pixel that needs to be drawn.
// This function does not account for priority attribute bit - sprite pixel still has to be
// evaluated against background to determine which one to draw.
ppu_get_sprite_pixel :: proc(p: ^PPU) -> (color: u8, palette: u8, priority: u8) {
    for i in 0 ..< 8 {
        if p.sprite_x_position[i] != 0 { // Skip if sprite is not yet active
            continue
        }
        
        bit_0 := p.sprite_shifter_pattern_low[i] >> 7
        bit_1 := p.sprite_shifter_pattern_high[i] >> 7
        color = (bit_1 << 1) | bit_0
        
        if color != 0 { // Opaque/non-transparent
            palette = (p.sprite_attributes[i] & 0x03) + 4 // Bits 0-1, encode values 4-7
            priority = (p.sprite_attributes[i] >> 5) & 1 // Bit 5
            
            // Sprites earlier in the OAM have higher priority, so we can return the first opaque pixel we find
            return
        }
    }
    
    return 0, 0, 0 // No opaque sprite found
}

ppu_get_sprite_pixel_optimized :: proc(p: ^PPU) -> (color, palette, priority: u8) {
    sprite_x_position := simd.from_array(p.sprite_x_position)
    sprite_shifter_pattern := simd.from_array(p.sprite_shifter_pattern_low) | simd.from_array(p.sprite_shifter_pattern_high)

    is_active := simd.lanes_eq(sprite_x_position, #simd [8]u8{})
    is_opaque := simd.lanes_gt(sprite_shifter_pattern, #simd [8]u8{0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F})

    valid := is_active & is_opaque

    bit_positions := #simd[8]u8{128, 64, 32, 16, 8, 4, 2, 1}
    masked_bits := valid & bit_positions
    
    valid_mask := simd.reduce_or(masked_bits)
    if valid_mask == 0 {
        return
    }

    first_valid_sprite_idx := intrinsics.count_leading_zeros(valid_mask)

    bit_0 := p.sprite_shifter_pattern_low[first_valid_sprite_idx] >> 7
    bit_1 := p.sprite_shifter_pattern_high[first_valid_sprite_idx] >> 7
    color = (bit_1 << 1) | bit_0
        
    palette = (p.sprite_attributes[first_valid_sprite_idx] & 0x03) + 4 // Bits 0-1, encode values 4-7
    priority = (p.sprite_attributes[first_valid_sprite_idx] >> 5) & 1 // Bit 5
            
    return
}

ppu_fetch_sprite_pattern_byte :: proc(p: ^PPU, b: ^PPU_Bus, sprite_idx: u8, plane: u16) -> u8 {
    attributes := p.sprite_attributes[sprite_idx]

    // Mask with (sprite_height - 1) to keep the value within 0-7/0-15 range.
    // This will be important for dummy sprite fetches where the Y coordinate is 0xFF.
    // In such cases, row might be negative, which will lead to wrap-around when casting to u16 during address calculation.
    sprite_height := u16(p.PPUCTRL.H == 0 ? 8 : 16)
    row := (p.scanline - u16(p.sprite_y_position)) & (sprite_height - 1)
    
    address: u16

    if sprite_height == 8 {
        if attributes & 0x80 != 0 { // Vertical flip
            row = 7 - row
        }

        address = u16(p.PPUCTRL.S) * 0x1000 + (u16(p.sprite_tile_number) << 4) + u16(row)
    } else {
        // We ignore PPUCTRL.S for 16-pixel sprites, and use 0-th bit of tile number as a pattern table number
        address = u16(p.sprite_tile_number & 1) * 0x1000
        tile := p.sprite_tile_number

        if attributes & 0x80 != 0 { // Vertical flip
            row = 15 - row
        }

        if row < 8 {
            tile &= 0xFE // Switch to top tile
        } else {
            tile |= 1 // Switch to bottom tile
            row -= 8 // Normalize row to a single 8x8 tile
        }

        address += (u16(tile) << 4) + u16(row)
    }

    address += plane * 8
    pattern := ppu_bus_read(b, address)

    if attributes & 0x40 != 0 { // Horizontal flip
        pattern = intrinsics.reverse_bits(pattern)
    }
    
    return pattern
}

// Every 8 cycles, we increment the coarse X to go to the next tile within the scanline.
ppu_increment_coarse_x :: proc(p: ^PPU) {
    if (p.v & 0x001F) == 31 { // If coarse X == 31
        p.v &= ~u16(0x001F) // Coarse X = 0
        p.v ~= 0x0400  // Switch horizontal nametable (flip bit 10 with XOR)
    } else { // Otherwise, just increment coarse X
        p.v += 1
    }
}

// At cycle 256 of each scanline, we increment Y to move to the next pixel row.
// Direct translation of pseudocode from NES documentation.
ppu_increment_y :: proc(p: ^PPU) {
    if (p.v & 0x7000) != 0x7000 { // If fine Y < 7, just increment fine Y
        p.v += 0x1000 
    } else {
        p.v &= ~u16(0x7000) // Fine Y = 0

        coarse_y := (p.v & 0x03E0) >> 5
        if coarse_y == 29 {
            coarse_y = 0
            p.v ~= 0x0800 // Switch vertical nametable (flip bit 11)
        } else if coarse_y == 31 {
            coarse_y = 0 
            // Not switching nametable
        } else {
            coarse_y += 1
        }
        
        // Put coarse Y back into v
        p.v = (p.v & ~u16(0x03E0)) | (coarse_y << 5)
    }
}

// At cycle 257 of each scanline, copy all bits related to horizontal position from t to v
ppu_transfer_x :: proc(p: ^PPU) {
    // v: ....A.. ...BCDEF <- t: ....A.. ...BCDEF
    // Copy bit 10 (horizontal nametable) and bits 0-4 (coarse X)
    p.v = (p.v & ~u16(0x041F)) | (p.t & 0x041F)
}

// During cycles 280-304 of pre-render scanline, copy all bits related to vertical position from t to v
ppu_transfer_y :: proc(p: ^PPU) {
    // v: GHIA.BC DEF..... <- t: GHIA.BC DEF.....
    // Copy bits 14-12 (fine Y), bit 11 (vertical nametable), and bits 9-5 (coarse Y)
    p.v = (p.v & ~u16(0x7BE0)) | (p.t & 0x7BE0)
}

// Fetch nametable byte (tile ID) using current v address
ppu_fetch_background_nametable_byte :: proc(p: ^PPU, b: ^PPU_Bus) -> u8 {
    address := 0x2000 | (p.v & 0x0FFF)
    return ppu_bus_read(b, address)
}

// Fetch attribute byte (palette number) using current v address
ppu_fetch_background_attribute_byte :: proc(p: ^PPU, b: ^PPU_Bus) -> u8 {
    // Each attribute byte controls 4 tiles (2x2 block)
    // Need to extract the correct 2 bits based on tile position within the block
    coarse_x := p.v & 0x001F
    coarse_y := (p.v >> 5) & 0x001F
    
    // Which quadrant of the 4-tile block? (0-3)
    shift := ((coarse_y & 0x02) << 1) | (coarse_x & 0x02)

    address := 0x23C0 | (p.v & 0x0C00) | ((p.v >> 4) & 0x38) | ((p.v >> 2) & 0x07)
    attribute_byte := ppu_bus_read(b, address)
    
    return (attribute_byte >> shift) & 0x03
}

// Fetch pattern byte (tile pixel data) for given plane
ppu_fetch_background_pattern_byte :: proc(p: ^PPU, b: ^PPU_Bus, tile_id: u8, plane: u8) -> u8 {
    pattern_table_base := u16(p.PPUCTRL.B) * 0x1000
    
    // Each tile is 16 bytes (8 bytes for low plane, 8 bytes for high plane)
    // Fine Y selects which row within the tile
    fine_y := (p.v >> 12) & 0x07
    
    address := pattern_table_base + (u16(tile_id) << 4) + (u16(plane) << 3) + fine_y
    
    return ppu_bus_read(b, address)
}

ppu_load_background_shifters :: proc(p: ^PPU) {
    // Load pattern data into low 8 bits of shifters
    p.bg_shifter_pattern_low = (p.bg_shifter_pattern_low & 0xFF00) | u16(p.bg_next_tile_pattern_low)
    p.bg_shifter_pattern_high = (p.bg_shifter_pattern_high & 0xFF00) | u16(p.bg_next_tile_pattern_high)
    
    // Expand palette bits: if bit is 1, fill with 0xFF; if 0, fill with 0x00
    palette_low := p.bg_next_tile_palette & 0x01 != 0 ? u16(0xFF) : 0x00
    palette_high := p.bg_next_tile_palette & 0x02 != 0 ?  u16(0xFF) : 0x00
    
    p.bg_shifter_palette_low = (p.bg_shifter_palette_low & 0xFF00) | palette_low
    p.bg_shifter_palette_high = (p.bg_shifter_palette_high & 0xFF00) | palette_high
}

ppu_load_background_shifters_optimized :: proc(p: ^PPU) {
    // Since all 4 background shifters are adjacent in memory, we can operate on them as a single 64-bit block.
    shifters := (^u64)(&p.bg_shifter_pattern_low)
    
    pal := p.bg_next_tile_palette
    
    // Pack bytes into 64-bit register at offsets 0, 16, 32, 48
    new_data := u64(p.bg_next_tile_pattern_low) | 
               (u64(p.bg_next_tile_pattern_high) << 16) |
               (u64((pal & 1) * 0xFF) << 32) | 
               (u64((pal >> 1) * 0xFF) << 48)

    // Mask preserves high bytes (0xFF00...), insert writes low bytes
    shifters^ = (shifters^ & 0xFF00FF00FF00FF00) | new_data
}

ppu_shift_background_registers :: proc(p: ^PPU) {
    // For high bitplane of background pattern, 1 is shifted into the low bit of the shifter, instead of 0.
    // Usually, these 1's are overwritten with tile data when shifters are loaded every 8 cycles. But, if
    // rendering is disabled and enabled at some very precise moments (disable before load, enable right after load), 
    // it is possible to skip loading shifters with fresh tile data, and these 1's could potentially be rendered
    // on the screen, and even cause sprite 0 hit.
    //
    // TODO: AccuracyCoin's "BG Serial In" test is flaky with current implementation. Probably something with 
    // rendering toggle latency, or with how 1's are shifted into BG, or with how BG shifters are loaded.
    p.bg_shifter_pattern_high = (p.bg_shifter_pattern_high << 1) | 1

    p.bg_shifter_pattern_low  <<= 1
    p.bg_shifter_palette_high <<= 1
    p.bg_shifter_palette_low  <<= 1
}

ppu_shift_background_registers_optimized :: proc(p: ^PPU) {
    shifters := (^u64)(&p.bg_shifter_pattern_low)
    
    val := shifters^
    
    // Shift everything left by 1
    val <<= 1
    
    // 1. Clear "carry" bits (16, 32, 48) where lower u16s bled into higher ones
    // 2. Clear bit 0 (standard shift behavior)
    val &= 0xFFFE_FFFE_FFFE_FFFE
    
    // Shift 1 into the pattern high bitplane
    val |= 0x0000_0000_0001_0000
    
    shifters^ = val
}

ppu_get_background_pixel :: proc(p: ^PPU) -> (color: u16, palette: u16) {
    // Select bit based on fine X scroll
    bit_select := 15 - p.x
    
    // Extract one bit from each shifter
    pixel_bit_0 := (p.bg_shifter_pattern_low >> bit_select) & 1
    pixel_bit_1 := (p.bg_shifter_pattern_high >> bit_select) & 1
    palette_bit_0 := (p.bg_shifter_palette_low >> bit_select) & 1
    palette_bit_1 := (p.bg_shifter_palette_high >> bit_select) & 1
    
    // Combine bits
    color = (pixel_bit_1 << 1) | pixel_bit_0
    palette = (palette_bit_1 << 1) | palette_bit_0
    
    return
}

ppu_get_background_pixel_optimized :: proc(p: ^PPU) -> (color: u16, palette: u16) {
    shifters := (^u64)(&p.bg_shifter_pattern_low)^
    
    // Parallel shift - move target bits to positions: 0, 16, 32, 48
    shift := (15 - u64(p.x)) & 0xF 
    shifters >>= shift

    // Only preserve the low bit of each u16
    shifters &= 0x0001_0001_0001_0001

    combined := shifters | (shifters >> 15)
    
    color   = u16(combined) & 0x03
    palette = u16(combined >> 32) & 0x03
    
    return
}
