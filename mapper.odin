package main

import "core:mem"

Mapper_Not_Supported :: struct {
    mapper_number: u8,
}

Mapper_Initialization_Error :: union {
    mem.Allocator_Error,
    Mapper_Not_Supported,
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

mapper_init :: proc(rom: ^ROM) -> (mapper: Mapper, err: Mapper_Initialization_Error) {
	mapper_number := mapper_number(rom)

    err_alloc: mem.Allocator_Error

	switch mapper_number {
	case 0:
		mapper, err_alloc = new(NROM)
    case: 
        err = Mapper_Not_Supported{mapper_number}
	}

    // Since Mapper_Initialization_Error is not #shared_nil (to be able to return structs as error variants), 
    // we need to manully check allocator error for nil in order to avoid returning Allocator_Error.None as 
    // a legitimate error.
    if err_alloc != nil {
        return nil, err_alloc
    }

	return
}

mapper_free :: proc(mapper: Mapper) {
	switch m in mapper {
	case ^NROM:
		free(m)
	}
}
