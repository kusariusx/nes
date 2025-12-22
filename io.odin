package main

IO_Port :: enum {
    // General-purpose ports
    Port_1,
    Port_2,

    Expansion_Port,
}

IO :: struct {
    ports: [IO_Port]Peripheral,
}

io_read_register :: proc(io: ^IO, address: u16) -> (value: u8, handled: bool) {
    switch address {
    case 0x4016:
        result := u8(0)

        // Input is connected to both general-purpose port and expansion port
        if io.ports[IO_Port.Port_1] != nil {
            input := peripheral_read(io.ports[IO_Port.Port_1])

            // General-purpose ports input is 3 bits wide.
            // Whatever 3 bits we read from the peripheral, put them into bits 0, 3 and 4 of the result
            // since those bits are actually connected to the bus.
            result |= ((input << 2) & 0b11000) | (input & 1)
        }
        
        if io.ports[IO_Port.Expansion_Port] != nil {
            input := peripheral_read(io.ports[IO_Port.Expansion_Port])

            // Expansion port input is 5 bits wide which is connected to bits 0-4 on the bus
            result |= input & 0b11111
        }
        
        return result, true
    case 0x4017:
        result := u8(0)

        if io.ports[IO_Port.Port_2] != nil {
            input := peripheral_read(io.ports[IO_Port.Port_2])
            result |= ((input << 2) & 0b11000) | (input & 1)
        }
        
        if io.ports[IO_Port.Expansion_Port] != nil {
            input := peripheral_read(io.ports[IO_Port.Expansion_Port])
            result |= input & 0b11111
        }
        
        return result, true
    }

    return 0, false
}

io_write_register :: proc(io: ^IO, address: u16, value: u8) -> (handled: bool) {
    switch address {
    case 0x4016:
        value_gp := value & 1 // Only a single bit is going to general-purpose ports
        value_exp := value & 0b111 // All 3 bits are going to the expansion port

        // There's a single output port that is routed to all peripherals
        if io.ports[IO_Port.Port_1] != nil {
            peripheral_write(io.ports[IO_Port.Port_1], value_gp)
        }

        if io.ports[IO_Port.Port_2] != nil {
            peripheral_write(io.ports[IO_Port.Port_2], value_gp)
        }

        if io.ports[IO_Port.Expansion_Port] != nil {
            peripheral_write(io.ports[IO_Port.Expansion_Port], value_exp)
        }

        return true
    }

    return false
}
