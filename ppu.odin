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

}
