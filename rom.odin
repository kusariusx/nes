package main

import "core:mem"

PRG_ROM_BANK_SIZE :: 0x4000
CHR_ROM_BANK_SIZE :: 0x2000

PRG_RAM_BANK_SIZE :: 0x2000

INES_Header_Data :: struct {
    flags_8: byte, // Number of PRG RAM banks
    flags_9: bit_field byte {
        tv_system: byte | 1, // (0: NTSC; 1: PAL)
        // Other 7 bits are reserved and set to zero
    },
    flags_10: bit_field byte {
        tv_system: byte | 2, // (0: NTSC; 2: PAL; 1/3: dual compatible)
        _: byte | 2, // Padding
        prg_ram_present: byte | 1, // (0: present; 1: not present)
        bus_conflicts: byte | 1, // 0: Board has no bus conflicts; 1: Board has bus conflicts
    },
    // Bytes 11-15 are not used, but sometimes random data is put there
}

ROM_Header :: struct { // First 16-bytes of the ROM
    nes_constant: []byte, // Constant $4E $45 $53 $1A (ASCII "NES" followed by MS-DOS end-of-file)
    prg_rom_banks: byte,
    chr_rom_banks: byte, // Can be 0
    flags_6: bit_field byte {
        nametable_arrangement: byte | 1,
        battery_backed_memory: byte | 1,
        trainer: byte | 1,
        alternative_nametable_layout: byte | 1,
        mapper_low_nibble: byte | 4,
    },
    flags_7: bit_field byte {
        vs_unisystem: byte | 1,
        playchoice_10: byte | 1,
        nes_2_0: byte | 2, // If equal to 2, bytes 8-15 of the header are in NES 2.0 format
        mapper_high_nibble: byte | 4,
    },
    format_specific_flags: union {
        INES_Header_Data,
    },

    // Precalculated format-agnostic info
    prg_ram_size: u16,
}

ROM :: struct {
    header: ROM_Header,
    trainer: [512]byte, // Could be absent, preallocate for simplicity
    prg_rom: []byte, // Program ROM
    chr_rom: []byte, // Character? ROM - holds graphics tile data
    
    // TODO: ROM could also contain:
    // PlayChoice INST-ROM, if present (0 or 8192 bytes)
    // PlayChoice PROM, if present (16 bytes Data, 16 bytes CounterOut)
}

Parsing_Errors :: enum {
    Invalid_Header,
}

Parsing_Error :: union #shared_nil {
    mem.Allocator_Error,
    Parsing_Errors,
}

rom_parse :: proc(data: []byte) -> (rom: ^ROM, err: Parsing_Error) {
    if len(data) < 16 {
        return nil, Parsing_Errors.Invalid_Header
    }
    
    // ROMs could be large, so allocate it on the heap
    rom = new(ROM) or_return

    // Header
    rom.header = {
        nes_constant = data[0:4],
        prg_rom_banks = data[4],
        chr_rom_banks = data[5],
        flags_6 = auto_cast data[6],
        flags_7 = auto_cast data[7],
    }

    if rom.header.flags_7.nes_2_0 != 2 {
        rom.header.format_specific_flags = INES_Header_Data{
            flags_8 = data[8],
            flags_9 = auto_cast data[9],
            flags_10 = auto_cast data[10],
        }
    }

    // Optional trainer
    ptr := 16
    if rom.header.flags_6.trainer == 1 {
        copy(rom.trainer[:], data[ptr:ptr+512])
        ptr += 512
    }

    // PRG ROM
    prg_rom_size := int(rom.header.prg_rom_banks) * PRG_ROM_BANK_SIZE
    rom.prg_rom = make([]byte, prg_rom_size)
    copy(rom.prg_rom, data[ptr:ptr+prg_rom_size])
    ptr += prg_rom_size

    // CHR ROM
    chr_rom_size := int(rom.header.chr_rom_banks) * CHR_ROM_BANK_SIZE
    rom.chr_rom = make([]byte, chr_rom_size)
    copy(rom.chr_rom, data[ptr:ptr+chr_rom_size])
    ptr += chr_rom_size

    // Precalculate some info for later use
    rom.header.prg_ram_size = rom_prg_ram_size(rom)

    return
}

rom_free :: proc(rom: ^ROM) {
    delete(rom.prg_rom)
    delete(rom.chr_rom)

    free(rom)
}

rom_prg_ram_size :: proc(rom: ^ROM) -> u16 {
    switch flags in rom.header.format_specific_flags {
    case INES_Header_Data:
        if flags.flags_10.prg_ram_present == 1 {
            // This flag is an extension to the original iNES 1.0 format and is almost never used, but I'd like
            // to support it anyway as the only option to explicitly disable PRG-RAM in iNES 1.0 ROMs. 
            return 0
        }

        if flags.flags_8 > 0 {
            return u16(flags.flags_8) * PRG_RAM_BANK_SIZE
        }

        // When both flags_8 and flags_10.prg_ram_present are 0, we assume a single 8 KB bank of PRG-RAM
        return PRG_RAM_BANK_SIZE 
    }

    return 0
}
