package main

MMC1 :: struct{
    // All MMC1 registers are 5 bit wide
    shift_register: u8,
    control: u8,
    chr_bank_0: u8,
    chr_bank_1: u8,
    prg_bank: u8,

    // MMC1 can modify how we map to internal VRAM, so include a pointer to it
    vram: []byte,

    prg_ram: [0x2000]byte, // 8 KB of optional PRG-RAM
    chr_ram: [0x2000]byte, // 8 KB of potential CHR-RAM
} 

mmc1_cpu_read :: proc(m: ^MMC1, r: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF: // Optional PRG-RAM
        prg_ram_enabled := (m.prg_bank >> 4) & 1 == 0
        if prg_ram_enabled && r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            return m.prg_ram[effective_address], true
        }
    case 0x8000 ..= 0xBFFF: // 16 KB PRG-ROM bank
        bank: u8

        bank_mode := (m.control >> 2) & 0b11
        switch bank_mode {
        case 0, 1: // Switch 32 KB at $8000, ignoring low bit of bank number
            bank = m.prg_bank & 0b01110
        case 2: // Fix first bank at $8000 and switch 16 KB bank at $C000
            bank = 0
        case 3: // Fix last bank at $C000 and switch 16 KB bank at $8000
            bank = m.prg_bank & 0b01111
        }

        bank %= r.header.prg_rom_banks

        effective_address := PRG_ROM_BANK_SIZE * int(bank) + int(address - 0x8000)
        return r.prg_rom[effective_address], true
    case 0xC000 ..= 0xFFFF: // 16 KB PRG-ROM bank
        bank: u8

        bank_mode := (m.control >> 2) & 0b11
        switch bank_mode {
        case 0, 1: // Switch 32 KB at $8000, ignoring low bit of bank number
            bank = (m.prg_bank & 0b01110) + 1 // +1 because this is the second half of the 32 KB bank
        case 2: // Fix first bank at $8000 and switch 16 KB bank at $C000
            bank = m.prg_bank & 0b01111
        case 3: // Fix last bank at $C000 and switch 16 KB bank at $8000
            bank = r.header.prg_rom_banks - 1
        }

        bank %= r.header.prg_rom_banks

        effective_address := PRG_ROM_BANK_SIZE * int(bank) + int(address - 0xC000)
        return r.prg_rom[effective_address], true
    }

    return 0, false
}

mmc1_cpu_write :: proc(m: ^MMC1, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF: // Optional PRG-RAM
        prg_ram_enabled := (m.prg_bank >> 4) & 1 == 0
        if prg_ram_enabled && r.header.prg_ram_size > 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            m.prg_ram[effective_address] = value
            
            return true
        }
    case 0x8000 ..= 0xFFFF: // Load register
        if value >> 7 == 1 {
            // Reset shift register
            m.shift_register = 0b10000 // Use 1 to keep track when shift register becomes full
            return true
        }

        // We shifted the initial 1 into 0-th position, meaning 4 bits have been loaded 
        // and we only need to shift one last bit.
        shift_register_full := m.shift_register & 1 == 1

        m.shift_register = (m.shift_register >> 1) | ((value & 1) << 4)

        if shift_register_full { 
            switch (address >> 13) & 0b11 { // Address bits 13-14 determine which register we write to
            case 0:
                m.control = m.shift_register
            case 1:
                m.chr_bank_0 = m.shift_register
            case 2:
                m.chr_bank_1 = m.shift_register
            case 3:
                m.prg_bank = m.shift_register
            }

            m.shift_register = 0b10000 // Shift register resets automatically after successfull write
        }
        
        return true
    }
    
    return false
}

mmc1_ppu_read :: proc(m: ^MMC1, r: ^ROM, address: u16) -> (value: u8, read_handled: bool) {
    switch address {
    case 0x0000 ..= 0x0FFF:
        bank := m.chr_bank_0
        if (m.control >> 4) & 1 == 0 { // 8KB mode
            bank &= 0b11110 // Ignore low bit
        }
        
        // Total number of 4KB banks (2x the 8KB bank count)
        total_banks := r.header.chr_rom_banks == 0 ? 2 : r.header.chr_rom_banks * 2
        bank %= total_banks
        
        effective_address := 0x1000 * int(bank) + int(address)    
        if r.header.chr_rom_banks == 0 {
            return m.chr_ram[effective_address], true
        } else {
            return r.chr_rom[effective_address], true
        }
    case 0x1000 ..= 0x1FFF:
        bank := m.chr_bank_1
        if (m.control >> 4) & 1 == 0 { // 8KB mode
            bank = (m.chr_bank_0 & 0b11110) + 1
        }
        
        total_banks := r.header.chr_rom_banks == 0 ? 2 : r.header.chr_rom_banks * 2
        bank %= total_banks
        
        effective_address := 0x1000 * int(bank) + int(address - 0x1000)
        if r.header.chr_rom_banks == 0 {
            return m.chr_ram[effective_address], true
        } else {
            return r.chr_rom[effective_address], true
        }
    case 0x2000 ..= 0x2FFF: // Internal VRAM
        bank: u16

        // What nametable are we trying to access (0-3)
        nametable := (address >> 10) & 0b11

        nametable_arrangement := m.control & 0b11
        switch nametable_arrangement {
        case 0: // One-screen, lower bank
            bank = 0
        case 1: // One-screen, upper bank
            bank = 1
        case 2: // Horizontal arrangement (vertical mirroring)
            bank = nametable & 1 // 0 -> 0, 1 -> 1, 2 -> 0, 3 -> 1
        case 3: // Vertical arrangement (horizontal mirroring)
            bank = nametable >> 1 // 0 -> 0, 1 -> 0, 2 -> 1, 3 -> 1
        }

        effective_address := int(bank) * VRAM_BANK_SIZE + int(address & 0x3FF)
        return m.vram[effective_address], true
    }

    return 0, false
}

mmc1_ppu_write :: proc(m: ^MMC1, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x0000 ..= 0x0FFF:
        if r.header.chr_rom_banks == 0 {
            bank := m.chr_bank_0
            if (m.control >> 4) & 1 == 0 {
                bank &= 0b11110
            }
            
            bank %= 2
            
            effective_address := 0x1000 * int(bank) + int(address)
            m.chr_ram[effective_address] = value

            return true
        }
    case 0x1000 ..= 0x1FFF:
        if r.header.chr_rom_banks == 0 {
            bank := m.chr_bank_1
            if (m.control >> 4) & 1 == 0 {
                bank = (m.chr_bank_0 & 0b11110) + 1
            }
            
            bank %= 2
            
            effective_address := 0x1000 * int(bank) + int(address - 0x1000)
            m.chr_ram[effective_address] = value

            return true
        }
    case 0x2000 ..= 0x2FFF:
        bank: u16

        nametable := (address >> 10) & 0b11
        nametable_arrangement := m.control & 0b11

        switch nametable_arrangement {
        case 0: // One-screen, lower bank
            bank = 0
        case 1: // One-screen, upper bank
            bank = 1
        case 2: // Horizontal arrangement (vertical mirroring)
            bank = nametable & 1
        case 3: // Vertical arrangement (horizontal mirroring)
            bank = nametable >> 1
        }

        effective_address := int(bank) * VRAM_BANK_SIZE + int(address & 0x3FF)
        m.vram[effective_address] = value

        return true
    }    
    
    return false
}
