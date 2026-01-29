package main

MMC3_REVISION_A_IRQ :: false

MMC3 :: struct{
    bank_select: bit_field u8 {
        bank_register: u8 | 3,
        _:             u8 | 3,
        prg_rom_mode:  u8 | 1,
        chr_rom_mode:  u8 | 1,
    },

    bank_register: [8]u8,
    nametable_arrangement: u8,

    prg_ram_protect: bit_field u8 {
        _:                u8 | 6,
        write_protection: u8 | 1,
        prg_ram_enabled:  u8 | 1,
    },

    irq_latch: u8,
    irq_counter: u8,
    irq_reload: bool,
    irq_enabled: bool,

    ppu_a12_prev: u16,
    ppu_a12_last_rising_edge_clock: u64,
    cpu: ^CPU,
    ppu_bus: ^NES_PPU_Bus,

    prg_ram: [0x2000]byte,
    chr_ram: [0x2000]byte,
    vram: []byte,
} 

mmc3_cpu_read :: proc(m: ^MMC3, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    prg_rom_banks := r.header.prg_rom_banks * 2 // Header uses 16Kb banks, but MMC3 counts in 8Kb banks

    switch address {
    case 0x6000 ..= 0x7FFF:
        if r.header.prg_ram_size > 0 && m.prg_ram_protect.prg_ram_enabled == 1 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            return m.prg_ram[effective_address], 0xFF
        }
    case 0x8000 ..= 0x9FFF:
        bank_number := m.bank_select.prg_rom_mode == 0 ? m.bank_register[6] : prg_rom_banks - 2
        effective_address := int(bank_number) * 0x2000 + int(address - 0x8000)
        return r.prg_rom[effective_address], 0xFF
    case 0xA000 ..= 0xBFFF:
        bank_number := m.bank_register[7]
        effective_address := int(bank_number) * 0x2000 + int(address - 0xA000)
        return r.prg_rom[effective_address], 0xFF
    case 0xC000 ..= 0xDFFF:
        bank_number := m.bank_select.prg_rom_mode == 0 ? prg_rom_banks - 2 : m.bank_register[6]
        effective_address := int(bank_number) * 0x2000 + int(address - 0xC000)
        return r.prg_rom[effective_address], 0xFF
    case 0xE000 ..= 0xFFFF:
        bank_number := prg_rom_banks - 1
        effective_address := int(bank_number) * 0x2000 + int(address - 0xE000)
        return r.prg_rom[effective_address], 0xFF
    }

    return 0, 0
}

mmc3_cpu_write :: proc(m: ^MMC3, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    switch address {
    case 0x6000 ..= 0x7FFF:
        if r.header.prg_ram_size > 0 && m.prg_ram_protect.prg_ram_enabled == 1 && m.prg_ram_protect.write_protection == 0 {
            effective_address := int(address - 0x6000) % r.header.prg_ram_size
            m.prg_ram[effective_address] = value
        } else { // PRG RAM is not present - nowhere to write!
            return false
        }
    case 0x8000 ..= 0x9FFF:
        if address & 1 == 0 { // Bank select
            m.bank_select = auto_cast value
        } else { // Bank data
            value := value

            switch m.bank_select.bank_register {
            case 0, 1: // R0 and R1 ignore the bottom bit
                value &= 0b11111110
            case 6, 7: // R6 and R7 ignore the top two bits
                value &= 0b00111111
            }

            m.bank_register[m.bank_select.bank_register] = value
        }
    case 0xA000 ..= 0xBFFF:
        if address & 1 == 0 { // Nametable arrangement
            m.nametable_arrangement = value & 1
        } else { // PRG RAM protect
            m.prg_ram_protect = auto_cast value
        }
    case 0xC000 ..= 0xDFFF:
        if address & 1 == 0 { // IRQ latch
            m.irq_latch = value
        } else { // IRQ reload
            m.irq_counter = 0
            m.irq_reload = true
        }
    case 0xE000 ..= 0xFFFF:
        if address & 1 == 0 { // IRQ disable
            m.irq_enabled = false
            m.cpu.irq_external_line = false
        } else { // IRQ enable
            m.irq_enabled = true
        }
    case:
        return false
    }
    
    return true
}

mmc3_ppu_read :: proc(m: ^MMC3, r: ^ROM, address: u16) -> (value: u8, mask: u8) {
    if r.header.chr_rom_banks == 0 && address >= 0x0000 && address <= 0x1FFF {
        return m.chr_ram[address], 0xFF
    }

    switch address {
    case 0x0000 ..= 0x03FF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[0] : m.bank_register[2]
        effective_address := int(bank_number) * 0x400 + int(address)
        return r.chr_rom[effective_address], 0xFF
    case 0x0400 ..= 0x07FF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[0] + 1 : m.bank_register[3]
        effective_address := int(bank_number) * 0x400 + int(address - 0x0400)
        return r.chr_rom[effective_address], 0xFF
    case 0x0800 ..= 0x0BFF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[1] : m.bank_register[4]
        effective_address := int(bank_number) * 0x400 + int(address - 0x0800)
        return r.chr_rom[effective_address], 0xFF
    case 0x0C00 ..= 0x0FFF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[1] + 1 : m.bank_register[5]
        effective_address := int(bank_number) * 0x400 + int(address - 0x0C00)
        return r.chr_rom[effective_address], 0xFF

    case 0x1000 ..= 0x13FF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[2] : m.bank_register[0]
        effective_address := int(bank_number) * 0x400 + int(address - 0x1000)
        return r.chr_rom[effective_address], 0xFF
    case 0x1400 ..= 0x17FF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[3] : m.bank_register[0] + 1
        effective_address := int(bank_number) * 0x400 + int(address - 0x1400)
        return r.chr_rom[effective_address], 0xFF
    case 0x1800 ..= 0x1BFF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[4] : m.bank_register[1]
        effective_address := int(bank_number) * 0x400 + int(address - 0x1800)
        return r.chr_rom[effective_address], 0xFF
    case 0x1C00 ..= 0x1FFF:
        bank_number := m.bank_select.chr_rom_mode == 0 ? m.bank_register[5] : m.bank_register[1] + 1
        effective_address := int(bank_number) * 0x400 + int(address - 0x1C00)
        return r.chr_rom[effective_address], 0xFF

    case 0x2000 ..= 0x2FFF:
        nametable := (address >> 10) & 0b11

        bank: u16
        if m.nametable_arrangement == 0 { // Horizontal arrangement
            bank = nametable & 1
        } else { // Vertical arrangement
            bank = nametable >> 1
        }

        effective_address := int(bank) * VRAM_BANK_SIZE + int(address & 0x3FF)
        return m.vram[effective_address], 0xFF
    }

    return 0, 0
}

mmc3_ppu_write :: proc(m: ^MMC3, r: ^ROM, address: u16, value: u8) -> (write_handled: bool) {
    if r.header.chr_rom_banks == 0 && address >= 0x0000 && address <= 0x1FFF {
        m.chr_ram[address] = value
    }

    switch address {
    case 0x2000 ..= 0x2FFF:
        nametable := (address >> 10) & 0b11

        bank: u16
        if r.header.flags_6.alternative_nametable_layout == 1 {
            bank = nametable
        } else {
            if m.nametable_arrangement == 0 { // Horizontal arrangement
                bank = nametable & 1
            } else { // Vertical arrangement
                bank = nametable >> 1
            }
        }

        effective_address := int(bank) * VRAM_BANK_SIZE + int(address & 0x3FF)
        m.vram[effective_address] = value

        return true
    }
    
    return false
}

mmc3_handle_event :: proc(m: ^MMC3, event: System_Event) {
    is_rising_edge :: proc(m: ^MMC3) -> bool {
        rising_edge_delay :: 6 // CPU cycles (5-23)

        ppu_a12 := (m.ppu_bus.address_bus_value >> 12) & 1
        rising_edge := false

        if m.ppu_a12_prev == 0 && ppu_a12 == 1 {
            if m.cpu.clock - m.ppu_a12_last_rising_edge_clock > rising_edge_delay {
                rising_edge = true
            }

            m.ppu_a12_last_rising_edge_clock = m.cpu.clock
        }

        m.ppu_a12_prev = ppu_a12

        return rising_edge
    }

    switch event {
    case .PPU_Address_Bus_Changed:
        if !is_rising_edge(m) {
            break
        }

        orig := m.irq_counter

        if m.irq_counter == 0 || m.irq_reload {
            m.irq_counter = m.irq_latch
        } else {
            m.irq_counter -= 1
        }

        when MMC3_REVISION_A_IRQ {
            irq_condition := (orig > 0 || m.irq_reload) && m.irq_counter == 0 && m.irq_enabled
        } else {
            irq_condition := m.irq_counter == 0 && m.irq_enabled
        }

        if irq_condition {
            cpu_trigger_external_irq(m.cpu)
        }

        m.irq_reload = false
    }
}
