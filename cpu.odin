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

CPU_State :: struct {
	// Registers
	A:    byte, // Accumulator
	X, Y: byte, // Indexing registers
	S:    byte, // Stack pointer
	P:    CPU_Flags,

	// Program counter
	// With this construction, both PC and its individual bytes can be referred just by their names - cpu.PC, cpu.PCL, cpu.PCH
	using _: struct #raw_union {
        using _: struct { PCL, PCH: byte },
        PC: u16,
    },
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
	was_halted: bool,

	nmi_line_prev: bool, // For NMI edge detection

	// Flip-flops indicating that interrupt conditions have been met
	nmi_latch: bool,
	irq_latch: bool, 

	irq_external_line: bool,
	just_polled_interrupts: bool,

	// NMI flip-flop is polled at discrete intervals (not continuously) - we handle NMI only when flip-flop is active during polling
	nmi_pending: bool,

	interrupt_vector: u16,

	// To control DMA cadence - DMAs can only start on read cycles. If they start on write cycles, they wait.
	// TODO: with the new `clock` variable, is this even needed?
	is_read_cycle: bool,

	clock: u64,

	// Indicates that the CPU will write to the bus on the next cycle - used to determine when to start DMC DMA.
	// DMC DMA cannot halt the CPU on the cycle when it writes to the bus. In such case, DMC DMA waits and tries to 
	// halt the CPU on the next cycle.
	will_write: bool,

	using state: CPU_State,
}

Instruction :: struct {
	mnemonic: string, // For disassembly/debug
	format:   string, // For instructions with operands
	handler:  proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8),
}

cpu_tick_nes_bus :: proc(cpu: ^CPU, bus: ^NES_CPU_Bus) {
	// Alternate between read and write cycles
	cpu.is_read_cycle = !cpu.is_read_cycle

	// TODO: move all DMA related stuff into a separate module
	dmc_dma_dummy_read, oam_dma_dummy_read: bool
	dmc_dma_action, oam_dma_action: bool

	// Handle DMC DMA
	if bus.apu.dmc_dma_cycle > 0 && !bus.apu.dmc_dma_halt_pending {
		if bus.apu.status.dmc == 0 { // DMC was disabled during ongoing DMA - abort the DMA
			bus.apu.dmc_dma_cycle = 0
			dmc_dma_dummy_read = true // Still do this cycle's read
		} else {
			bus.apu.dmc_dma_cycle -= 1

			if bus.apu.dmc_dma_cycle == 0 {
				dmc_dma_action = true
			} else {
				dmc_dma_dummy_read = true
			}
		}
	}

	if bus.apu.dmc_dma_pending {
		bus.apu.dmc_dma_pending = false
		bus.apu.dmc_dma_halt_pending = true
	}

	if bus.apu.dmc_dma_halt_pending {
		if !cpu.will_write {
			// DMA will halt the CPU for 3 or 4 cycles, depending on whether the start of the DMA lands on read or write cycle.
			bus.apu.dmc_dma_cycle = cpu.is_read_cycle ? 2 : 3

			bus.apu.dmc_dma_halt_pending = false
			dmc_dma_dummy_read = true

			// TODO: again, this is a hack because I don't properly emulate the address bus
			if cpu.instruction == nil { // If we're at instruction start, the CPU was about to fetch opcode from PC
				bus.apu.dmc_dma_dummy_read_address = cpu.PC
			} else { // Mid-instruction, use the last known operand address
				bus.apu.dmc_dma_dummy_read_address = cpu.instruction_operands.whole
			}
		} else {
			// When DMA lands on a cycle when CPU writes to bus, DMA is postponed and CPU is not halted. DMA will attempt
			// to halt the CPU on the next cycle, regardless of whether it is read or write cycle (however, the halt duration
			// will change depending on what type of cycle the start of the DMA lands on).
		}

		if bus.apu.dmc_dma_aborted {
			// Abort DMA
			bus.apu.dmc_dma_cycle = 0
			bus.apu.dmc_dma_halt_pending = false

			// If aborted DMA was postponed due to landing on write cycle, DMA should not halt at all
			if cpu.will_write {
				dmc_dma_dummy_read = false
			}
		}
	}

	// Handle OAM DMA
	if bus.oam_dma_active {
		if bus.oam_dma_perform_alignment_cycle {
			bus.oam_dma_perform_alignment_cycle = false
			oam_dma_dummy_read = true
		} else {
			oam_dma_action = true
		}
	}

	// OAM DMA cannot land on a write cycle as well
	if bus.oam_dma_pending && !cpu.will_write {
		oam_dma_dummy_read = true

		// We should wait for either 2 or 1 cycles depending on whether this is a read or a write cycle
		if cpu.is_read_cycle {
			// Do nothing, let oam_dma_pending remain true and skip this cycle
		} else {
			// We only need to halt for 1 (current) cycle
			bus.oam_dma_pending = false
			bus.oam_dma_active = true // DMA will start on the next (read) cycle
		}
	}

	if dmc_dma_dummy_read || dmc_dma_action || oam_dma_dummy_read || oam_dma_action { // We have some pending DMA work
		trace(
			.CPU, 
			"DMA work pending: dmc_dma_dummy_read = %t, dmc_dma_action = %t, oam_dma_dummy_read = %t, oam_dma_action = %t",
			dmc_dma_dummy_read, dmc_dma_action, oam_dma_dummy_read, oam_dma_action,
		)

		/* 
		Since there are 4 flags, there are 16 possible states, but some of them as impossible by design. For example,
		it is not possible for both OAM DMA action and OAM DMA dummy read to be pending at the same time. After excluding 
		such impossible cases, we end up with 8 possible scenarios:
		
		dmc_dma_dummy_read	dmc_dma_action	oam_dma_dummy_read	oam_dma_action	What to do
		0					0				0					1				Perform OAM action
		0					0				1					0				Perform OAM dummy read
		0					1				0					0				Perform DMC action
		0					1				0					1				Perform DMC action and request alignment cycle for OAM
		0					1				1					0				Not possible?
		1					0				0					0				Perform DMC dummy read
		1					0				0					1				Perform OAM action and DMC dummy read (don't actually read the bus but advance counters)
		1					0				1					0				Perform DMC dummy read and OAM dummy read (which one exactly?)
		*/

		if dmc_dma_action {
			// Perform DMC DMA action
			bus.apu.dmc_sample_buffer = cpu_bus_read(bus, bus.apu.dmc_current_address, is_dma = true)
			bus.apu.dmc_sample_buffer_is_empty = false

			trace(.CPU, "DMA'd $%02X into DMC sample buffer", bus.apu.dmc_sample_buffer)

			if bus.apu.dmc_current_address == 0xFFFF {
				bus.apu.dmc_current_address = 0x8000
			} else {
				bus.apu.dmc_current_address += 1
			}

			bus.apu.dmc_bytes_remaining -= 1
			if bus.apu.dmc_bytes_remaining == 0  {
				if !bus.apu.dmc_loop { // No loop, assert IRQ if enabled
					if bus.apu.dmc_irq_enabled {
						trace(.CPU, "requesting DMC IRQ")
						bus.apu.status.dmc_interrupt = 1
					}

					bus.apu.dmc_dma_sample_just_finished = true
				} else { // Loop
					bus.apu.dmc_current_address = bus.apu.dmc_sample_address
					bus.apu.dmc_bytes_remaining = bus.apu.dmc_sample_length
				}
			}

			if oam_dma_action {
				// Request dummy read cycle for OAM DMA
				bus.oam_dma_perform_alignment_cycle = true
			}
		} else if oam_dma_action {
			// Perform OAM DMA action
			if cpu.is_read_cycle { // Read from page
				bus.oam_dma_data = cpu_bus_read(bus, bus.oam_dma_address, is_dma = true)
			} else { // Write to OAMDATA
				cpu_bus_write(bus, OAMDATA_ADDRESS, bus.oam_dma_data)
	
				if bus.oam_dma_address & 0x00FF == 0xFF { // We've just wrote the last byte (reached page end)
					bus.oam_dma_active = false
				} else { // We still have data remaining
					bus.oam_dma_address += 1
				}
			}
		} else { 
			if dmc_dma_dummy_read && oam_dma_dummy_read {
				// TODO: we want both dummy reads, decide which one to perform
			}

			if dmc_dma_dummy_read {
				// Perform DMC DMA dummy read
				cpu_bus_read(bus, bus.apu.dmc_dma_dummy_read_address)
			} else if oam_dma_dummy_read {
				// Perform OAM DMA dummy read
				cpu_bus_read(bus, cpu.PC)
			}
		}

		cpu.was_halted = true

		return
	}

	if cpu.halt {
		// Ignore the tick if CPU is halted
		return
	}

	if cpu.instruction == nil { // We start executing a new instruction
		cpu.instruction_operands.whole = 0
		
		// This is the first cycle of any instruction
		// Start with 1 for better alignment with the documentation
		cpu.instruction_cycle = 1

		// Fetch opcode
		// Even when handling interrupts, this bus read is still the first cycle of the interrupt sequence
		opcode := cpu_bus_read(bus, cpu.PC)

		// Check for interrupts
		// Note: when handling interrupts, writes to PC are suppressed, hence not incrementing it
		if cpu.nmi_pending {
			trace(.CPU, "acknowledging NMI")

			// Acknowledge NMI
			cpu.nmi_latch = false
			cpu.nmi_pending = false 

			// Forget about IRQ
			cpu.irq_latch = false

			cpu.interrupt_vector = NMI_Vector
			cpu.instruction = &Interrupt_Handler
		} else if cpu.irq_latch {
			trace(.CPU, "acknowledging IRQ")

			cpu.irq_latch = false
			
			cpu.interrupt_vector = IRQ_Vector
			cpu.instruction = &Interrupt_Handler
		} else {
			// Decode instruction
			cpu.instruction = &Instructions[opcode]
			disassembler_start_instruction(opcode, cpu.instruction, cpu.state)

			// Increment PC
			cpu.PC += 1
		}
	}

	trace(
		.CPU,
		"(%d, %d) [PC:%04X P:%02X S:%02X A:%02X X:%02X Y:%02X] %d - %s", 
		bus.ppu.scanline, bus.ppu.scanline_cycle, 
		cpu.PC, u8(cpu.P), cpu.S, cpu.A, cpu.X, cpu.Y,
		cpu.instruction_cycle, cpu.instruction.mnemonic,
	)

	cpu.will_write = false
	
	// Most instructions don't have special handling for the 1-st cycle (almost all instruction handlers
	// start their cycle switch from 2), but some instructions need to have additional logic at cycle 1 for 
	// interrupt polling.
	cpu.instruction.handler(cpu, bus, cpu.instruction_cycle)

	cpu.instruction_cycle += 1
	cpu.clock += 1
	cpu.was_halted = false

	cpu_detect_nmi(cpu, bus)
}

cpu_detect_nmi :: proc(c: ^CPU, b: ^NES_CPU_Bus) {
	// NMI edge detection.
	// PPUSTATUS.V and PPUCTRL.V are AND'ed together and fed to CPU's NMI line.
	// Additionally, we need to take into account the fact that VBL could potentially 
	// be set or cleared *simultaneously* with currently running CPU cycle.
	nmi_line := (b.ppu.PPUSTATUS.V == 1 || b.ppu.will_set_vbl) && !b.ppu.will_clear_ppustatus && b.ppu.PPUCTRL.V == 1
	if !c.nmi_line_prev && nmi_line {
		trace(.CPU, "NMI edge detected")
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
		b.apu.status.frame_interrupt == 1 || // APU Frame Counter
		b.apu.status.dmc_interrupt == 1 || // APU DMC
		c.irq_external_line // Any external IRQ signal like MMC3 mapper

	c.irq_latch &&= c.P.I == 0

	c.just_polled_interrupts = true

	trace(.CPU, "(%d, %d) interrupt polling: NMI %t, IRQ %t", b.ppu.scanline, b.ppu.scanline_cycle, c.nmi_latch, c.irq_latch)
}

// This is used by external systems like mappers to request an IRQ
cpu_trigger_external_irq :: proc(c: ^CPU) {
	if c.just_polled_interrupts && c.P.I == 0 {
		trace(.CPU, "external IRQ triggered just as interrupts were polled - allowing IRQ")
		c.irq_latch = true
	}

	c.irq_external_line = true
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
	disassembler_end_instruction()
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

		cpu.will_write = true // Stack pushes write to the bus
	case 3:
		// Push PCH on the stack
		stack_push(cpu, bus, cpu.PCH)

		cpu.will_write = true
	case 4:
		// Push PCL on the stack
		stack_push(cpu, bus, cpu.PCL)

		cpu.will_write = true
	case 5:
		// Push P on the stack (with B flag clear)
		p := cpu.P
		p.B = is_brk ? 1 : 0

		stack_push(cpu, bus, byte(p))

		// Detect interrupt hijacking
		if cpu.nmi_latch {
			trace(.CPU, "interrupt hijacked by the NMI")

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
