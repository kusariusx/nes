package main

UxROM :: struct {
    prg_bank: u8,
    
    prg_ram: [0x2000]byte, 
    chr_ram: [0x2000]byte, 
}

uxrom_cpu_read :: proc(m: ^UxROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x6000 ..= 0x7FFF:
        if r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            return m.prg_ram[effective_address], 0xFF
        }

    case 0x8000 ..= 0xBFFF: // 16 KB switchable PRG-ROM bank
        bank := m.prg_bank % r.header.prg_rom_banks
        effective_address := 0x4000 * int(bank) + int(address - 0x8000)
        return r.prg_rom[effective_address], 0xFF

    case 0xC000 ..= 0xFFFF: // 16 KB Fixed PRG-ROM bank (Last bank)
        bank := r.header.prg_rom_banks - 1
        effective_address := 0x4000 * int(bank) + int(address - 0xC000)
        return r.prg_rom[effective_address], 0xFF
    }

    return 0, 0
}

uxrom_cpu_write :: proc(m: ^UxROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF:
        if r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            m.prg_ram[effective_address] = value
            return true
        }

    case 0x8000 ..= 0xFFFF: 
        // UxROM uses only 4 low bits of the value, but since there are many other mappers that work
        // exactly like UxROM but allow more/less bits for the bank number, I'm saving the entire value
        // to be able to reuse this implementation for other mappers.
        m.prg_bank = value
        return true
    }

    return false
}

uxrom_ppu_read :: proc(m: ^UxROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 { 
            return m.chr_ram[address], 0xFF
        }

        return r.chr_rom[address], 0xFF
    }

    return 0, 0
}

uxrom_ppu_write :: proc(m: ^UxROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 { 
            m.chr_ram[address] = value 
            return true
        }

        return false
    }

    return false
}
