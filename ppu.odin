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

    OAM: [256]u8, // Object Attribute Memory

    // Internal PPU registers
    v: u16, // Current VRAM address (15 bits)
    t: u16, // Temporary VRAM address (15 bits)
    x: u8,  // Fine X scroll (3 bits)
    w: u8,  // First or second write toggle (1 bit)

    // Shift registers used for drawing.
    // Every dot/cycle, the low 8 bits of these are used to construct data for 1 pixel: 
    // 2-bit color and 2-bit palette number. After that, they are shifted right.
    bg_shifter_pattern_low: u16,  // Holds low bit of 2-bit color code for 16 pixels (2 tiles)
    bg_shifter_pattern_high: u16, // Holds high bit of 2-bit color code
    bg_shifter_palette_low: u16,  // Holds low bit of 2-bit palette number for 16 pixels
    bg_shifter_palette_high: u16, // Holds high bit of 2-bit palette number

    // Internal latches used to pre-fetch data for the next tile.
    // Every 8 cycles, these latches are used to fill the high 8 bits of shift registers with data for the next tile.
    bg_next_tile_id: u8,           // Fetched from nametable
    bg_next_tile_palette: u8,      // Only 2 bits used - all pixels in a tile share the same palette
    bg_next_tile_pattern_low: u8,  // Low bits of 2-bit color codes
    bg_next_tile_pattern_high: u8, // High bits of 2-bit color codes

    is_odd_frame: bool,
    scanline_cycle: int, // Current cycle/dot inside a scanline
    scanline: int,       // Current scanline
}

// PPU runs 3x faster than CPU, so for each CPU tick, we tick PPU 3 times
ppu_tick :: proc(p: ^PPU, b: ^NES_PPU_Bus) {
    switch p.scanline {
    case 0 ..= 239: // Visible scanlines
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
    case 261: // Pre-render scanline
        // The three PPUSTATUS flags are automatically cleared on dot 1 of the prerender scanline
        if p.scanline_cycle == 1 {
            p.PPUSTATUS.V = 0
            p.PPUSTATUS.S = 0
            p.PPUSTATUS.O = 0
        }
    }

    p.scanline_cycle += 1

    rendering_enabled := p.PPUMASK.b == 1 || p.PPUMASK.s == 1

    // 261st scanline varies in length, could be 341 or 340 cycles long
    // All other scanlines are 341 cycles long
    scanline_length := 341
    if p.scanline == 261 && p.is_odd_frame && rendering_enabled {
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
