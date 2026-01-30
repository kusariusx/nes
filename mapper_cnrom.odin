package main

CNROM :: struct {
    chr_bank: u8,
    prg_ram: [0x2000]byte,
}

cnrom_cpu_read :: proc(m: ^CNROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x6000 ..= 0x7FFF:
        if r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            return m.prg_ram[effective_address], 0xFF
        }

    case 0x8000 ..= 0xFFFF:
        prg_rom_size := int(r.header.prg_rom_banks) * PRG_ROM_BANK_SIZE
        effective_address := int(address - 0x8000) % prg_rom_size
        return r.prg_rom[effective_address], 0xFF
    }

    return 0, 0
}

cnrom_cpu_write :: proc(m: ^CNROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF:
        if r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            m.prg_ram[effective_address] = value
            return true
        }

    case 0x8000 ..= 0xFFFF:
        // CNROM always has bus conflicts
        conflicting_value, _ := cnrom_cpu_read(m, r, address)
        value := value & conflicting_value
        
        // Standard CNROM uses bits 0-1 (for total of 4 banks, 8Kb each). Just in case, store the full byte
        // to support oversize CNROM variants (up to 2MB theoretically).
        m.chr_bank = value
        return true
    }

    return false
}

cnrom_ppu_read :: proc(m: ^CNROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        bank := m.chr_bank % r.header.chr_rom_banks
        effective_address := 0x2000 * int(bank) + int(address)
        return r.chr_rom[effective_address], 0xFF
    }

    return 0, 0
}

cnrom_ppu_write :: proc(m: ^CNROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    // CNROM does not have CHR-RAM and does not remap VRAM access
    return false
}
