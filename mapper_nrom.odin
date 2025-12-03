package main

import "core:fmt"
NROM :: struct{
    prg_ram: [0x2000]byte,
    chr_ram: [0x2000]byte,
} 

nrom_cpu_read :: proc(m: ^NROM, r: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF: // PRG-RAM
        if r.header.prg_ram_size > 0 {
            effective_address := (address - 0x6000) % r.header.prg_ram_size
            return m.prg_ram[effective_address], true
        }
    case 0x8000 ..= 0xFFFF: // PRG-ROM
        prg_rom_size := u16(r.header.prg_rom_banks) * PRG_ROM_BANK_SIZE
        effective_address := (address - 0x8000) % prg_rom_size // Modulo actual size to implement mirroring
        return r.prg_rom[effective_address], true
    }

    return 0, false
}

nrom_cpu_write :: proc(m: ^NROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF: // PRG-RAM
        if r.header.prg_ram_size > 0 {
            // if address > 0x6004 {
            //     fmt.printf("%c", value)
            // }
            effective_address := (address - 0x6000) % r.header.prg_ram_size
            m.prg_ram[effective_address] = value
            
            return true
        }
    }
    
    return false
}

nrom_ppu_read :: proc(m: ^NROM, r: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 { // Cartridge uses CHR-RAM
            return m.chr_ram[address], true
        } 

        return r.chr_rom[address], true
    }

    return 0, false
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
