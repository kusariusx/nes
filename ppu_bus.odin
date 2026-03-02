package main

PPU_OPEN_BUS_VALUE :: 0xFF
VRAM_BANK_SIZE :: 1024

PPU_Bus :: struct {
    vram: [2 * VRAM_BANK_SIZE]byte,
    palette_ram: [32]byte,

    cpu: ^CPU,
    cpu_bus: ^CPU_Bus,
    
    rom: ^ROM,
    mapper: Mapper,

    address_bus_value: u16,
}

ppu_bus_set_address :: proc(b: ^PPU_Bus, address: u16) {
    if b.address_bus_value == address { // Nothing changed
        return
    }

    b.address_bus_value = address
    mapper_notify(b.mapper, .PPU_Address_Bus_Changed)
}

ppu_bus_read :: proc(b: ^PPU_Bus, address: u16) -> u8 {
    address := address & 0x3FFF // PPU address bus is 14-bit
    ppu_bus_set_address(b, address)
    
    switch address {
    case 0x0000 ..= 0x3EFF: // This address space could be remapped by cardridge, try it
        value, mask := mapper_ppu_read(b.mapper, b.rom, address)
        if mask != 0 {
            return value & mask
        }

        // If cartridge did not handle this read, try to map to internal VRAM
        switch address {
        case 0x2000 ..= 0x2FFF:
            nametable := (address >> 10) & 0b11

            bank: u16
            switch b.rom.header.flags_6.nametable_arrangement {
            case 0:
                bank = nametable >> 1
            case 1:
                bank = nametable & 1
            }

            effective_address := bank * VRAM_BANK_SIZE + (address & 0x3FF)
            return b.vram[effective_address]
        case:
            return PPU_OPEN_BUS_VALUE
        }
    case 0x3F00 ..= 0x3FFF: // This address space is internal to the PPU - palette RAM
        return ppu_bus_read_palette_ram(b, address - 0x3F00)
    }

    return PPU_OPEN_BUS_VALUE
}

ppu_bus_write :: proc(b: ^PPU_Bus, address: u16, value: u8) {
    address := address & 0x3FFF
    ppu_bus_set_address(b, address)

    switch address {
    case 0x0000 ..= 0x3EFF:
        handled := mapper_ppu_write(b.mapper, b.rom, address, value)
        if handled {
            return
        } 

        switch address {
        case 0x2000 ..= 0x2FFF:
            nametable := (address >> 10) & 0b11

            bank: u16
            switch b.rom.header.flags_6.nametable_arrangement {
            case 0:
                bank = nametable >> 1
            case 1:
                bank = nametable & 1
            }

            effective_address := bank * VRAM_BANK_SIZE + (address & 0x3FF)
            b.vram[effective_address] = value
        }
    case 0x3F00 ..= 0x3FFF:
        effective_address := (address - 0x3F00) & 0x1F
        if effective_address & 0x03 == 0 {
            effective_address &= 0x0F
        }
        
        b.palette_ram[effective_address] = value
    }
}

// Retrieves n-th entry in palette RAM
ppu_bus_read_palette_ram :: proc(b: ^PPU_Bus, entry: u16) -> u8 {
    effective_address := entry & 0x1F // Mask to 32 bytes
    if effective_address & 0x03 == 0 {
        // 0-th entry of each palette, both sprite and background (addresses 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C),
        // must point to the same memory. Masking effective address with 0x0F to mirror address 0x10 to address 0x00,
        // address 0x14 to 0x04, etc.
        effective_address &= 0x0F
    }

    return b.palette_ram[effective_address]
}
