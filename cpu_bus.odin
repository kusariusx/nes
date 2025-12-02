package main

// TODO: implement proper open bus behavior
CPU_OPEN_BUS_VALUE :: 0xFF

NES_CPU_Bus :: struct {
	ram: [2 * 1024]u8, // 2 KB internal RAM

    ppu: ^PPU,
    ppu_bus: ^NES_PPU_Bus,

    rom: ^ROM,
    mapper: Mapper,

    // CPU will check these, and other components will write into them
    nmi_pending: bool,
    irq_pending: bool,

    oam_dma_pending: bool,
    oam_dma_active: bool,
    oam_dma_address: u16,
    oam_dma_data: u8,
}

nes_cpu_bus_read :: proc(b: ^NES_CPU_Bus, address: u16) -> u8 {
    if address >= 0x4020 && address <= 0xFFFF { // Unmapped space, let mapper handle
        value, handled := mapper_cpu_read(b.mapper, b.rom, address)
        if handled {
            return value
        }

        return CPU_OPEN_BUS_VALUE
    }

    return nes_cpu_bus_resolve_read(b, address)
}

nes_cpu_bus_write :: proc(b: ^NES_CPU_Bus, address: u16, value: u8) {
    if address >= 0x4020 && address <= 0xFFFF { 
        mapper_cpu_write(b.mapper, b.rom, address, value)
        return // Ignore unhandled writes
    }

    nes_cpu_bus_resolve_write(b, address, value)
}

// Handles read-write and read-only addresses
nes_cpu_bus_resolve_read :: proc(b: ^NES_CPU_Bus, address: u16) -> u8 {
    switch address {
    case 0 ..= 0x1FFF: // Internal RAM (1 real and 3 mirrors)
        effective_address := address & 0x7FF // Mask to 11 bits (2 KB)
        return b.ram[effective_address]
    case 0x2000 ..= 0x3FFF: // PPU registers (8 real registers, the rest are mirrors)
        effective_address := address & 0x7 // Mask to 3 bits (8 registers)
        switch effective_address {
        case 2: // PPUSTATUS
            value := u8(b.ppu.PPUSTATUS)

            // Reading PPUSTATUS has some side effects
            b.ppu.PPUSTATUS.V = 0
            b.ppu.w = 0

            return value
        case 4: // OAMDATA
            // TODO: if OAMDATA is read during rendering, different values are returned (based on sprite evaluation state)
            return b.ppu.oam[b.ppu.OAMADDR]
        case 7: // PPUDATA
            // Read current data
            value := ppu_bus_read(b.ppu_bus, b.ppu.v)

            // We return data from the internal buffer, i.e. all reads are delayed
            result := b.ppu.ppudata_read_buffer

            // Special handling for palette RAM - these reads are unbuffered
            if b.ppu.v >= 0x3F00 && b.ppu.v <= 0x3FFF {
                result = value // Replace result with current/unbuffered data

                // When reading palette memory, the internal buffer is not filled with palette data,
                // but with data "underneath" the palette memory in PPU address space - this is usually the 
                // mirrored nametable. Subtract 0x1000 to mirror 0x3XXX addresses into 0x2XXX.
                b.ppu.ppudata_read_buffer = ppu_bus_read(b.ppu_bus, b.ppu.v - 0x1000)
            } else {
                // Update buffer with current read
                b.ppu.ppudata_read_buffer = value
            }

            // Auto-increment v based on PPUCTRL.I
            b.ppu.v += b.ppu.PPUCTRL.I == 0 ? 1 : 32

            return result
        }
    case 0x4000 ..= 0x4017: // APU and IO registers
    case 0x4018 ..= 0x401F: // Additional APU and IO functionality which is normally disabled
    case 0x4020 ..= 0xFFFF: // Unmapped - cartridges are free to map this area to anything 
    }

    return CPU_OPEN_BUS_VALUE
}

// Handles read-write and write-only addresses
nes_cpu_bus_resolve_write :: proc(b: ^NES_CPU_Bus, address: u16, value: u8) {
    switch address {
    case 0 ..= 0x1FFF: // Internal RAM (1 real and 3 mirrors)
        effective_address := address & 0x7FF // Mask to 11 bits (2 KB)
        b.ram[effective_address] = value
    case 0x2000 ..= 0x3FFF: // PPU registers (8 real registers, the rest are mirrors)
        effective_address := address & 0x7 // Mask to 3 bits (8 registers)
        switch effective_address {
        case 0: // PPUCTRL
            orig_nmi_enabled := b.ppu.PPUCTRL.V
            b.ppu.PPUCTRL = PPUCTRL_Bits(value)

            // If VBlank NMI was enabled during VBlank - request NMI immediately
            if orig_nmi_enabled == 0 && b.ppu.PPUCTRL.V == 1 && b.ppu.PPUSTATUS.V == 1 {
                b.nmi_pending = true
            }

            // Update bits 10 and 11 of PPU's internal t register
            b.ppu.t = (b.ppu.t & 0xF3FF) | (u16(b.ppu.PPUCTRL.NN) << 10)
        case 1: // PPUMASK
            b.ppu.PPUMASK = PPUMASK_Bits(value)
        case 3: // OAMADDR
            b.ppu.OAMADDR = value
        case 4: // OAMDATA
            b.ppu.oam[b.ppu.OAMADDR] = value
            b.ppu.OAMADDR += 1 // Will wrap automatically since OAMADDR is u8
        case 5: // PPUSCROLL
            // Note: I could've stored these values in separate variables - it would've been simpler.
            // But I want to emulate the original hardware behavior, so I'm using PPU internal registers to
            // store these values (in rather obscure format).

            // Note: t and v are 15-bit registers, but I'm using full 16-bit masks for clarity
            // Odin allows underscores in numeric literals - very convenient for separating bytes.

            if b.ppu.w == 0 { // First write (X scroll)
                b.ppu.x = value & 0b111 // Set fine X scroll
                b.ppu.t = (b.ppu.t & 0b11111111_11100000) | (u16(value) >> 3) // Set coarse X scroll
                b.ppu.w = 1 // Toggle w
            } else { // Second write (Y scroll)
                b.ppu.t = (b.ppu.t & 0b10001111_11111111) | (u16(value & 0b00000111) << 12) // Set fine Y scroll
                b.ppu.t = (b.ppu.t & 0b11111100_00011111) | (u16(value & 0b11111000) << 2) // Set coarse Y scroll
                b.ppu.w = 0 // Toggle w back
            }
        case 6: // PPUADDR
            if b.ppu.w == 0 { // First write (high byte)
                b.ppu.t = (b.ppu.t & 0b10000000_11111111) | (u16(value & 0b00111111) << 8) // Set bits 8-13 and clear bit 14
                b.ppu.w = 1 // Toggle w
            } else { // Second write (low byte)
                b.ppu.t = (b.ppu.t & 0b11111111_00000000) | u16(value) // Set bits 0-7
                b.ppu.v = b.ppu.t // Copy t into v
                b.ppu.w = 0 // Toggle w back
            }
        case 7: // PPUDATA
            ppu_bus_write(b.ppu_bus, b.ppu.v, value)

            // Auto-increment v based on PPUCTRL.I
            b.ppu.v += b.ppu.PPUCTRL.I == 0 ? 1 : 32

            // TODO: when writing during rendering, instead of auto-increment, v is updated in a weird way,
            // causing simultaneous coarse X increment and Y increment.
        }
    case 0x4000 ..= 0x4017: // APU and IO registers
        switch address {
        case 0x4014: // OAMDMA
            b.oam_dma_pending = true
            b.oam_dma_address = u16(value) << 8
        }
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
    return CPU_OPEN_BUS_VALUE
}

cpu_bus_write :: proc(b: CPU_Bus, address: u16, value: u8) {
    switch bus in b {
    case ^NES_CPU_Bus:
        nes_cpu_bus_write(bus, address, value)
    case ^Test_CPU_Bus:
        test_cpu_bus_write(bus, address, value)
    }
}
