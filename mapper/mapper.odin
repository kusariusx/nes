package mapper

import rom "../rom"

Mapper :: union {
    ^NROM,
}

read :: proc(mapper: Mapper, rom: ^rom.ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_read(m, rom, address)
    }

    // Should not happen as the switch is exhaustive
    return 0, false
}

write :: proc(mapper: Mapper, rom: ^rom.ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_write(m, rom, address, value)
    }

    return false
}
