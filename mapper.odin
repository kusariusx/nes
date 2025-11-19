package main

Mapper :: union {
    ^NROM,
}

mapper_cpu_read :: proc(mapper: Mapper, rom: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_cpu_read(m, rom, address)
    }

    // Should not happen as the switch is exhaustive
    return 0, false
}

mapper_cpu_write :: proc(mapper: Mapper, rom: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_cpu_write(m, rom, address, value)
    }

    return false
}

mapper_ppu_read :: proc(mapper: Mapper, rom: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_ppu_read(m, rom, address)
    }

    return 0, false
}

mapper_ppu_write :: proc(mapper: Mapper, rom: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_ppu_write(m, rom, address, value)
    }

    return false
}
