package main

PPU :: struct {
    PPUCTRL: bit_field u8 {
        NN: u8 | 2, // Base nametable address (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
        I:  u8 | 1, // VRAM address increment per CPU read/write of PPUDATA (0: add 1, going across; 1: add 32, going down)
        S:  u8 | 1, // Sprite pattern table address for 8x8 sprites (0: $0000; 1: $1000; ignored in 8x16 mode)
        B:  u8 | 1, // Background pattern table address (0: $0000; 1: $1000)
        H:  u8 | 1, // Sprite size (0: 8x8 pixels; 1: 8x16 pixels – see PPU OAM#Byte 1)
        P:  u8 | 1, // PPU master/slave select (0: read backdrop from EXT pins; 1: output color on EXT pins)
        V:  u8 | 1, // Vblank NMI enable (0: off, 1: on)
    },
    PPUMASK: bit_field u8 {
        g: u8 | 1, // Greyscale (0: normal color, 1: greyscale)
        m: u8 | 1, // 1: Show background in leftmost 8 pixels of screen, 0: Hide
        M: u8 | 1, // 1: Show sprites in leftmost 8 pixels of screen, 0: Hide
        b: u8 | 1, // 1: Enable background rendering
        s: u8 | 1, // 1: Enable sprite rendering
        R: u8 | 1, // Emphasize red (green on PAL/Dendy)
        G: u8 | 1, // Emphasize green (red on PAL/Dendy)
        B: u8 | 1, // Emphasize blue
    },
    PPUSTATUS: bit_field u8 {
        _: u8 | 5, // PPU open bus
        O: u8 | 1, // Sprite overflow flag
        S: u8 | 1, // Sprite 0 hit flag
        V: u8 | 1, // Vblank flag, cleared on read
    },
    OAMADDR:   u8, 
    OAMDATA:   u8,
    PPUSCROLL: u8, // X and Y scroll (first write - X, second write - Y) 
    PPUADDR:   u8, // VRAM address (14-bit value, bits 8-13 on first write, bits 0-7 on second write)
    PPUDATA:   u8,

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
                b.cpu.nmi_pending = true
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
