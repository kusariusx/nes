package main

// Immediate addressing
imm :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 1:
        cpu_poll_interrupts(cpu, bus)
    case 2:
        // Fetch value, increment PC
        value := cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(value)
        cpu.PC += 1

        // Perform action
        action(cpu, bus, value)

        // Immediate instructions are always 2 cycle long, so we are done after the 2nd cycle
        cpu_instruction_done(cpu)
    }
}

// Common handling for zero-page addressing mode for read instructions
zpg_read :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 2:
        // Fetch address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1

        cpu_poll_interrupts(cpu, bus)
    case 3:
        // Fetch value from effective address
        value := cpu_bus_read(bus, u16(cpu.instruction_operand))

        // Perform action, complete instruction
        action(cpu, bus, value)
        cpu_instruction_done(cpu)
    }
}

// Zero-page indexed addressing, read instructions
// Effective address is (operand + index) % 256
zpgi_read :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, index_register: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 2:
        // Fetch address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from address, add index to it
        // This read is performed by the hardware but does not play any role - the result is discarded
        cpu_bus_read(bus, u16(cpu.instruction_operand))
        cpu.instruction_operand += index_register

        cpu_poll_interrupts(cpu, bus)
    case 4:    
        // Fetch value from effective address, perform action, done
        value := cpu_bus_read(bus, u16(cpu.instruction_operand))
        action(cpu, bus, value)
        cpu_instruction_done(cpu)
    }
}

// Absolute addressing, read instructions
abs_read :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 2:
        // Fetch low byte of address, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[LOW])
        cpu.PC += 1
    case 3:
        // Fetch high byte of address, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[HIGH])
        cpu.PC += 1

        cpu_poll_interrupts(cpu, bus)
    case 4:    
        // Fetch value from effective address, perform action, done
        value := cpu_bus_read(bus, cpu.instruction_operands.whole)
        action(cpu, bus, value)
        cpu_instruction_done(cpu)
    }
}

// Absolute indexed addressing, read instructions
// Index is either X or Y register
absi_read :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, index_register: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 2:
        // Fetch low byte of address, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[LOW])
        cpu.PC += 1
    case 3:
        // Fetch high byte of address, add index to low address byte, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[HIGH])
        cpu.instruction_operands.bytes[LOW] += index_register
        cpu.PC += 1

        // Poll for interrupts if page boundary was not crossed
        if cpu.instruction_operands.bytes[LOW] >= index_register {
            cpu_poll_interrupts(cpu, bus)
        }
    case 4:
        // Read from effective address
        value := cpu_bus_read(bus, cpu.instruction_operands.whole)
        
        if cpu.instruction_operands.bytes[LOW] < index_register { 
            // If page boundary was crossed (meaning if there was an overflow when adding index to low address byte), 
            // fix the high byte of effective addess
            cpu.instruction_operands.bytes[HIGH] += 1

            cpu_poll_interrupts(cpu, bus)
        } else {
            // If page boundary was not crossed, perform action and complete the instruction
            action(cpu, bus, value)
            cpu_instruction_done(cpu)
        }
    case 5:
        // Re-read from corrected effective address, perform action, done
        value := cpu_bus_read(bus, cpu.instruction_operands.whole)
        action(cpu, bus, value)
        cpu_instruction_done(cpu)
    }
}

// Indexed indirect addressing, read instructions
// Effective address is placed in memory at addresses (operand + X) and (operand + X + 1)
indx_read :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 2:
        // Fetch pointer address
        // Both instruction_operand and instruction_operands are used to keep the pointer zero-page address and effective address
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from pointer address (on zero page), add X to pointer address
        cpu_bus_read(bus, u16(cpu.instruction_operand)) // Performed by hardware but discarded
        cpu.instruction_operand += cpu.X
    case 4:
        // Fetch effective address low byte
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, u16(cpu.instruction_operand))
    case 5:
        // Fetch effective address high byte
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, u16(cpu.instruction_operand+1))

        cpu_poll_interrupts(cpu, bus)
    case 6:
        // Read from effective address, perform action, done
        value := cpu_bus_read(bus, cpu.instruction_operands.whole)
        action(cpu, bus, value)
        cpu_instruction_done(cpu)
    }
}

// Indirect indexed addressing, read instructions
// Effective address is placed in memory at addresses (operand) and (operand + 1), and then Y added to it
indy_read :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: u8)) {
    switch cycle {
    case 2:
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Fetch effective address low byte
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, u16(cpu.instruction_operand))
    case 4:
        // Fetch effective address high byte, add Y to low address byte
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, u16(cpu.instruction_operand+1))
        cpu.instruction_operands.bytes[LOW] += cpu.Y

        if cpu.instruction_operands.bytes[LOW] >= cpu.Y { // No page cross
            cpu_poll_interrupts(cpu, bus)
        }
    case 5:
        // Read from effective address, fix high byte if page crossed
        value := cpu_bus_read(bus, cpu.instruction_operands.whole)

        if cpu.instruction_operands.bytes[LOW] < cpu.Y { 
            cpu.instruction_operands.bytes[HIGH] += 1

            cpu_poll_interrupts(cpu, bus)
        } else {
            // If page boundary was not crossed, perform action and complete the instruction
            action(cpu, bus, value)
            cpu_instruction_done(cpu)
        }
    case 6:
        // Re-read from effective address, perform action, done
        value := cpu_bus_read(bus, cpu.instruction_operands.whole)
        action(cpu, bus, value)
        cpu_instruction_done(cpu)
    }
}

// Zero-page addressing, read-modify-write instructions
zpg_read_modify_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: ^u8)) {
    switch cycle {
    case 2:
        // Fetch address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from effective address
        cpu.instruction_temp_value = cpu_bus_read(bus, u16(cpu.instruction_operand))

        cpu.will_write = true
    case 4:
        // Dummy write the value back to effective address, perform action
        cpu_bus_write(bus, u16(cpu.instruction_operand), cpu.instruction_temp_value)
        action(cpu, bus, &cpu.instruction_temp_value)

        cpu_poll_interrupts(cpu, bus)
        cpu.will_write = true
    case 5:
        // Write the new value to effective address, done
        cpu_bus_write(bus, u16(cpu.instruction_operand), cpu.instruction_temp_value)
        cpu_instruction_done(cpu)
    }
}

// Zero-page indexed addressing, read-modify-write instructions
zpgi_read_modify_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, index_register: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: ^u8)) {
    switch cycle {
    case 2:
        // Fetch address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from address, add index to it
        cpu_bus_read(bus, u16(cpu.instruction_operand))
        cpu.instruction_operand += index_register
    case 4:    
        // Read from effective address
        cpu.instruction_temp_value = cpu_bus_read(bus, u16(cpu.instruction_operand))
        
        cpu.will_write = true
    case 5:
        // Dummy write the back to effective address, perform action
        cpu_bus_write(bus, u16(cpu.instruction_operand), cpu.instruction_temp_value)
        action(cpu, bus, &cpu.instruction_temp_value)

        cpu_poll_interrupts(cpu, bus)
        
        cpu.will_write = true
    case 6:
        // Write the new value to effective address, done
        cpu_bus_write(bus, u16(cpu.instruction_operand), cpu.instruction_temp_value)
        cpu_instruction_done(cpu)
    }
}

// Absolute addressing, read-modify-write instructions
abs_read_modify_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: ^u8)) {
    switch cycle {
    case 2:
        // Fetch low byte of address, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[LOW])
        cpu.PC += 1
    case 3:
        // Fetch high byte of address, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[HIGH])
        cpu.PC += 1
    case 4:    
        // Read from effective address
        cpu.instruction_temp_value = cpu_bus_read(bus, cpu.instruction_operands.whole)

        cpu.will_write = true
    case 5:
        // Dummy write the value back to effective address, perform action
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        action(cpu, bus, &cpu.instruction_temp_value)

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 6:
        // Write the new value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        cpu_instruction_done(cpu)
    }
}

// Absolute indexed addressing, read-modify-write instructions
absi_read_modify_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, index_register: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: ^u8)) {
    switch cycle {
    case 2:
        // Fetch low byte of address, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[LOW])
        cpu.PC += 1
    case 3:
        // Fetch high byte of address, add index to low address byte, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[HIGH])
        cpu.instruction_operands.bytes[LOW] += index_register
        cpu.PC += 1
    case 4:
        // Dummy read from effective address, fix the high byte of effective address if page boundary crossed
        cpu_bus_read(bus, cpu.instruction_operands.whole)
        
        if cpu.instruction_operands.bytes[LOW] < index_register { 
            cpu.instruction_operands.bytes[HIGH] += 1
        }
    case 5:
        // Re-read from effective address
        cpu.instruction_temp_value = cpu_bus_read(bus, cpu.instruction_operands.whole)

        cpu.will_write = true
    case 6:
        // Dummy write the value back to effective address, perform action
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        action(cpu, bus, &cpu.instruction_temp_value)

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 7:
        // Write the new value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        cpu_instruction_done(cpu)
    }
}

// Relative addressing, used by branch instructions
// Operand is an 8-bit signed offset for the PC
rel :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, should_branch: bool) {
    switch cycle {
    case 1:
        cpu_poll_interrupts(cpu, bus)
    case 2:
        // Fetch operand, increment PC
        // If branch is not taken - done
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1

        if !should_branch {
            cpu_instruction_done(cpu)
        }
    case 3:
        // Fetch opcode of next instruction
        // If branch does not cross page boundary - done
        cpu_bus_read(bus, cpu.PC)

        page_crossed: bool
        if cpu.instruction_operand >= 128 { // Negative offset in two's complement
            cpu.PCL -= ~cpu.instruction_operand + 1 // Negating two's complement number is (~x + 1) which is equal to (256 - x)
            page_crossed = cpu.PCL >= cpu.instruction_operand
        } else { // Positive offset
            cpu.PCL += cpu.instruction_operand
            page_crossed = cpu.PCL < cpu.instruction_operand
        }

        if !page_crossed {
            cpu_instruction_done(cpu)
        } else {
            cpu_poll_interrupts(cpu, bus)
        }
    case 4:
        // Fetch opcode of next instruction, fix PCH
        cpu_bus_read(bus, cpu.PC)

        if cpu.instruction_operand >= 128 {
            cpu.PCH -= 1
        } else {
            cpu.PCH += 1
        }

        cpu_instruction_done(cpu)
    }
}

// Implied addressing - operands are determined by the instruction itself
implied :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus)) {
    switch cycle {
    case 1:
        cpu_poll_interrupts(cpu, bus)
    case 2:
        // Dummy read next instruction byte, perform action, done
        cpu_bus_read(bus, cpu.PC)
        action(cpu, bus)
        cpu_instruction_done(cpu)
    }
}

// Zero-page addressing, write instructions
zpg_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, value: u8) {
    switch cycle {
    case 2:
        // Fetch address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 3:
        // Write value to effective address, done
        cpu_bus_write(bus, u16(cpu.instruction_operand), value)
        cpu_instruction_done(cpu)
    }
}

// Zero-page indexed addressing, write instructions
zpgi_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, index_register: u8, value: u8) {
    switch cycle {
    case 2:
        // Fetch address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from address, add index to it
        cpu_bus_read(bus, u16(cpu.instruction_operand))
        cpu.instruction_operand += index_register

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 4:    
        // Write value to effective address, done
        cpu_bus_write(bus, u16(cpu.instruction_operand), value)
        cpu_instruction_done(cpu)
    }
}

// Absolute addressing, write instructions
abs_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, value: u8) {
    switch cycle {
    case 2:
        // Fetch low byte of address, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[LOW])
        cpu.PC += 1
    case 3:
        // Fetch high byte of address, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[HIGH])
        cpu.PC += 1

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 4:
        // Write value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, value)
        cpu_instruction_done(cpu)
    }
}

// Absolute indexed addressing, write instructions
absi_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, index_register: u8, value: u8) {
    switch cycle {
    case 2:
        // Fetch low byte of address, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[LOW])
        cpu.PC += 1
    case 3:
        // Fetch high byte of address, add index to low address byte, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operands.bytes[HIGH])
        cpu.instruction_operands.bytes[LOW] += index_register
        cpu.PC += 1
    case 4:
        // Dummy read from effective address, fix the high byte of effective address if page boundary crossed
        cpu_bus_read(bus, cpu.instruction_operands.whole)
        
        if cpu.instruction_operands.bytes[LOW] < index_register { 
            cpu.instruction_operands.bytes[HIGH] += 1
        }

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 5:
        // Write value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, value)
        cpu_instruction_done(cpu)
    }
}

// Indexed indirect addressing, write instructions
indx_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, value: u8) {
    switch cycle {
    case 2:
        // Fetch pointer address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from pointer address (on zero page), add X to pointer address
        cpu_bus_read(bus, u16(cpu.instruction_operand))
        cpu.instruction_operand += cpu.X
    case 4:
        // Fetch effective address low byte
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, u16(cpu.instruction_operand))
    case 5:
        // Fetch effective address high byte
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, u16(cpu.instruction_operand+1))

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 6:
        // Write value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, value)
        cpu_instruction_done(cpu)
    }
}

// Indirect indexed addressing, write instructions
indy_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, value: u8) {
    switch cycle {
    case 2:
        // Fetch pointer address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Fetch effective address low byte
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, u16(cpu.instruction_operand))
    case 4:
        // Fetch effective address high byte, add Y to low address byte
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, u16(cpu.instruction_operand+1))
        cpu.instruction_operands.bytes[LOW] += cpu.Y
    case 5:
        // Read from effective address, fix high byte if page crossed
        cpu_bus_read(bus, cpu.instruction_operands.whole)
        
        if cpu.instruction_operands.bytes[LOW] < cpu.Y { 
            cpu.instruction_operands.bytes[HIGH] += 1
        }

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 6:
        // Write value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, value)
        cpu_instruction_done(cpu)
    }
}

// Indexed indirect addressing, read-modify-write instructions
indx_read_modify_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: ^u8)) {
    switch cycle {
    case 2:
        // Fetch pointer address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Read from pointer address (on zero page), add X to pointer address
        cpu_bus_read(bus, u16(cpu.instruction_operand))
        cpu.instruction_operand += cpu.X
    case 4:
        // Fetch effective address low byte
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, u16(cpu.instruction_operand))
    case 5:
        // Fetch effective address high byte
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, u16(cpu.instruction_operand+1))
    case 6:
        // Dummy read from effective address
        cpu.instruction_temp_value = cpu_bus_read(bus, cpu.instruction_operands.whole)

        cpu.will_write = true
    case 7:
        // Write the value back to effective address, perform action
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        action(cpu, bus, &cpu.instruction_temp_value)

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 8:
        // Write the new value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        cpu_instruction_done(cpu)
    }
}

// Indirect indexed addressing, read-modify-write instructions
indy_read_modify_write :: proc(cpu: ^CPU, bus: ^CPU_Bus, cycle: u8, action: proc(cpu: ^CPU, bus: ^CPU_Bus, value: ^u8)) {
    switch cycle {
    case 2:
        // Fetch pointer address, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        disassembler_set_operand(cpu.instruction_operand)
        cpu.PC += 1
    case 3:
        // Fetch effective address low byte
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, u16(cpu.instruction_operand))
    case 4:
        // Fetch effective address high byte, add Y to low address byte
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, u16(cpu.instruction_operand+1))
        cpu.instruction_operands.bytes[LOW] += cpu.Y
    case 5:
        // Read from effective address, fix high byte if page crossed
        cpu_bus_read(bus, cpu.instruction_operands.whole)
        
        if cpu.instruction_operands.bytes[LOW] < cpu.Y { 
            cpu.instruction_operands.bytes[HIGH] += 1
        }
    case 6:
        // Dummy read from effective address
        cpu.instruction_temp_value = cpu_bus_read(bus, cpu.instruction_operands.whole)

        cpu.will_write = true
    case 7:
        // Write the value back to effective address, perform action
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        action(cpu, bus, &cpu.instruction_temp_value)

        cpu_poll_interrupts(cpu, bus)

        cpu.will_write = true
    case 8:
        // Write the new value to effective address, done
        cpu_bus_write(bus, cpu.instruction_operands.whole, cpu.instruction_temp_value)
        cpu_instruction_done(cpu)
    }
}
