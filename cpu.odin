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
	handler:  proc(cpu: ^CPU, bus: Bus, cycle: u8),
}

cpu_tick :: proc(cpu: ^CPU, bus: Bus) {
	if cpu.halt {
		// Ignore the tick if CPU is halted
		return
	}

	if cpu.instruction == nil { // We start executing a new instruction
		// This is the first cycle of any instruction
		// Start with 1 for better alignment with the documentation
		cpu.instruction_cycle = 1

		// Fetch opcode, decode instruction
		opcode := bus_read(bus, cpu.PC)
		cpu.instruction = &Instructions[opcode]

		// Increment PC
		cpu.PC += 1
	} else { // We are in a middle of executing an instruction
		cpu.instruction.handler(cpu, bus, cpu.instruction_cycle)
	}

	cpu.instruction_cycle += 1
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

not_implemented :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	opcode := bus_read(bus, cpu.PC)
	fmt.printf("opcode %x is not implemented\n", opcode)

	cpu_instruction_done(cpu) // Done after 1 cycle
}

stack_push :: proc(cpu: ^CPU, bus: Bus, value: byte) {
	// Stack is located on the second memory page 0x100-0x1FF
	bus_write(bus, STACK_START + u16(cpu.S), value)
	cpu.S -= 1
}

stack_pop :: proc(cpu: ^CPU, bus: Bus) -> byte {
	cpu.S += 1
	return bus_read(bus, STACK_START + u16(cpu.S))
}
