package main

import "core:fmt"

NROM :: struct{
    prg_ram: [0x2000]byte,
    chr_ram: [0x2000]byte,
} 

nrom_cpu_read :: proc(m: ^NROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x6000 ..= 0x7FFF: // PRG-RAM
        if r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            return m.prg_ram[effective_address], 0xFF
        }
    case 0x8000 ..= 0xFFFF: // PRG-ROM
        prg_rom_size := int(r.header.prg_rom_banks) * PRG_ROM_BANK_SIZE
        effective_address := int(address - 0x8000) % prg_rom_size // Modulo actual size to implement mirroring
        return r.prg_rom[effective_address], 0xFF
    }

    return 0, 0
}

nrom_cpu_write :: proc(m: ^NROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF: // PRG-RAM
        if r.header.prg_ram_size > 0 {
            if address >= 0x6004 {
                fmt.printf("%c", value)
            }
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            m.prg_ram[effective_address] = value
            
            return true
        }
    }
    
    return false
}

nrom_ppu_read :: proc(m: ^NROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 { // Cartridge uses CHR-RAM
            return m.chr_ram[address], 0xFF
        } 

        return r.chr_rom[address], 0xFF
    }

    return 0, 0
}

nrom_ppu_write :: proc(m: ^NROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 { // Cartridge uses CHR-RAM
            m.chr_ram[address] = value 
            return true
        }

        // CHR-ROM is not writeable
        return false
    }    
    
    return false
}
