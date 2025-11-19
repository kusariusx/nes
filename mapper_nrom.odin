package main

NROM :: struct{
    prg_ram: [0x2000]byte,
} 

nrom_cpu_read :: proc(m: ^NROM, r: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF: // PRG-RAM
        size := rom_prg_ram_size(r) 
        if size > 0 {
            effective_address := (address - 0x6000) % size
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
    return false
}

nrom_ppu_read :: proc(m: ^NROM, r: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch address {
    case 0x0000 ..= 0x1FFF:
        return r.chr_rom[address], true
    }

    return 0, false
}

nrom_ppu_write :: proc(m: ^NROM, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    return false
}
