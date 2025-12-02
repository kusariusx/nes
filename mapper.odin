package main

import "core:mem"

Mapper_Initialization_Error :: union #shared_nil {
    mem.Allocator_Error,
    enum {
        MAPPER_NOT_SUPPORTED = 1,
    }
}

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

mapper_number :: proc(rom: ^ROM) -> u8 {
    return (rom.header.flags_7.mapper_high_nibble << 4) | rom.header.flags_6.mapper_low_nibble
}

mapper_init :: proc(rom: ^ROM) -> (Mapper, Mapper_Initialization_Error) {
	mapper_number := mapper_number(rom)

	switch mapper_number {
	case 0:
		return new(NROM)
	}

	return nil, .MAPPER_NOT_SUPPORTED
}

mapper_free :: proc(mapper: Mapper) {
	switch m in mapper {
	case ^NROM:
		free(m)
	}
}
