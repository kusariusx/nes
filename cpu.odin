package main

LOW  :: 0
HIGH :: 1

STACK_START :: 0x100

OAMDATA_ADDRESS :: 0x2004

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

NMI_Vector   :: 0xFFFA
Reset_Vector :: 0xFFFC
IRQ_Vector   :: 0xFFFE

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

	nmi_line_prev: bool, // For NMI edge detection

	// Flip-flops indicating that interrupt conditions have been met
	nmi_latch: bool,
	irq_latch: bool, 

	// NMI flip-flop is polled at discrete intervals (not continuously) - we handle NMI only when flip-flop is active during polling
	nmi_pending: bool,

	interrupt_vector: u16,

	// To control DMA cadence - DMAs can only start on read cycles. If they start on write cycles, they wait.
	is_read_cycle: bool,

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
	// Alternate between read and write cycles
	cpu.is_read_cycle = !cpu.is_read_cycle

	// Handle OAM DMA
	if bus.oam_dma_pending {
		// Dummy read during alignment cycle
		cpu_bus_read(bus, cpu.PC)

		// We should wait for either 2 or 1 cycles depending on whether this is a read or a write cycle
		if cpu.is_read_cycle {
			// Do nothing, let oam_dma_pending remain true and skip this cycle
		} else {
			// We only need to halt for 1 (current) cycle
			bus.oam_dma_pending = false
			bus.oam_dma_active = true // DMA will start on the next (read) cycle
		}

		return
	}

	if bus.oam_dma_active {
		if cpu.is_read_cycle { // Read from page
			bus.oam_dma_data = cpu_bus_read(bus, bus.oam_dma_address)
		} else { // Write to OAMDATA
			cpu_bus_write(bus, OAMDATA_ADDRESS, bus.oam_dma_data)

			if bus.oam_dma_address & 0x00FF == 0xFF { // We've just wrote the last byte (reached page end)
				bus.oam_dma_active = false
			} else { // We still have data remaining
				bus.oam_dma_address += 1
			}
		}

		return
	}

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
		if cpu.nmi_pending {
			trace("acknowledging NMI")

			// Acknowledge NMI
			cpu.nmi_latch = false
			cpu.nmi_pending = false 

			// Forget about IRQ
			cpu.irq_latch = false

			cpu.interrupt_vector = NMI_Vector
			cpu.instruction = &Interrupt_Handler
		} else if cpu.irq_latch && cpu.P.I == 0 {
			trace("acknowledging IRQ")

			cpu.irq_latch = false
			
			cpu.interrupt_vector = IRQ_Vector
			cpu.instruction = &Interrupt_Handler
		} else {
			// Decode instruction
			cpu.instruction = &Instructions[opcode]

			// Increment PC
			cpu.PC += 1
		}
	}

	trace(
		"(%d, %d) [PC:%04X P:%02X S:%02X A:%02X X:%02X Y:%02X] %d - %s", 
		bus.ppu.scanline, bus.ppu.scanline_cycle, 
		cpu.PC, u8(cpu.P), cpu.S, cpu.A, cpu.X, cpu.Y,
		cpu.instruction_cycle, cpu.instruction.mnemonic,
	)
	
	// Most instructions don't have special handling for the 1-st cycle (almost all instruction handlers
	// start their cycle switch from 2), but some instructions need to have additional logic at cycle 1 for 
	// interrupt polling.
	cpu.instruction.handler(cpu, bus, cpu.instruction_cycle)

	cpu.instruction_cycle += 1

	cpu_detect_nmi(cpu, bus)
}

cpu_detect_nmi :: proc(c: ^CPU, b: ^NES_CPU_Bus) {
	// NMI edge detection.
	// PPUSTATUS.V and PPUCTRL.V are AND'ed together and fed to CPU's NMI line.
	// Additionally, we need to take into account the fact that VBL could potentially 
	// be set or cleared *simultaneously* with currently running CPU cycle.
	nmi_line := (b.ppu.PPUSTATUS.V == 1 || b.ppu.will_set_vbl) && !b.ppu.will_clear_ppustatus && b.ppu.PPUCTRL.V == 1
	if !c.nmi_line_prev && nmi_line {
		trace("NMI edge detected")
		c.nmi_latch = true
	}

	c.nmi_line_prev = nmi_line
}

// Interrupts are usually polled on the second-to-last cycle of an instruction.
cpu_poll_interrupts :: proc(c: ^CPU, b: CPU_Bus) {
	b, ok := b.(^NES_CPU_Bus)
	if !ok {
		return // No-op for test bus
	}

	// Edge case: NMI latch is updated at the end of every CPU cycle, AFTER the instruction cycle has been executed.
	// Thus, if NMI occurs at the exact cycle when interrupts are polled by an instruction (on the second-to-last cycle),
	// the poll will not detect a pending NMI since the latch is updated after the polling...
	// This is a side effect of sequential nature of emulation - on real hardware NMI level detection and interrupt polling
	// are happening at the exact same time. As a result, pending NMI is detected at the same sycle the level detector activates.
	// To compensate for this side effect, perform NMI level detection before the polling.
	// 
	// TODO: introduce something like "will_poll_interrupts: bool" to communicate that polling must be postponed until after
	// the level detection? This will allow to avoid calling cpu_detect_nmi twice in the same cycle.
	if !c.nmi_latch {
		cpu_detect_nmi(c, b)
	}

	if c.nmi_latch {
		c.nmi_pending = true
	}

	// IRQs can have various sources - they are all connected to the same IRQ line, being effectively OR'ed.
	// IRQ line will stay low/active until all interrupt sources acknowledge their interrupt.
	c.irq_latch = 
		(b.apu.status >> 6) & 1 == 1 // APU Frame Counter

	trace("interrupt polling: NMI %t, IRQ %t", c.nmi_latch, c.irq_latch)
}

cpu_tick_test_bus :: proc(cpu: ^CPU, bus: ^Test_CPU_Bus) {
	// For test bus, no need to check for interrupts or handle halt state

	if cpu.instruction == nil {
		opcode := cpu_bus_read(bus, cpu.PC)
		cpu.instruction = &Instructions[opcode]
		
		cpu.instruction_cycle = 1
		cpu.PC += 1
	} 

	cpu.instruction.handler(cpu, bus, cpu.instruction_cycle)
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

cpu_reset :: proc(cpu: ^CPU, bus: CPU_Bus) {
	cpu.A, cpu.X, cpu.Y = 0, 0, 0
	cpu.S = 0xFD
	
	cpu.P.C, cpu.P.Z, cpu.P.D, cpu.P.V, cpu.P.N = 0, 0, 0, 0, 0
	cpu.P.I, cpu.P.unused = 1, 1

	cpu.PCL = cpu_bus_read(bus, Reset_Vector)
	cpu.PCH = cpu_bus_read(bus, Reset_Vector + 1)

	cpu.nmi_pending = false
	cpu.nmi_latch = false
	cpu.nmi_line_prev = false
	cpu.irq_latch = false

	cpu.is_read_cycle = false
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

interrupt_sequence_handler :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8, is_brk: bool) {
	switch cycle {
	case 2:
		// Dummy read from PC
		cpu_bus_read(bus, cpu.PC)

		if is_brk {
			cpu.PC += 1
		}
	case 3:
		// Push PCH on the stack
		stack_push(cpu, bus, cpu.PCH)
	case 4:
		// Push PCL on the stack
		stack_push(cpu, bus, cpu.PCL)
	case 5:
		// Push P on the stack (with B flag clear)
		p := cpu.P
		p.B = is_brk ? 1 : 0

		stack_push(cpu, bus, byte(p))

		// Detect interrupt hijacking
		if cpu.nmi_latch {
			trace("interrupt hijacked by the NMI")

			cpu.nmi_latch = false // Acknowledge the hijacking NMI
			cpu.irq_latch = false // IRQ forgotten when NMI wins

			cpu.interrupt_vector = NMI_Vector
		} else if is_brk {
			// BRK uses IRQ vector if not hijacked
			cpu.interrupt_vector = IRQ_Vector
		}
	case 6:
		// Fetch PCL, set I flag
		cpu.PCL = cpu_bus_read(bus, cpu.interrupt_vector)
		cpu.P.I = 1
	case 7:
		// Fetch PCH, set flags, done
		cpu.PCH = cpu_bus_read(bus, cpu.interrupt_vector + 1)
		cpu_instruction_done(cpu)
	}
}

// Ephemeral "instruction" implementing the interrupt handling sequence
Interrupt_Handler := Instruction{
	mnemonic = "nmi/irq",
	handler = proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
		interrupt_sequence_handler(cpu, bus, cycle, false)
	}
}
