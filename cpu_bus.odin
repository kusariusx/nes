package main

OPEN_CPU_BUS_VALUE :: 0xFF

NES_CPU_Bus :: struct {
	ram: [2 * 1024]u8, // 2 KB internal RAM

    rom: ^ROM,
    mapper: Mapper,
}

nes_cpu_bus_read :: proc(b: ^NES_CPU_Bus, address: u16) -> u8 {
    if address >= 0x4020 && address <= 0xFFFF { // Unmapped space, let mapper handle
        value, handled := mapper_read(b.mapper, b.rom, address)
        if handled {
            return value
        }

        return OPEN_CPU_BUS_VALUE
    }

    memory := nes_cpu_bus_resolve(b, address)
    if memory != nil {
        return memory^
    }

    return OPEN_CPU_BUS_VALUE
}

nes_cpu_bus_write :: proc(b: ^NES_CPU_Bus, address: u16, value: u8) {
    if address >= 0x4020 && address <= 0xFFFF { 
        mapper_write(b.mapper, b.rom, address, value)
        return // Ignore unhandled writes
    }

    memory := nes_cpu_bus_resolve(b, address)
    if memory != nil {
        memory^ = value
    }
}

// For addresses that do not need special read/write handling
nes_cpu_bus_resolve :: proc(b: ^NES_CPU_Bus, address: u16) -> ^u8 {
    switch address {
    case 0 ..= 0x1FFF: // Internal RAM (1 real and 3 mirrors)
        effective_address := address & 0x7FF // Mask to 11 bits (2 KB)
        return &b.ram[address]
    case 0x2000 ..= 0x3FFF: // PPU registers (8 real registers, the rest are mirrors)
        effective_address := address & 0x7 // Mask to 3 bits (8 registers)
        switch effective_address {
        case 0: // PPUCTRL
        case 1: // PPUMASK
        case 2: // PPUSTATUS
        case 3: // OAMADDR
        case 4: // OAMDATA
        case 5: // PPUSCROLL
        case 6: // PPUADDR
        case 7: // PPUDATA
        }
    case 0x4000 ..= 0x4017: // APU and IO registers
    case 0x4018 ..= 0x401F: // Additional APU and IO functionality which is normally disabled
    case 0x4020 ..= 0xFFFF: // Unmapped - cartridges are free to map this area to anything 
    }

    return nil
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
    return OPEN_CPU_BUS_VALUE
}

cpu_bus_write :: proc(b: CPU_Bus, address: u16, value: u8) {
    switch bus in b {
    case ^NES_CPU_Bus:
        nes_cpu_bus_write(bus, address, value)
    case ^Test_CPU_Bus:
        test_cpu_bus_write(bus, address, value)
    }
}
