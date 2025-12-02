package main

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

    ppudata_read_buffer: u8,

    oam: [256]u8, // Object Attribute Memory
    secondary_oam: [32]u8,

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
    scanline_cycle: int, // Current cycle/dot inside a scanline
    scanline: int,       // Current scanline
    
    sprite_eval_n: u8, // What sprite we currently evaluate
    sprite_eval_m: u8, // Current byte within sprite
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

    framebuffer: [256 * 240]u8,
}

// PPU runs 3x faster than CPU, so for each CPU tick, we tick PPU 3 times
ppu_tick :: proc(p: ^PPU, b: ^NES_PPU_Bus) {
    is_background_enabled := p.PPUMASK.b == 1
    is_sprite_enabled := p.PPUMASK.s == 1
    is_rendering_enabled := is_background_enabled || is_sprite_enabled
   
    switch p.scanline {
    case 0 ..= 239, 261: // Visible scanlines and pre-render scanline
        // Joining visible and pre-render scanlines because a lot of identical things happen on both of them

        is_pre_render_scanline := p.scanline == 261
        is_visible_scanline := !is_pre_render_scanline

        if is_pre_render_scanline {
            // The three PPUSTATUS flags are automatically cleared on dot 1 of the pre-render scanline
            if p.scanline_cycle == 1 {
                p.PPUSTATUS.V = 0
                p.PPUSTATUS.S = 0
                p.PPUSTATUS.O = 0
            }
        }

        if is_rendering_enabled {
            is_rendering_cycle := p.scanline_cycle >= 1 && p.scanline_cycle <= 256
            is_prefetch_cycle := p.scanline_cycle >= 321 && p.scanline_cycle <= 336

            // Sprite evaluation
            // Only happens on visible scanlines when rendering is enabled
            if is_visible_scanline {
                increment_n :: proc(p: ^PPU) {
                    p.sprite_eval_n = (p.sprite_eval_n + 1) & 0x3F // Wrap to 0-63
                    if p.sprite_eval_n == 0 { // Overflow to 0 - all 64 sprites have been evaluated
                        p.sprite_eval_done = true
                    }  
                }

                increment_m :: proc(p: ^PPU) {
                    if p.sprite_eval_m == 3 { // Processed last byte of the sprite
                        // Move on to the next sprite
                        p.sprite_eval_m = 0
                        increment_n(p)
                    } else {
                        // Move on to the next byte within the sprite
                        p.sprite_eval_m += 1 
                    }
                }

                is_odd_cycle := p.scanline_cycle % 2 == 1

                if p.scanline_cycle == 1 { // Sprite evaluation has just started, reset state
                    p.sprite_eval_n = 0
                    p.sprite_eval_m = 0
                    p.sprite_eval_found = 0
                    p.sprite_eval_secondary_oam_pos = 0
                    p.sprite_eval_pending_reads = 0
                    p.sprite_eval_done = false
                    p.sprite_eval_sprite_0_present = false
                }

                switch p.scanline_cycle {
                case 1 ..= 64: // Secondary OAM clearing
                    if is_odd_cycle {
                        // Dummy read from OAM
                        // Note: since OAM is not accessed through the bus (i.e. read has no side effects), 
                        // we can probably just do nothing here?
                    } else {
                        // Write 0xFF to secondary OAM
                        // Writes happen at cycles 2, 4, ..., 64 into positions 0, 1, ..., 31
                        secondary_oam_pos := (p.scanline_cycle >> 1) - 1
                        p.secondary_oam[secondary_oam_pos] = 0xFF
                    }
                case 65 ..= 256: // Sprite evaluation
                    sprite_height := int(p.PPUCTRL.H == 0 ? 8 : 16)

                    if p.sprite_eval_done {
                        if is_odd_cycle {
                            // Dummy read n-th sprite from OAM
                            // Reading OAM has no side effects, so can just do nothing here
                        } else {
                            increment_n(p)
                        }

                        // Just burn cycles until we reach cycle 257

                        break
                    }

                    // Already found 8 sprites to draw, but still have sprites to evaluate - transition
                    // to sprite overflow phase.
                    if p.sprite_eval_found == 8 {
                        if is_odd_cycle {
                            oam_pos := (p.sprite_eval_n << 2) + p.sprite_eval_m
                            p.sprite_eval_oam_data = p.oam[oam_pos]
                        } else {
                            if p.sprite_eval_pending_reads > 0 {
                                // Dummy read the OAM

                                increment_m(p)
                                p.sprite_eval_pending_reads -= 1
                            } else {
                                // Evaluate data as a Y position. Due to hardware bug leading to m being incremented together with n,
                                // data will not always be the 0-th byte of a sprite, but we still evaluate it as such.
                                sprite_y := int(p.sprite_eval_oam_data)
                                sprite_in_range := p.scanline >= sprite_y && p.scanline < sprite_y + sprite_height

                                if sprite_in_range {
                                    // Set overflow flag because we have found more than 8 in-range sprites
                                    p.PPUSTATUS.O = 1

                                    increment_m(p)

                                    // Request to read 3 next OAM bytes without evaluating them, effectively skipping to the next sprite
                                    p.sprite_eval_pending_reads = 3
                                } else {
                                    // Hardware bug - increment both n and m. This leads to random data (tile index, attributes, X position)
                                    // being evaluated as Y position, leading to random changes in overflow flag.
                                    p.sprite_eval_m = (p.sprite_eval_m + 1) & 0x03 // Increment and wrap to 0-3
                                    increment_n(p)
                                }
                            }
                        }

                        break
                    }

                    // On odd cycles, data is read from OAM
                    // On even cycles, state is updated and writes to secondary OAM happen
                    if is_odd_cycle {
                        oam_pos := (p.sprite_eval_n << 2) + p.sprite_eval_m // 4 * n + m
                        p.sprite_eval_oam_data = p.oam[oam_pos]
                    } else {
                        switch p.sprite_eval_m {
                        case 0: // Started processing a new sprite (0-th byte, Y position)
                            // We write Y to secondary OAM regardless of whether the sprite is in range or not.
                            // If not in range, it will be just overwritten by the next sprite.
                            p.secondary_oam[p.sprite_eval_secondary_oam_pos] = p.sprite_eval_oam_data

                            sprite_y := int(p.sprite_eval_oam_data)
                            sprite_in_range := p.scanline >= sprite_y && p.scanline < sprite_y + sprite_height
                            
                            if sprite_in_range {
                                p.sprite_eval_found += 1
                                p.sprite_eval_secondary_oam_pos += 1 // Advance in the secondary OAM
                                p.sprite_eval_m += 1 // We would like to process the next byte of this sprite

                                if p.sprite_eval_n == 0 {
                                    p.sprite_eval_sprite_0_present = true
                                }
                            } else {
                                increment_n(p) // Move on to the next sprite, leave m at 0, and secondary OAM position intact
                            }
                        case 1, 2, 3: // Processing tile index, attributes, or X position
                            // Copy byte to secondary OAM
                            p.secondary_oam[p.sprite_eval_secondary_oam_pos] = p.sprite_eval_oam_data
                            p.sprite_eval_secondary_oam_pos += 1

                            increment_m(p)
                        }
                    }
                }
            }

            // Sprite fetching, happens on both visible scanlines and pre-render scanline
            switch p.scanline_cycle {
            case 257 ..= 320:
                sprite_idx := (p.scanline_cycle - 257) / 8
                secondary_oam_pos := sprite_idx * 4

                // When we have less than 8 sprites on a scanline, we still perform all this fetches but discard
                // those dummy sprites during rendering.
                switch p.scanline_cycle % 8 {
                case 1: // Read Y
                    p.sprite_y_position = p.secondary_oam[secondary_oam_pos]
                    ppu_fetch_nametable_byte(p, b) // Dummy nametable fetch (at cycles 1-2)
                case 2: // Read tile number
                    p.sprite_tile_number = p.secondary_oam[secondary_oam_pos + 1]
                case 3: // Read attributes
                    p.sprite_attributes[sprite_idx] = p.secondary_oam[secondary_oam_pos + 2]
                    ppu_fetch_nametable_byte(p, b) // Dummy nametable fetch (at cycles 3-4)
                case 4: // Read X
                    p.sprite_x_position[sprite_idx] = p.secondary_oam[secondary_oam_pos + 3]
                case 5: // Fetch pattern low (takes 2 cycles)
                    p.sprite_shifter_pattern_low[sprite_idx] = ppu_fetch_sprite_pattern_byte(p, b, sprite_idx, LOW)
                case 7: // Fetch pattern high (takes 2 cycles)
                    p.sprite_shifter_pattern_high[sprite_idx] = ppu_fetch_sprite_pattern_byte(p, b, sprite_idx, HIGH)
                }
            }

            // Background and sprite rendering
            if is_visible_scanline && is_rendering_cycle {
                pixel_x := p.scanline_cycle - 1

                color, palette: u16
                background_color, background_palette: u16
                sprite_color, sprite_palette, sprite_priority: u8

                // Handle disable flag and "show leftmost 8 pixels" flag, extract pixels
                if !is_background_enabled || (pixel_x < 8 && p.PPUMASK.m == 0) {
                    background_color, background_palette = 0, 0
                } else {
                    background_color, background_palette = ppu_get_background_pixel(p)
                }

                if !is_sprite_enabled || (pixel_x < 8 && p.PPUMASK.M == 0) {
                    sprite_color, sprite_palette, sprite_priority = 0, 0, 0
                } else {
                    sprite_color, sprite_palette, sprite_priority = ppu_get_sprite_pixel(p)
                }

                // Sprite 0 hit detection
                if p.sprite_0_on_current_scanline {
                    // If sprite 0 is present on the current scanline, it is guaranteed to be first in our shifters/latches
                    sprite_0_bit_0 := p.sprite_shifter_pattern_low[0] >> 7
                    sprite_0_bit_1 := p.sprite_shifter_pattern_high[0] >> 7
                    sprite_0_color := (sprite_0_bit_1 << 1) | sprite_0_bit_0

                    sprite_0_hit := // Sprite 0 is hit when...
                        p.sprite_x_position[0] == 0 && // Sprite 0 is active
                        p.PPUSTATUS.S == 0 && // It was not hit earlier on the scanline
                        is_sprite_enabled && // Sprite rendering is enabled - we need to check this because we read sprite data directly from shifters
                        background_color != 0 && sprite_0_color != 0 && // Both background and sprite 0 are opaque
                        // Sprite 0 hit is not detected when rendering is disabled for leftmost 8 pixels.
                        // We are either in the safe zone where this restriction does not apply (pixel_x >= 8),
                        // Or both background and sprites are enabled in this zone.
                        (pixel_x >= 8 || (p.PPUMASK.m == 1 && p.PPUMASK.M == 1)) &&
                        pixel_x != 255 // Due to hardware specifics, sprite 0 hit cannot occur at X = 255

                    if sprite_0_hit {
                        p.PPUSTATUS.S = 1
                    }
                }

                // After pixel extraction and sprite 0 hit detection, shift active sprites
                for i in 0 ..< 8 {
                    if p.sprite_x_position[i] == 0 {
                        p.sprite_shifter_pattern_low[i] <<= 1
                        p.sprite_shifter_pattern_high[i] <<= 1
                    }
                }

                // Decrement sprite X counters
                for i in 0 ..< 8 {
                    if p.sprite_x_position[i] > 0 {
                        p.sprite_x_position[i] -= 1
                    }
                }

                // Determine what pixel to draw
                if (sprite_color != 0 && sprite_priority == 0) || background_color == 0 { // Sprite pixel wins
                    color, palette = u16(sprite_color), u16(sprite_palette)
                } else { // Background pixel wins
                    color, palette = background_color, background_palette
                }

                // Calculate palette RAM address
                // If color is 0, it's transparent - use backdrop color
                palette_address: u16
                if color == 0 {
                    palette_address = 0x3F00 // Backdrop color
                } else {
                    palette_address = 0x3F00 + (palette << 2) + color
                }
                
                color_index := ppu_bus_read(b, palette_address)
                
                // Write to framebuffer
                pixel_index := p.scanline * 256 + pixel_x
                p.framebuffer[pixel_index] = color_index
            }

            // Background fetching, happens on both visible scanlines and pre-render scanline
            if is_rendering_cycle || is_prefetch_cycle {
                switch p.scanline_cycle % 8 {
                case 1:
                    ppu_load_shifters(p)
                    p.bg_next_tile_id = ppu_fetch_nametable_byte(p, b)
                case 3:
                    p.bg_next_tile_palette = ppu_fetch_attribute_byte(p, b)
                case 5:
                    p.bg_next_tile_pattern_low = ppu_fetch_pattern_byte(p, b, p.bg_next_tile_id, LOW)
                case 7:
                    p.bg_next_tile_pattern_high = ppu_fetch_pattern_byte(p, b, p.bg_next_tile_id, HIGH)
                case 0:
                    ppu_increment_coarse_x(p)
                }

                ppu_shift_registers(p)
            }
            
            if p.scanline_cycle == 256 {
                ppu_increment_y(p)
            }
            
            if p.scanline_cycle == 257 {
                ppu_transfer_x(p)

                // After sprite evaluation and rendering, transfer flag to be able to detect sprite 0 hit on the next scanline
                p.sprite_0_on_current_scanline = p.sprite_eval_sprite_0_present
            }
            
            if is_pre_render_scanline && p.scanline_cycle >= 280 && p.scanline_cycle <= 304 {
                ppu_transfer_y(p)
            }
        }
    case 240: // Post-render scanline
        // PPU is idle during this scanline
    case 241 ..= 260: // VBlank scanlines
        if p.scanline == 241 && p.scanline_cycle == 1 {
            // Set VBlank flag on the second cycle of 241st scanline
            p.PPUSTATUS.V = 1

            // Request NMI if enabled
            if p.PPUCTRL.V == 1 {
                b.cpu_bus.nmi_pending = true
            }
        }
    }

    p.scanline_cycle += 1

    // 261-st scanline varies in length, could be 341 or 340 cycles long
    // All other scanlines are 341 cycles long
    scanline_length := 341
    if p.scanline == 261 && p.is_odd_frame && is_rendering_enabled {
        scanline_length = 340
    }

    if p.scanline_cycle == scanline_length { // Scanline is completed
        p.scanline_cycle = 0
        p.scanline += 1

        if p.scanline == 262 { // Frame is completed
            p.scanline = 0
            p.is_odd_frame = !p.is_odd_frame
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

reverse_bits :: proc(n: u8) -> u8 {
    n := n
    result := u8(0)

    for _ in 0 ..< 8 {
        result = (result << 1) | (n & 1)
        n >>= 1
    }

    return result
}

ppu_fetch_sprite_pattern_byte :: proc(p: ^PPU, b: ^NES_PPU_Bus, sprite_idx: int, plane: u16) -> u8 {
    attributes := p.sprite_attributes[sprite_idx]

    // Mask with (sprite_height - 1) to keep the value within 0-7/0-15 range.
    // This will be important for dummy sprite fetches where the Y coordinate is 0xFF.
    // In such cases, row might be negative, which will lead to wrap-around when casting to u16 during address calculation.
    sprite_height := int(p.PPUCTRL.H == 0 ? 8 : 16)
    row := (p.scanline - int(p.sprite_y_position)) & (sprite_height - 1)
    
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
        pattern = reverse_bits(pattern)
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
ppu_fetch_nametable_byte :: proc(p: ^PPU, b: ^NES_PPU_Bus) -> u8 {
    address := 0x2000 | (p.v & 0x0FFF)
    return ppu_bus_read(b, address)
}

// Fetch attribute byte (palette number) using current v address
ppu_fetch_attribute_byte :: proc(p: ^PPU, b: ^NES_PPU_Bus) -> u8 {
    address := 0x23C0 | (p.v & 0x0C00) | ((p.v >> 4) & 0x38) | ((p.v >> 2) & 0x07)
    attribute_byte := ppu_bus_read(b, address)
    
    // Each attribute byte controls 4 tiles (2x2 block)
    // Need to extract the correct 2 bits based on tile position within the block
    coarse_x := p.v & 0x001F
    coarse_y := (p.v >> 5) & 0x001F
    
    // Which quadrant of the 4-tile block? (0-3)
    shift := ((coarse_y & 0x02) << 1) | (coarse_x & 0x02)
    
    return (attribute_byte >> shift) & 0x03
}

// Fetch pattern byte (tile pixel data) for given plane
ppu_fetch_pattern_byte :: proc(p: ^PPU, b: ^NES_PPU_Bus, tile_id: u8, plane: u8) -> u8 {
    pattern_table_base := u16(p.PPUCTRL.B) * 0x1000
    
    // Each tile is 16 bytes (8 bytes for low plane, 8 bytes for high plane)
    // Fine Y selects which row within the tile
    fine_y := (p.v >> 12) & 0x07
    
    address := pattern_table_base + (u16(tile_id) << 4) + (u16(plane) << 3) + fine_y
    
    return ppu_bus_read(b, address)
}

ppu_load_shifters :: proc(p: ^PPU) {
    // Load pattern data into low 8 bits of shifters
    p.bg_shifter_pattern_low = (p.bg_shifter_pattern_low & 0xFF00) | u16(p.bg_next_tile_pattern_low)
    p.bg_shifter_pattern_high = (p.bg_shifter_pattern_high & 0xFF00) | u16(p.bg_next_tile_pattern_high)
    
    // Expand palette bits: if bit is 1, fill with 0xFF; if 0, fill with 0x00
    palette_low := p.bg_next_tile_palette & 0x01 != 0 ? u16(0xFF) : 0x00
    palette_high := p.bg_next_tile_palette & 0x02 != 0 ?  u16(0xFF) : 0x00
    
    p.bg_shifter_palette_low = (p.bg_shifter_palette_low & 0xFF00) | palette_low
    p.bg_shifter_palette_high = (p.bg_shifter_palette_high & 0xFF00) | palette_high
}

ppu_shift_registers :: proc(p: ^PPU) {
    p.bg_shifter_pattern_low  <<= 1
    p.bg_shifter_pattern_high <<= 1
    p.bg_shifter_palette_low  <<= 1
    p.bg_shifter_palette_high <<= 1
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
