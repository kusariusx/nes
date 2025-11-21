package main

PPU_OPEN_BUS_VALUE :: 0xFF

NES_PPU_Bus :: struct {
    vram: [2 * 1024]byte,

    cpu: ^CPU, // For requesting interrupts
    rom: ^ROM,
    mapper: Mapper,
}

ppu_bus_read :: proc(b: ^NES_PPU_Bus, address: u16) -> u8 {
    address := address & 0x3FFF // PPU address bus is 14-bit
    switch address {
    case 0x0000 ..= 0x3EFF: // This address space could be remapped by cardridge, try it
        value, handled := mapper_ppu_read(b.mapper, b.rom, address)
        if handled {
            return value
        } 

        // If cartridge did not handle this read, try to map to internal VRAM
        switch address {
        case 0x2000 ..= 0x2FFF:
            effective_address := (address - 0x2000) & 0x7FF // Mask to 2 KB space
            return b.vram[effective_address]
        case:
            return PPU_OPEN_BUS_VALUE
        }
    case 0x3F00 ..= 0x3FFF: // This address space is internal to the PPU
    }

    return PPU_OPEN_BUS_VALUE
}

ppu_bus_write :: proc(b: ^NES_PPU_Bus, address: u16, value: u8) {
    address := address & 0x3FFF
    switch address {
    case 0x0000 ..= 0x3EFF:
        handled := mapper_ppu_write(b.mapper, b.rom, address, value)
        if handled {
            return
        } 

        switch address {
        case 0x2000 ..= 0x2FFF:
            effective_address := (address - 0x2000) & 0x7FF
            b.vram[effective_address] = value
        }
    case 0x3F00 ..= 0x3FFF:
    }
}
