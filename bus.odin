package main

OPEN_BUS_VALUE :: 0xFF

NES_Bus :: struct {
	ram: [2 * 1024]u8, // 2 KB internal RAM
}

Test_Bus :: struct {
    ram: [0x10000]u8,
    
    memory_access_idx: int,
    memory_accesses: [10]struct{ // 10 should be sufficient for any instruction
        address, value: u16,
        operation: string,
    },
}

Bus :: union {
    ^NES_Bus,
    ^Test_Bus,
}

bus_read :: proc(b: Bus, address: u16) -> u8 {
    switch bus in b {
    case ^NES_Bus:
        switch address {
        case 0 ..= 0x07FF:
            return bus.ram[address]
        case:
            return OPEN_BUS_VALUE
        }
    case ^Test_Bus:
        res := bus.ram[address]

        bus.memory_accesses[bus.memory_access_idx] = {
            address = address,
            value = u16(res),
            operation = "read",
        }

        bus.memory_access_idx += 1

        return res
    }

    return OPEN_BUS_VALUE
}

bus_write :: proc(b: Bus, address: u16, value: u8) {
    switch bus in b {
    case ^NES_Bus:
        switch address {
        case 0 ..= 0x07FF:
            bus.ram[address] = value
        }
    case ^Test_Bus:
        bus.ram[address] = value
        
        bus.memory_accesses[bus.memory_access_idx] = {
            address = address,
            value = u16(value),
            operation = "write",
        }
        
        bus.memory_access_idx += 1
    }
}
