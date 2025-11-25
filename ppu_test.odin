package main

import "core:testing"

@(test)
test_increment_coarse_x :: proc(t: ^testing.T) {
    ppu: PPU

    // Basic case
    ppu = PPU{v = 5} // Coarse X = 5
    ppu_increment_coarse_x(&ppu)
    testing.expect_value(t, ppu.v, 6)

    // Wrapping at 31
    ppu = PPU{v = 31} // Coarse X = 31
    ppu_increment_coarse_x(&ppu)
    testing.expect_value(t, ppu.v, 0x0400) // Coarse X = 0, horizontal nametable bit flipped

    // Preserve other bits
    ppu = PPU{v = 0x7FFF} // All bits set (coarse X = 31, everything else = 1)
    ppu_increment_coarse_x(&ppu)
    testing.expect_value(t, ppu.v, 0x7BE0) // Expected: 0x7BE0 (0111 1011 1110 0000)
}

@(test)
test_increment_y :: proc(t: ^testing.T) {
    ppu: PPU

    // Increment fine Y (fine Y < 7)
    ppu = PPU{v = 0x3000} // Fine Y = 3
    ppu_increment_y(&ppu)
    testing.expect_value(t, ppu.v, 0x4000) // Fine Y = 4

    // Fine Y overflow (fine Y = 7, coarse Y increments)
    ppu = PPU{v = 0x7000} // Fine Y = 7, coarse Y = 0
    ppu_increment_y(&ppu)
    testing.expect_value(t, ppu.v, 0x0020) // Fine Y = 0, coarse Y = 1

    // Wrap at coarse Y = 29 (switch vertical nametable)
    ppu = PPU{v = 0x73A0} // Fine Y = 7, coarse Y = 29
    ppu_increment_y(&ppu)
    testing.expect_value(t, ppu.v, 0x0800) // Fine Y = 0, coarse Y = 0, vertical nametable flipped

    // Wrap at coarse Y = 31 (no nametable switch)
    ppu = PPU{v = 0x73E0} // Fine Y = 7, coarse Y = 31
    ppu_increment_y(&ppu)
    testing.expect_value(t, ppu.v, 0x0000) // Fine Y = 0, coarse Y = 0, nametable unchanged

    // Normal coarse Y increment
    ppu = PPU{v = 0x71E0} // Fine Y = 7, coarse Y = 15
    ppu_increment_y(&ppu)
    testing.expect_value(t, ppu.v, 0x0200) // Fine Y = 0, coarse Y = 16

    // Preserve horizontal bits
    ppu = PPU{v = 0x7FFF} // All bits set
    ppu_increment_y(&ppu)
    // Coarse Y = 31 wraps to 0, fine Y = 7 wraps to 0, horizontal/vertical bits preserved
    // Expected: 0x0C1F (0000 1100 0001 1111)
    testing.expect_value(t, ppu.v, 0x0C1F)
}

@(test)
test_transfer_x :: proc(t: ^testing.T) {
    ppu: PPU

    // Copy horizontal bits from t to v
    ppu = PPU{v = 0x7FFF, t = 0x0000}
    ppu_transfer_x(&ppu)
    // Should copy bit 10 and bits 4-0 from t (all 0) to v
    // v starts as 0x7FFF = 0111 1111 1111 1111
    // After: 0x7BE0 = 0111 1011 1110 0000
    testing.expect_value(t, ppu.v, 0x7BE0)

    // Copy horizontal bits, preserve vertical
    ppu = PPU{v = 0x0000, t = 0x041F}
    ppu_transfer_x(&ppu)
    // Should copy bit 10 (1) and bits 4-0 (all 1) from t to v
    // Expected: 0x041F
    testing.expect_value(t, ppu.v, 0x041F)

    // Mixed case
    ppu = PPU{v = 0x7BE0, t = 0x001F}
    ppu_transfer_x(&ppu)
    // Copy coarse X = 31, horizontal nametable = 0 from t
    // Preserve all vertical bits from v
    // Expected: 0x7BFF
    testing.expect_value(t, ppu.v, 0x7BFF)
}

@(test)
test_transfer_y :: proc(t: ^testing.T) {
    ppu: PPU

    // Copy vertical bits from t to v
    ppu = PPU{v = 0x7FFF, t = 0x0000}
    ppu_transfer_y(&ppu)
    // Should copy bits 14-12 (fine Y), bit 11 (vertical nametable), bits 9-5 (coarse Y) from t (all 0) to v
    // v starts as 0x7FFF = 0111 1111 1111 1111
    // After: 0x041F = 0000 0100 0001 1111
    testing.expect_value(t, ppu.v, 0x041F)

    // Copy vertical bits, preserve horizontal
    ppu = PPU{v = 0x0000, t = 0x7BE0}
    ppu_transfer_y(&ppu)
    // Should copy fine Y, vertical nametable, coarse Y from t to v
    // Expected: 0x7BE0
    testing.expect_value(t, ppu.v, 0x7BE0)

    // Mixed case
    ppu = PPU{v = 0x041F, t = 0x73E0}
    ppu_transfer_y(&ppu)
    // Copy fine Y = 7, vertical nametable = 0, coarse Y = 31 from t
    // Preserve horizontal bits from v
    // Expected: 0x77FF
    testing.expect_value(t, ppu.v, 0x77FF)
}

@(test)
test_fetch_nametable_byte :: proc(t: ^testing.T) {
    ppu: PPU
    bus: NES_PPU_Bus

    // Initialize bus VRAM with test data
    bus.vram[0x000] = 0x42 // Address 0x2000
    bus.vram[0x3FF] = 0x99 // Address 0x23FF

    // Fetch from first nametable
    ppu.v = 0x2000 // Points to 0x2000
    result := ppu_fetch_nametable_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0x42))

    // Fetch from end of first nametable
    ppu.v = 0x23FF // Points to 0x23FF
    result = ppu_fetch_nametable_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0x99))

    // Fetch with fine Y bits set (should be masked out)
    ppu.v = 0x7000 // Fine Y = 7, address still 0x2000
    result = ppu_fetch_nametable_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0x42))
}

@(test)
test_fetch_attribute_byte :: proc(t: ^testing.T) {
    ppu: PPU
    bus: NES_PPU_Bus

    // Set up attribute byte: 0b11_10_01_00
    // Bits 1-0: 00 (top-left)
    // Bits 3-2: 01 (top-right)
    // Bits 5-4: 10 (bottom-left)
    // Bits 7-6: 11 (bottom-right)
    bus.vram[0x3C0] = 0b11_10_01_00 // First attribute byte at 0x23C0

    // Top-left quadrant (coarse_x = 0, coarse_y = 0)
    ppu.v = 0x2000
    result := ppu_fetch_attribute_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0b00))

    // Top-right quadrant (coarse_x = 2, coarse_y = 0)
    ppu.v = 0x2002
    result = ppu_fetch_attribute_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0b01))

    // Bottom-left quadrant (coarse_x = 0, coarse_y = 2)
    ppu.v = 0x2040
    result = ppu_fetch_attribute_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0b10))

    // Bottom-right quadrant (coarse_x = 2, coarse_y = 2)
    ppu.v = 0x2042
    result = ppu_fetch_attribute_byte(&ppu, &bus)
    testing.expect_value(t, result, u8(0b11))
}

@(test)
test_fetch_pattern_byte :: proc(t: ^testing.T) {
    ppu: PPU
    bus: NES_PPU_Bus
    rom: ROM

    // Set up pattern table data
    // Tile 0x05 at pattern table 0 (0x0000)
    // Each tile is 16 bytes: 8 for low plane, 8 for high plane
    rom.chr_rom = make([]u8, 0x2000)
    rom.header.chr_rom_banks = 1 // To make NROM to use 
    defer delete(rom.chr_rom)
    
    tile_offset := 0x05 * 16
    rom.chr_rom[tile_offset + 0] = 0xAA // Low plane, row 0
    rom.chr_rom[tile_offset + 3] = 0xBB // Low plane, row 3
    rom.chr_rom[tile_offset + 8] = 0xCC // High plane, row 0
    rom.chr_rom[tile_offset + 11] = 0xDD // High plane, row 3

    mapper := NROM{}
    bus.rom = &rom
    bus.mapper = &mapper

    // Fetch low plane, row 0
    ppu.PPUCTRL.B = 0 // Pattern table 0
    ppu.v = 0x0000 // Fine Y = 0
    result := ppu_fetch_pattern_byte(&ppu, &bus, 0x05, 0)
    testing.expect_value(t, result, u8(0xAA))

    // Fetch low plane, row 3
    ppu.v = 0x3000 // Fine Y = 3
    result = ppu_fetch_pattern_byte(&ppu, &bus, 0x05, 0)
    testing.expect_value(t, result, u8(0xBB))

    // Fetch high plane, row 0
    ppu.v = 0x0000 // Fine Y = 0
    result = ppu_fetch_pattern_byte(&ppu, &bus, 0x05, 1)
    testing.expect_value(t, result, u8(0xCC))

    // Fetch high plane, row 3
    ppu.v = 0x3000 // Fine Y = 3
    result = ppu_fetch_pattern_byte(&ppu, &bus, 0x05, 1)
    testing.expect_value(t, result, u8(0xDD))

    // Test pattern table 1 (0x1000)
    rom.chr_rom[0x1000 + tile_offset + 0] = 0xEE
    ppu.PPUCTRL.B = 1 // Pattern table 1
    ppu.v = 0x0000
    result = ppu_fetch_pattern_byte(&ppu, &bus, 0x05, 0)
    testing.expect_value(t, result, u8(0xEE))
}
