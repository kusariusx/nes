package main

AxROM :: struct {
    prg_bank: u8,
    vram_bank: u8,

    chr_ram: [0x2000]byte,

    vram: []byte,
}

axrom_cpu_read :: proc(m: ^AxROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x8000 ..= 0xFFFF:
        effective_address := 0x8000 * int(m.prg_bank) + int(address - 0x8000)
        return r.prg_rom[effective_address], 0xFF
    }

    return 0, 0
}

axrom_cpu_write :: proc(m: ^AxROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    prg_rom_banks := max(1, r.header.prg_rom_banks / 2) // AxROM operates with 32Kb banks

    switch address {
    case 0x8000 ..= 0xFFFF:
        // Standard AxROM uses low 3 bits for the bank size, but there are oversized AxROM variations,
        // so store the 4th bit as well to support them.
        m.prg_bank = (value & 0x0F) % prg_rom_banks
        m.vram_bank = (value >> 4) & 1
        return true
    }

    return false
}

axrom_ppu_read :: proc(m: ^AxROM, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 {
            return m.chr_ram[address], 0xFF
        }
    case 0x2000 ..= 0x2FFF:
        effective_address := int(m.vram_bank) * 0x400 + int(address & 0x3FF)
        return m.vram[effective_address], 0xFF
    }

    return 0, 0
}

axrom_ppu_write :: proc(m: ^AxROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 {
            m.chr_ram[address] = value
            return true
        }
    case 0x2000 ..= 0x2FFF:
        effective_address := int(m.vram_bank) * 0x400 + int(address & 0x3FF)
        m.vram[effective_address] = value
        return true
    }

    return false
}
