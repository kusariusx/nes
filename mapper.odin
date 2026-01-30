package main

import "core:mem"

Mapper_Not_Supported :: struct {
    mapper_number: u8,
}

Mapper_Initialization_Error :: union {
    mem.Allocator_Error,
    Mapper_Not_Supported,
}

System_Event :: enum {
    PPU_Address_Bus_Changed,
}

Mapper :: union {
    ^NROM,
    ^MMC1,
    ^MMC3,
    ^UxROM,
    ^CNROM,
    ^AxROM,
}

mapper_cpu_read :: proc(mapper: Mapper, rom: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch m in mapper {
    case ^NROM: 
        return nrom_cpu_read(m, rom, address)
    case ^MMC1: 
        return mmc1_cpu_read(m, rom, address)
    case ^MMC3: 
        return mmc3_cpu_read(m, rom, address)
    case ^UxROM: 
        return uxrom_cpu_read(m, rom, address)
    case ^CNROM: 
        return cnrom_cpu_read(m, rom, address)
    case ^AxROM: 
        return axrom_cpu_read(m, rom, address)
    }

    // Should not happen as the switch is exhaustive
    return 0, 0
}

mapper_cpu_write :: proc(mapper: Mapper, rom: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_cpu_write(m, rom, address, value)
    case ^MMC1: 
        return mmc1_cpu_write(m, rom, address, value)
    case ^MMC3: 
        return mmc3_cpu_write(m, rom, address, value)
    case ^UxROM: 
        return uxrom_cpu_write(m, rom, address, value)
    case ^CNROM: 
        return cnrom_cpu_write(m, rom, address, value)
    case ^AxROM: 
        return axrom_cpu_write(m, rom, address, value)
    }

    return false
}

mapper_ppu_read :: proc(mapper: Mapper, rom: ^ROM, address: u16) -> (value: u8, mask: u8) {
    switch m in mapper {
    case ^NROM: 
        return nrom_ppu_read(m, rom, address)
    case ^MMC1: 
        return mmc1_ppu_read(m, rom, address)
    case ^MMC3: 
        return mmc3_ppu_read(m, rom, address)
    case ^UxROM:
        return uxrom_ppu_read(m, rom, address)
    case ^CNROM:
        return cnrom_ppu_read(m, rom, address)
    case ^AxROM:
        return axrom_ppu_read(m, rom, address)
    }

    return 0, 0
}

mapper_ppu_write :: proc(mapper: Mapper, rom: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch m in mapper {
    case ^NROM: 
        return nrom_ppu_write(m, rom, address, value)
    case ^MMC1: 
        return mmc1_ppu_write(m, rom, address, value)
    case ^MMC3: 
        return mmc3_ppu_write(m, rom, address, value)
    case ^UxROM:
        return uxrom_ppu_write(m, rom, address, value)
    case ^CNROM:
        return cnrom_ppu_write(m, rom, address, value)
    case ^AxROM:
        return axrom_ppu_write(m, rom, address, value)
    }

    return false
}

mapper_notify :: proc(mapper: Mapper, event: System_Event) {
    #partial switch m in mapper {
    case ^MMC3:
        mmc3_handle_event(m, event)
    }
}

mapper_number :: proc(rom: ^ROM) -> u8 {
    return (rom.header.flags_7.mapper_high_nibble << 4) | rom.header.flags_6.mapper_low_nibble
}

mapper_init :: proc(nes: ^NES) -> (mapper: Mapper, err: Mapper_Initialization_Error) {
    err_alloc: mem.Allocator_Error

    mapper_number := mapper_number(nes.rom)

	switch mapper_number {
	case 0:
		mapper, err_alloc = new(NROM)
    case 1:
        mapper, err_alloc = new_clone(MMC1{
            shift_register = 0b10000,
            control = 0x0C,
            vram = nes.ppu_bus.vram[:],
        })
    case 2:
        mapper, err_alloc = new(UxROM)
    case 3:
        mapper, err_alloc = new(CNROM)
    case 4:
        mapper, err_alloc = new_clone(MMC3{
            cpu = nes.cpu,
            ppu_bus = nes.ppu_bus,
            vram = nes.ppu_bus.vram[:],
        })
    case 7:
        mapper, err_alloc = new_clone(AxROM{
            vram = nes.ppu_bus.vram[:],
        })
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
    case ^MMC1:
        free(m)
    case ^MMC3:
        free(m)
    case ^UxROM:
        free(m)
    case ^CNROM:
        free(m)
    case ^AxROM:
        free(m)
	}
}
