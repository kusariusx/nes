package main

CPU_Bus :: struct {
	ram: [2 * 1024]u8, // 2 KB internal RAM

    // TODO: instead of all these links, maybe just link all components directly to the NES object itself?
    ppu: ^PPU,
    ppu_bus: ^PPU_Bus,

    apu: ^APU,

    rom: ^ROM,
    mapper: Mapper,

    io: ^IO,

    // TODO: move this into a separate DMA module
    oam_dma_perform_alignment_cycle: bool,
    oam_dma_pending: bool,
    oam_dma_active: bool,
    oam_dma_address: u16,
    oam_dma_data: u8,

    // Reading open bus returns the last value read from valid address, or written to any address.
    data_bus_value: u8,

    // Actually there are 3 "internal" address buses: CPU, DMC DMA and OAM DMA. They are multiplexed onto
    // a single "external" address bus which actually decides what data to load. This variable tracks CPU internal
    // address bus for the purpose of gating access to APU registers - they are active and readable only when
    // CPU address bus points to the range $4000-$401F.
    address_bus_value: u16,
}

cpu_bus_read :: proc(b: ^CPU_Bus, address: u16, is_dma := false) -> u8 {
    // DMA reads do not update CPU address bus, because DMAs have their own buses
    if !is_dma {
        b.address_bus_value = address
    }
    
    value, mask: u8

    apu_registers_active := b.address_bus_value >= 0x4000 && b.address_bus_value <= 0x401F
    apu_address_space := address >= 0x4000 && address <= 0x40FF
    mapper_region := address >= 0x4020 && address <= 0xFFFF

    if apu_registers_active {
        // APU address space is mirrored
        apu_address := 0x4000 | (address & 0x1F)
        apu_value, apu_mask := cpu_bus_resolve_read(b, apu_address)

        if apu_address_space { // Reading APU address space when it's active - all good
            value, mask = apu_value, apu_mask
        } else { // Trying to read outside of APU address space when it's active - bus conflict
            conflicting_value, conflicting_mask: u8

            if mapper_region {
                conflicting_value, conflicting_mask = mapper_cpu_read(b.mapper, b.rom, address)
            } else {
                conflicting_value, conflicting_mask = cpu_bus_resolve_read(b, address)
            }

            if mapper_region && apu_address == 0x4015 {
                // Special handling for address $4015 when conflicting with mapper - mapper completely overwrites the bus
                apu_mask = 0
            } else {
                // Conflicting value will occupy open bus bits of the APU value
                conflicting_mask = ~apu_mask
            }
            
            value = (apu_value & apu_mask) | (conflicting_value & conflicting_mask)
            mask = apu_mask | conflicting_mask

            trace(
                .CPU_BUS, 
                "bus conflict: apu_address = $%04X, apu_value = $%02X, apu_mask = $%02X, conflicting_value = $%02X, conflicting_mask = $%02X",
                apu_address, apu_value, apu_mask, conflicting_value, conflicting_mask,
            )
        }
    } else {
        if apu_address_space { // Trying to read APU address space when it's not active - open bus
            value, mask = 0, 0
        } else if mapper_region { // Unmapped space, let mapper handle
            value, mask = mapper_cpu_read(b.mapper, b.rom, address)
        } else {
            value, mask = cpu_bus_resolve_read(b, address)
        }
    }

    // Apply active value bits and retain inactive bits
    res := (b.data_bus_value & ~mask) | (value & mask)
    
    // Address 0x4015 is special - all data read from APU status register is internal to the APU chip itself,
    // so the data bus is not used (or more precisely - APU's own bus is used instead). However, we still 
    // retain inactive bits from the data bus, but we do not update it with the value we've read.
    if address != 0x4015 {
        b.data_bus_value = res
    }

    trace(.CPU_BUS, "read $%02X from $%04X, address bus - $%04X, data bus - $%02X", res, address, b.address_bus_value, b.data_bus_value)

    return res
}

cpu_bus_write :: proc(b: ^CPU_Bus, address: u16, value: u8) {
    b.data_bus_value = value

    if address >= 0x4020 && address <= 0xFFFF { 
        mapper_cpu_write(b.mapper, b.rom, address, value)
        return // Ignore unhandled writes
    }

    cpu_bus_resolve_write(b, address, value)

    trace(.CPU_BUS, "wrote $%02X to $%04X, address bus - $%04X, data bus - $%02X", value, address, b.address_bus_value, b.data_bus_value)
}

// Handles read-write and read-only addresses.
// Returns the value and a mask representing what bits of the value are active. Bits masked with 0's are open bus.
cpu_bus_resolve_read :: proc(b: ^CPU_Bus, address: u16) -> (value: u8, mask: u8) {
    switch address {
    case 0 ..= 0x1FFF: // Internal RAM (1 real and 3 mirrors)
        effective_address := address & 0x7FF // Mask to 11 bits (2 KB)
        return b.ram[effective_address], 0xFF
    case 0x2000 ..= 0x3FFF: // PPU registers (8 real registers, the rest are mirrors)
        effective_address := u8(address & 0x7) // Mask to 3 bits (8 registers)
        return ppu_read_register(b.ppu, b.ppu_bus, effective_address), 0xFF
    case 0x4000 ..= 0x4017: // APU and IO registers
        if address == 0x4016 || address == 0x4017 { // IO registers
            return io_read_register(b.io, address)
        }

        return apu_read_register(b.apu, address)
    case 0x4018 ..= 0x401F: // Additional APU and IO functionality which is normally disabled
    case 0x4020 ..= 0xFFFF: // Unmapped - cartridges are free to map this area to anything 
    }

    return 0, 0
}

// Handles read-write and write-only addresses
cpu_bus_resolve_write :: proc(b: ^CPU_Bus, address: u16, value: u8) {
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
        case 0x4016: // IO
            io_write_register(b.io, address, value)
        case:
            apu_write_register(b.apu, address, value)
        }
    case 0x4018 ..= 0x401F: // Additional APU and IO functionality which is normally disabled
    case 0x4020 ..= 0xFFFF: // Unmapped - cartridges are free to map this area to anything 
    }
}
