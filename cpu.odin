package main

import "core:fmt"

LOW  :: 0
HIGH :: 1

STACK_START :: 0x100

// Flags layout in the register:
// Bit:   76543210
// Value: NV1BDIZC
//          ^-- always 1
CPU_Flags :: bit_field byte {
	C:      byte | 1, // Carry
    Z:      byte | 1, // Zero
	I:      byte | 1, // Interrupt disable
	D:      byte | 1, // Decimal
	B:      byte | 1, // B flag
	unused: byte | 1, // Unused bit, always set to 1
	V:      byte | 1, // Overflow
	N:      byte | 1, // Negative
}

CPU :: struct {
	instruction:            ^Instruction, // Current running instruction
	instruction_cycle:      u8, // Current cycle within an instruction

    // Buffers for keeping state during instruction execution between individual cycles
    instruction_temp_value: byte,
	instruction_operand:    byte, 
	instruction_operands:   struct #raw_union {
        bytes: [2]byte,
        whole: u16,
    },

	halt: bool,

	// Registers
	A:                   byte, // Accumulator
	X, Y:                byte, // Indexing registers
	S:                   byte, // Stack pointer
	P:                   CPU_Flags,

	// Program counter
	// With this construction, both PC and its individual bytes can be referred just by their names - cpu.PC, cpu.PCL, cpu.PCH
	using _: struct #raw_union {
        using _: struct { PCL, PCH: byte },
        PC: u16,
    },
}

Instruction :: struct {
	mnemonic: string, // For disassembly/debug
	handler:  proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8),
}

cpu_tick_nes_bus :: proc(cpu: ^CPU, bus: ^NES_CPU_Bus) {
	if cpu.halt {
		// Ignore the tick if CPU is halted
		return
	}

	if cpu.instruction == nil { // We start executing a new instruction
		// This is the first cycle of any instruction
		// Start with 1 for better alignment with the documentation
		cpu.instruction_cycle = 1

		// Fetch opcode
		// Even when handling interrupts, this bus read is still the first cycle of the interrupt sequence
		opcode := cpu_bus_read(bus, cpu.PC)

		// Check for interrupts
		// Note: when handling interrupts, writes to PC are suppressed, hence not incrementing it
		if bus.nmi_pending {
			bus.nmi_pending = false
			cpu.instruction = &NMI_Handler
		} else if bus.irq_pending && cpu.P.I == 0 {
			bus.irq_pending = false
			cpu.instruction = &IRQ_Handler
		} else {
			// Decode instruction
			cpu.instruction = &Instructions[opcode]

			// Increment PC
			cpu.PC += 1
		}
	} else { // We are in a middle of executing an instruction
		cpu.instruction.handler(cpu, bus, cpu.instruction_cycle)
	}

	cpu.instruction_cycle += 1
}

cpu_tick_test_bus :: proc(cpu: ^CPU, bus: ^Test_CPU_Bus) {
	// For test bus, no need to check for interrupts or handle halt state

	if cpu.instruction == nil {
		opcode := cpu_bus_read(bus, cpu.PC)
		cpu.instruction = &Instructions[opcode]
		
		cpu.instruction_cycle = 1
		cpu.PC += 1
	} else { 
		cpu.instruction.handler(cpu, bus, cpu.instruction_cycle)
	}

	cpu.instruction_cycle += 1
}

cpu_tick :: proc {
	cpu_tick_nes_bus,
	cpu_tick_test_bus,
}

// Each instruction will individually command when its execution is done.
// This is done to allow instructions to control for how many cycles they run.
cpu_instruction_done :: proc(cpu: ^CPU) {
	cpu.instruction = nil
}

cpu_reset :: proc(cpu: ^CPU) {
	cpu.A, cpu.X, cpu.Y = 0, 0, 0
	cpu.S = 0xFD
	
	cpu.P.C, cpu.P.Z, cpu.P.D, cpu.P.V, cpu.P.N = 0, 0, 0, 0, 0
	cpu.P.I, cpu.P.unused = 1, 1
}

stack_push :: proc(cpu: ^CPU, bus: CPU_Bus, value: byte) {
	// Stack is located on the second memory page 0x100-0x1FF
	cpu_bus_write(bus, STACK_START + u16(cpu.S), value)
	cpu.S -= 1
}

stack_pop :: proc(cpu: ^CPU, bus: CPU_Bus) -> byte {
	cpu.S += 1
	return cpu_bus_read(bus, STACK_START + u16(cpu.S))
}

interrupt_sequence_handler :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8, vector_low: u16, vector_high: u16) {
	switch cycle {
	case 2:
		// Dummy read from PC
		cpu_bus_read(bus, cpu.PC)
	case 3:
		// Push PCH on the stack
		stack_push(cpu, bus, cpu.PCH)
	case 4:
		// Push PCL on the stack
		stack_push(cpu, bus, cpu.PCL)
	case 5:
		// Push P on the stack (with B flag clear)
		p := cpu.P
		p.B = 0

		stack_push(cpu, bus, byte(p))

		// TODO: implement interrupt hijacking on this cycle. For BRK as well.
	case 6:
		// Fetch PCL, set I flag
		cpu.PCL = cpu_bus_read(bus, vector_low)
		cpu.P.I = 1
	case 7:
		// Fetch PCH, set flags, done
		cpu.PCH = cpu_bus_read(bus, vector_high)
		cpu_instruction_done(cpu)
	}
}

// Ephemeral "instructions" implementing the interrupt handling sequence
NMI_Handler := Instruction{
	handler = proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
		interrupt_sequence_handler(cpu, bus, cycle, 0xFFFA, 0xFFFB)
	}
}

IRQ_Handler := Instruction{
	handler = proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
		interrupt_sequence_handler(cpu, bus, cycle, 0xFFFE, 0xFFFF)
	}
}
