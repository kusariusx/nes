package main

NES_CPU_Bus :: struct {
	ram: [2 * 1024]u8, // 2 KB internal RAM

    ppu: ^PPU,
    ppu_bus: ^NES_PPU_Bus,

    apu: ^APU,

    rom: ^ROM,
    mapper: Mapper,

    oam_dma_pending: bool,
    oam_dma_active: bool,
    oam_dma_address: u16,
    oam_dma_data: u8,

    // Reading open bus returns the last value read from valid address
    last_read_value: u8,
}

nes_cpu_bus_read :: proc(b: ^NES_CPU_Bus, address: u16) -> u8 {
    value: u8
    handled: bool
    
    if address >= 0x4020 && address <= 0xFFFF { // Unmapped space, let mapper handle
        value, handled = mapper_cpu_read(b.mapper, b.rom, address)
    } else {
        value, handled = nes_cpu_bus_resolve_read(b, address)
    }

    if !handled { // Read was not handled - open bus
        return b.last_read_value
    }

    b.last_read_value = value
    return value
}

nes_cpu_bus_write :: proc(b: ^NES_CPU_Bus, address: u16, value: u8) {
    if address >= 0x4020 && address <= 0xFFFF { 
        mapper_cpu_write(b.mapper, b.rom, address, value)
        return // Ignore unhandled writes
    }

    nes_cpu_bus_resolve_write(b, address, value)
}

// Handles read-write and read-only addresses
nes_cpu_bus_resolve_read :: proc(b: ^NES_CPU_Bus, address: u16) -> (value: u8, handled: bool) {
    switch address {
    case 0 ..= 0x1FFF: // Internal RAM (1 real and 3 mirrors)
        effective_address := address & 0x7FF // Mask to 11 bits (2 KB)
        return b.ram[effective_address], true
    case 0x2000 ..= 0x3FFF: // PPU registers (8 real registers, the rest are mirrors)
        effective_address := u8(address & 0x7) // Mask to 3 bits (8 registers)
        return ppu_read_register(b.ppu, b.ppu_bus, effective_address), true
    case 0x4000 ..= 0x4017: // APU and IO registers
        return apu_read_register(b.apu, address)
    case 0x4018 ..= 0x401F: // Additional APU and IO functionality which is normally disabled
    case 0x4020 ..= 0xFFFF: // Unmapped - cartridges are free to map this area to anything 
    }

    return 0, false
}

// Handles read-write and write-only addresses
nes_cpu_bus_resolve_write :: proc(b: ^NES_CPU_Bus, address: u16, value: u8) {
    switch address {
    case 0 ..= 0x1FFF: // Internal RAM (1 real and 3 mirrors)
        effective_address := address & 0x7FF // Mask to 11 bits (2 KB)
        b.ram[effective_address] = value
    case 0x2000 ..= 0x3FFF: // PPU registers (8 real registers, the rest are mirrors)
        effective_address := u8(address & 0x7) // Mask to 3 bits (8 registers)
        ppu_write_register(b.ppu, b.ppu_bus, effective_address, value)
    case 0x4000 ..= 0x4017: // APU and IO registers
        switch address {
        case 0x4014: // OAMDMA
            b.oam_dma_pending = true
            b.oam_dma_address = u16(value) << 8
        }

        apu_write_register(b.apu, address, value)
    case 0x4018 ..= 0x401F: // Additional APU and IO functionality which is normally disabled
    case 0x4020 ..= 0xFFFF: // Unmapped - cartridges are free to map this area to anything 
    }
}

Test_CPU_Bus :: struct {
    ram: [0x10000]u8,
    
    track_memory_access: bool,
    memory_access_idx: int,
    memory_accesses: [10]struct{ // 10 should be sufficient for any instruction
        address, value: u16,
        operation: string,
    },
}

test_cpu_bus_read :: proc(b: ^Test_CPU_Bus, address: u16) -> u8 {
    res := b.ram[address]

    if b.track_memory_access {
        b.memory_accesses[b.memory_access_idx] = {
            address = address,
            value = u16(res),
            operation = "read",
        }

        b.memory_access_idx += 1
    }

    return res
}

test_cpu_bus_write :: proc(b: ^Test_CPU_Bus, address: u16, value: u8) {
    b.ram[address] = value
        
    if b.track_memory_access {
        b.memory_accesses[b.memory_access_idx] = {
            address = address,
            value = u16(value),
            operation = "write",
        }
        
        b.memory_access_idx += 1
    }
}

CPU_Bus :: union {
    ^NES_CPU_Bus,
    ^Test_CPU_Bus,
}

cpu_bus_read :: proc(b: CPU_Bus, address: u16) -> u8 {
    switch bus in b {
    case ^NES_CPU_Bus:
        return nes_cpu_bus_read(bus, address)
    case ^Test_CPU_Bus:
        return test_cpu_bus_read(bus, address)
    }

    // Should never happen since switch is exhaustive
    return 0
}

cpu_bus_write :: proc(b: CPU_Bus, address: u16, value: u8) {
    switch bus in b {
    case ^NES_CPU_Bus:
        nes_cpu_bus_write(bus, address, value)
    case ^Test_CPU_Bus:
        test_cpu_bus_write(bus, address, value)
    }
}
