package main

adc :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Add with Carry
    result_full := u16(cpu.A) + u16(value) + u16(cpu.P.C)
    result := byte(result_full & 0xFF)

    cpu.P.C = byte(result_full >> 8)
    cpu.P.Z = result == 0 ? 1 : 0
    cpu.P.V = ((result ~ cpu.A) & (result ~ value)) >> 7 // Signed overflow/underflow (result sign is different from both A and value)
    cpu.P.N = result >> 7

    cpu.A = result
}

adc_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	imm(cpu, bus, cycle, adc)
}

adc_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	zpg_read(cpu, bus, cycle, adc)
}

adc_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	zpgi_read(cpu, bus, cycle, cpu.X, adc)
}

adc_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	abs_read(cpu, bus, cycle, adc)
}

adc_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.X, adc)
}

adc_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.Y, adc)
}

adc_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	indx_read(cpu, bus, cycle, adc)
}

adc_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	indy_read(cpu, bus, cycle, adc)
}

and :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) {
    result := cpu.A & value

    cpu.P.Z = result == 0 ? 1 : 0
    cpu.P.N = result >> 7

    cpu.A = result
}

and_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	imm(cpu, bus, cycle, and)
}

and_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	zpg_read(cpu, bus, cycle, and)
}

and_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	zpgi_read(cpu, bus, cycle, cpu.X, and)
}

and_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	abs_read(cpu, bus, cycle, and)
}

and_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.X, and)
}

and_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.Y, and)
}

and_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	indx_read(cpu, bus, cycle, and)
}

and_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
	indy_read(cpu, bus, cycle, and)
}

asl :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // Arithmetic Shift Left
    cpu.P.C = value^ >> 7
    value^ <<= 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

asl_a :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { asl(cpu, bus, &cpu.A) })
}
  
asl_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    zpg_read_modify_write(cpu, bus, cycle, asl)
}

asl_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, asl)
}

asl_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    abs_read_modify_write(cpu, bus, cycle, asl)
}

asl_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    absi_read_modify_write(cpu, bus, cycle, cpu.X, asl)
}

bcc :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Carry Clear
    rel(cpu, bus, cycle, cpu.P.C == 0)
}

bcs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Carry Set
    rel(cpu, bus, cycle, cpu.P.C == 1)
}

beq :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Equal
    rel(cpu, bus, cycle, cpu.P.Z == 1)
}

bit :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Bit test
    result := cpu.A & value

    cpu.P.Z = result == 0 ? 1 : 0
    cpu.P.V = (value >> 6) & 1
    cpu.P.N = value >> 7 
}

bit_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, bit)
}

bit_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, bit)
}

bmi :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Minus
    rel(cpu, bus, cycle, cpu.P.N == 1)
}

bne :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Not Equal
    rel(cpu, bus, cycle, cpu.P.Z == 0)
}

bpl :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Plus
    rel(cpu, bus, cycle, cpu.P.N == 0)
}

brk :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Break
    interrupt_sequence_handler(cpu, bus, cycle, true)
}

bvc :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Overflow Clear
    rel(cpu, bus, cycle, cpu.P.V == 0)
}

bvs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Branch if Overflow Set
    rel(cpu, bus, cycle, cpu.P.V == 1)
}

clc :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Clear Carry
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.C = 0 })
}

cld :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Clear Decimal
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.D = 0 })
}

cli :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Clear Interrupt Disable
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.I = 0 })
}

clv :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Clear Overflow
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.V = 0 })
}

compare :: proc(cpu: ^CPU, a, b: u8) {
    result := a - b

    cpu.P.C = a >= b ? 1 : 0
    cpu.P.Z = a == b ? 1 : 0
    cpu.P.N = result >> 7 
}

cmp :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Compare A
    compare(cpu, cpu.A, value)
}

cmp_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, cmp)
}

cmp_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, cmp)
}

cmp_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, cmp)
}

cmp_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, cmp)
}

cmp_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, cmp)
}

cmp_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, cmp)
}

cmp_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, cmp)
}

cmp_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, cmp)
}

cpx :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Compare X
    compare(cpu, cpu.X, value)
}

cpx_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, cpx)
}

cpx_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, cpx)
}

cpx_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, cpx)
}

cpy :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Compare Y
    compare(cpu, cpu.Y, value)
}

cpy_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, cpy)
}

cpy_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, cpy)
}

cpy_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, cpy)
}

dec :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // Decrement Memory
    value^ -= 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

dec_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, dec)
}

dec_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, dec)
}

dec_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, dec)
}

dec_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, dec)
}

dex :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Decrement X
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { dec(cpu, bus, &cpu.X) })
}

dey :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Decrement Y
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { dec(cpu, bus, &cpu.Y) })
}

eor :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Bitwise Exclusive OR
    cpu.A ~= value

    cpu.P.Z = cpu.A == 0 ? 1 : 0
    cpu.P.N = cpu.A >> 7
}

eor_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, eor)
}

eor_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, eor)
}

eor_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, eor)
}

eor_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, eor)
}

eor_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, eor)
}

eor_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, eor)
}

eor_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, eor)
}

eor_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, eor)
}

inc :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // Increment Memory
    value^ += 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

inc_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, inc)
}

inc_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, inc)
}

inc_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, inc)
}

inc_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, inc)
}

inx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Increment X
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { inc(cpu, bus, &cpu.X) })
}

iny :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Increment Y
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { inc(cpu, bus, &cpu.Y) })
}

jmp_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Jump Absolute
    switch cycle {
    case 2:
        // Fetch low address byte, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        cpu.PC += 1

        cpu_poll_interrupts(cpu, bus)
    case 3:
        // Copy low address byte to PCL, fetch high address byte to PCH, done
        cpu.PCH = cpu_bus_read(bus, cpu.PC)
        cpu.PCL = cpu.instruction_operand
        cpu_instruction_done(cpu)
    }
}

// Jump Indirect (operand is a 16-bit address of a low byte of the effective address)
jmp_ind :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2:
        // Fetch pointer address low, increment PC
        cpu.instruction_operands.bytes[LOW] = cpu_bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 3:
        // Fetch pointer address high, increment PC
        cpu.instruction_operands.bytes[HIGH] = cpu_bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 4:
        // Fetch low address to latch
        cpu.instruction_temp_value = cpu_bus_read(bus, cpu.instruction_operands.whole)

        cpu_poll_interrupts(cpu, bus)
    case 5:
        // Fetch PCH, copy latch to PCL, done
        cpu.instruction_operands.bytes[LOW] += 1 // Deliberately ignore page crossing and just increment the low byte (hardware bug)
        cpu.PCH = cpu_bus_read(bus, cpu.instruction_operands.whole)

        cpu.PCL = cpu.instruction_temp_value

        cpu_instruction_done(cpu)
    }
}

jsr :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Jump to Subroutine
    switch cycle {
    case 2:
        // Fetch low address byte, increment PC
        cpu.instruction_operand = cpu_bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 3:
        // Internal operation - dummy read the stack
        cpu_bus_read(bus, STACK_START + u16(cpu.S))
    case 4:
        // Push PCH on stack
        stack_push(cpu, bus, cpu.PCH)
    case 5:
        // Push PCL on stack
        stack_push(cpu, bus, cpu.PCL)

        cpu_poll_interrupts(cpu, bus)
    case 6:
        // Copy low address byte to PCL, fetch high address byte to PCH, done
        cpu.PCH = cpu_bus_read(bus, cpu.PC)
        cpu.PCL = cpu.instruction_operand

        cpu_instruction_done(cpu)
    }
}

load :: proc(cpu: ^CPU, target: ^u8, value: u8) {
    target^ = value

    cpu.P.Z = target^ == 0 ? 1 : 0
    cpu.P.N = target^ >> 7
}

lda :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Load A
    load(cpu, &cpu.A, value)
}

lda_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, lda)
}

lda_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, lda)
}

lda_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, lda)
}

lda_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, lda)
}

lda_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, lda)
}

lda_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, lda)
}

lda_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, lda)
}

lda_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, lda)
}

ldx :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Load X
    load(cpu, &cpu.X, value)
}

ldx_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, ldx)
}

ldx_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, ldx)
}

ldx_zpgy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.Y, ldx)
}

ldx_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, ldx)
}

ldx_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, ldx)
}

ldy :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Load Y
    load(cpu, &cpu.Y, value)
}

ldy_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, ldy)
}

ldy_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, ldy)
}

ldy_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, ldy)
}

ldy_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, ldy)
}

ldy_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, ldy)
}

lsr :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // Logical Shift Right
    cpu.P.C = value^ & 1
    value^ >>= 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = 0
}

lsr_a :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { lsr(cpu, bus, &cpu.A) })
}

lsr_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, lsr)
}

lsr_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, lsr)
}

lsr_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, lsr)
}

lsr_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, lsr)
}

nop :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // No Operation
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { })
}

ora :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Bitwise OR
    cpu.A |= value

    cpu.P.Z = cpu.A == 0 ? 1 : 0
    cpu.P.N = cpu.A >> 7
}

ora_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, ora)
}

ora_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, ora)
}

ora_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, ora)
}

ora_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, ora)
}

ora_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, ora)
}

ora_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, ora)
}

ora_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, ora)
}

ora_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, ora)
}

pha :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Push A
    switch cycle {
    case 2:
        // Dummy read next instruction byte
        cpu_bus_read(bus, cpu.PC)

        cpu_poll_interrupts(cpu, bus)
    case 3:
        // Push A on stack, done
        stack_push(cpu, bus, cpu.A)
        cpu_instruction_done(cpu)
    }
}

php :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Push P
    switch cycle {
    case 2:
        // Dummy read next instruction byte
        cpu_bus_read(bus, cpu.PC)

        cpu_poll_interrupts(cpu, bus)
    case 3:
        // Push P on stack with B flag set, done
        p := cpu.P
        p.B = 1

        stack_push(cpu, bus, u8(p))
        cpu_instruction_done(cpu)
    }
}

pla :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Pull A
    switch cycle {
    case 2:
        // Dummy read next instruction byte
        cpu_bus_read(bus, cpu.PC)
    case 3:
        // Dummy read on the stack
        cpu_bus_read(bus, STACK_START + u16(cpu.S))

        cpu_poll_interrupts(cpu, bus)
    case 4:
        // Pull A from stack, set flags, done
        cpu.A = stack_pop(cpu, bus)
        
        cpu.P.Z = cpu.A == 0 ? 1 : 0
        cpu.P.N = cpu.A >> 7

        cpu_instruction_done(cpu)
    }
}

plp :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Pull P
    switch cycle {
    case 2:
        // Dummy read next instruction byte
        cpu_bus_read(bus, cpu.PC)
    case 3:
        // Dummy read on the stack
        cpu_bus_read(bus, STACK_START + u16(cpu.S))

        cpu_poll_interrupts(cpu, bus)
    case 4:
        // Pull P from stack ignoring/preserving bits 4 and 5, done
        p := (u8(cpu.P) & 0b00110000) | (stack_pop(cpu, bus) & 0b11001111)
        cpu.P = CPU_Flags(p)

        cpu_instruction_done(cpu)
    }
}

rol :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // Rotate Left (through Carry)
    c := cpu.P.C
    cpu.P.C = value^ >> 7
    value^ = (value^ << 1) | c

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

rol_a :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { rol(cpu, bus, &cpu.A) })
}

rol_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, rol)
}

rol_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, rol)
}

rol_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, rol)
}

rol_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, rol)
}

ror :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // Rotate Right (through Carry)
    c := cpu.P.C
    cpu.P.C = value^ & 1
    value^ = (value^ >> 1) | (c << 7)

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = c
}

ror_a :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { ror(cpu, bus, &cpu.A) })
}

ror_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, ror)
}

ror_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, ror)
}

ror_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, ror)
}

ror_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, ror)
}

rti :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Return from Interrupt
    switch cycle {
    case 2:
        // Dummy read next instruction byte
        cpu_bus_read(bus, cpu.PC)
    case 3:
        // Dummy read on the stack
        cpu_bus_read(bus, STACK_START + u16(cpu.S))
    case 4:
        // Pull P from stack ignoring/preserving bits 4 and 5
        p := (u8(cpu.P) & 0b00110000) | (stack_pop(cpu, bus) & 0b11001111)
        cpu.P = CPU_Flags(p)
    case 5:
        // Pull PCL from stack
        cpu.PCL = stack_pop(cpu, bus)

        cpu_poll_interrupts(cpu, bus)
    case 6:
        // Pull PCH from stack, done
        cpu.PCH = stack_pop(cpu, bus)

        cpu_instruction_done(cpu)
    }
}

rts :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Return from Subroutine
    switch cycle {
    case 2:
        // Dummy read next instruction byte
        cpu_bus_read(bus, cpu.PC)
    case 3:
        // Dummy read on the stack
        cpu_bus_read(bus, STACK_START + u16(cpu.S))
    case 4:
        // Pull PCL from stack
        cpu.PCL = stack_pop(cpu, bus)
    case 5:
        // Pull PCH from stack
        cpu.PCH = stack_pop(cpu, bus)

        cpu_poll_interrupts(cpu, bus)
    case 6:
        // Dummy read at the PC, increment PC, done
        cpu_bus_read(bus, cpu.PC)
        cpu.PC += 1
        cpu_instruction_done(cpu)
    }
}

sbc :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // Subtract with Carry
    // A = A - value - ~C, or equivalently: A = A + ~value + C 
    // Even on the hardware level, SBC is implemented using ADC, just with inverted value
    adc(cpu, bus, ~value)
}

sbc_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, sbc)
}

sbc_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, sbc)
}

sbc_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, sbc)
}

sbc_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, sbc)
}

sbc_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, sbc)
}

sbc_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, sbc)
}

sbc_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, sbc)
}

sbc_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, sbc)
}

sec :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Set Carry
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.C = 1 })
}

sed :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Set Decimal
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.D = 1 })
}

sei :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Set Interrupt Disable
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.P.I = 1 })
}

sta_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Store A
    zpg_write(cpu, bus, cycle, cpu.A)
}

sta_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_write(cpu, bus, cycle, cpu.X, cpu.A)
}

sta_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_write(cpu, bus, cycle, cpu.A)
}

sta_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_write(cpu, bus, cycle, cpu.X, cpu.A)
}

sta_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_write(cpu, bus, cycle, cpu.Y, cpu.A)
}

sta_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_write(cpu, bus, cycle, cpu.A)
}

sta_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_write(cpu, bus, cycle, cpu.A)
}

stx_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Store X
    zpg_write(cpu, bus, cycle, cpu.X)
}

stx_zpgy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    zpgi_write(cpu, bus, cycle, cpu.Y, cpu.X)
}

stx_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_write(cpu, bus, cycle, cpu.X)
}

sty_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Store Y
    zpg_write(cpu, bus, cycle, cpu.Y)
}

sty_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { 
    zpgi_write(cpu, bus, cycle, cpu.X, cpu.Y)
}

sty_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_write(cpu, bus, cycle, cpu.Y)
}

transfer :: proc(cpu: ^CPU, target: ^u8, source: u8) {
    target^ = source

    cpu.P.Z = source == 0 ? 1 : 0
    cpu.P.N = source >> 7
}

tax :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Transfer A to X
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { transfer(cpu, &cpu.X, cpu.A) })
}

tay :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Transfer A to Y
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { transfer(cpu, &cpu.Y, cpu.A) })
}

tsx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Transfer S to X
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { transfer(cpu, &cpu.X, cpu.S) })
}

txa :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Transfer X to A
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { transfer(cpu, &cpu.A, cpu.X) })
}

txs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Transfer X to S
    // In contrast to other transfer instructions, this one does not set flags
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { cpu.S = cpu.X })
}

tya :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // Transfer Y to A
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { transfer(cpu, &cpu.A, cpu.Y) })
}

// Illegal opcodes

nop_implied :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus) { })
}

nop_imm :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { })
}

nop_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { })
}

nop_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { })
}

nop_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { })
}

nop_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { })
}

jam :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2:
        // These bus reads are added in order to pass the CPU tests, I assume those are done by real hardware

        // Read the next instruction byte
        cpu_bus_read(bus, cpu.PC)

        cpu_poll_interrupts(cpu, bus)
    case 3:
        // Re-read the next instruction byte
        cpu_bus_read(bus, cpu.PC)

        // Decrement the PC - this instruction must leave the CPU state unchanged, including the PC
        cpu.PC -= 1

        // Halt the CPU, done
        // TODO: set data bus to 0xFF
        cpu.halt = true 
        cpu_instruction_done(cpu)
    }
}

alr :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // AND + LSR
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { 
        and(cpu, bus, value)
        lsr(cpu, bus, &cpu.A)
    })
}

anc :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // AND + set result bit 7 to C
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { 
        and(cpu, bus, value)
        cpu.P.C = cpu.A >> 7
    })
}

ane :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // (A OR CONST) AND X AND value -> A
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { 
        // This instruction is highly unstable because it depends on a constant the value of which 
        // is ultimately random and depends on temperature, CPU chip series, and potentially other factors.
        // Using 0xEE as the constant's value in order to pass the tests, but on real hardware the constant will 
        // be random with some more-probable typical values of 0xFF, 0xFE, 0xEE and 0x00.
        cpu.A = (cpu.A | 0xEE) & cpu.X & value

        cpu.P.Z = cpu.A == 0 ? 1 : 0
        cpu.P.N = cpu.A >> 7
    })
}

arr :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // AND + ROR
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { 
        // This opcode activates some parts related to ADC, leading to weird side effects. Full description:
        // In Binary mode (D flag clear), the instruction effectively does an AND between the accumulator and 
        // the immediate parameter, and then shifts the accumulator to the right, copying the C flag to the 8th bit. 
        // It sets the Negative and Zero flags just like the ROR would. The ADC code shows up in the Carry and 
        // Overflow flags. The C flag will be copied from the bit 6 of the result (which doesn't seem too logical), and the
        // V flag is the result of an Exclusive OR operation between the bit 6 and the bit 5 of the result.

        result := cpu.A & value // AND with value
        result = (result >> 1) | (cpu.P.C << 7) // Shift right

        cpu.P.Z = result == 0 ? 1 : 0
        cpu.P.N = result >> 7

        cpu.P.C = (result >> 6) & 1 
        cpu.P.V = ((result >> 6) & 1) ~ ((result >> 5) & 1)

        cpu.A = result
    })
}

dcp :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // DEC + CMP
    // Decrements the operand and then compares the result to the accumulator
    dec(cpu, bus, value)
    compare(cpu, cpu.A, value^)
}

dcp_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, dcp)
}

dcp_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, dcp)
}

dcp_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, dcp)
}

dcp_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, dcp)
}

dcp_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.Y, dcp)
}

dcp_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read_modify_write(cpu, bus, cycle, dcp)
}

dcp_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read_modify_write(cpu, bus, cycle, dcp)
}

isc :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // INC + SBC
    inc(cpu, bus, value)
    sbc(cpu, bus, value^)
}

isc_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, isc)
}

isc_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, isc)
}

isc_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, isc)
}

isc_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, isc)
}

isc_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.Y, isc)
}

isc_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read_modify_write(cpu, bus, cycle, isc)
}

isc_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read_modify_write(cpu, bus, cycle, isc)
}

las_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // LDA/TSX (kinda)
    absi_read(cpu, bus, cycle, cpu.Y, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) {
        result := value & cpu.S

        cpu.A = result
        cpu.X = result
        cpu.S = result

        cpu.P.Z = result == 0 ? 1 : 0
        cpu.P.N = result >> 7
    })
}

lax :: proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { // LDA + LDX
    lda(cpu, bus, value)
    ldx(cpu, bus, value)
}

lax_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, lax)
}

lax_zpgy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.Y, lax)
}

lax_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, lax)
}

lax_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, lax)
}

lax_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, lax)
}

lax_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, lax)
}

lxa :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // LAX immediate
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { 
        // This instruction includes an environment-dependent magic constant, thus highly unstable.
        // Note: Using 0xFF as a magic constant will pass blargg's CPU tests but fail JSON tests.
        // In order for them to pass, use 0xEE as a magic constant.
        result := (cpu.A | 0xFF) & value
        
        cpu.A = result
        cpu.X = result

        cpu.P.Z = result == 0 ? 1 : 0
        cpu.P.N = result >> 7
    })
}

rla :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // ROL + AND
    rol(cpu, bus, value)
    and(cpu, bus, value^)
}

rla_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, rla)
}

rla_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, rla)
}

rla_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, rla)
}

rla_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, rla)
}

rla_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.Y, rla)
}

rla_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read_modify_write(cpu, bus, cycle, rla)
}

rla_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read_modify_write(cpu, bus, cycle, rla)
}

rra :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // ROR + ADC
    ror(cpu, bus, value)
    adc(cpu, bus, value^)
}

rra_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, rra)
}

rra_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, rra)
}

rra_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, rra)
}

rra_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, rra)
}

rra_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.Y, rra)
}

rra_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read_modify_write(cpu, bus, cycle, rra)
}

rra_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read_modify_write(cpu, bus, cycle, rra)
}

// A and X are put on the bus at the same time (resulting effectively in an AND operation) and stored in M
sax_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_write(cpu, bus, cycle, cpu.A & cpu.X)
}

sax_zpgy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_write(cpu, bus, cycle, cpu.Y, cpu.A & cpu.X)
}

sax_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_write(cpu, bus, cycle, cpu.A & cpu.X)
}

sax_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_write(cpu, bus, cycle, cpu.A & cpu.X)
}

sbx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // CMP and DEX at once, sets flags like CMP
    imm(cpu, bus, cycle, proc(cpu: ^CPU, bus: CPU_Bus, value: u8) { 
        ax := cpu.A & cpu.X
        compare(cpu, ax, value)
        cpu.X = ax - value
    })
}

sha_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2 ..= 4:
        absi_write(cpu, bus, cycle, cpu.Y, 0)

        if cycle == 4 { // Second-to-last cycle
            cpu_poll_interrupts(cpu, bus)
        }
    case 5:
        // We need to intercept the 5th cycle of the instruction to get access to effective address (calculated on previous cycles).
        // This instruction is weird and very unstable. General description/observations from my own research:
        // 1. The core of this instruction is the fact that multiple values are being written on the bus simultaneously,
        //    effectively being AND'ed.
        // 2. The value we write is always A & X & (H + 1), where H is the original (non-corrected, non-corrupted)
        //    high byte of the effective address we read from PC.
        // 3. When the page boundary is not crossed, the effective address does not change.
        // 4. When the page boundary is crossed, the high byte of the effetive address itself is corrupted and
        //    gets AND'ed with A & X.

        value := cpu.A & cpu.X
        if cpu.instruction_operands.bytes[LOW] < cpu.Y { // Page crossed
            // Not adding 1 because the high byte was already incremented on 4th cycle
            value &= cpu.instruction_operands.bytes[HIGH] 
            
            // Corruption of high byte of the effective address
            cpu.instruction_operands.bytes[HIGH] &= cpu.A & cpu.X
        } else {
            value &= cpu.instruction_operands.bytes[HIGH] + 1
        }

        absi_write(cpu, bus, cycle, cpu.Y, value)
    }
}

sha_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2 ..= 5:
        indy_write(cpu, bus, cycle, 0)

        if cycle == 5 {
            cpu_poll_interrupts(cpu, bus)
        }
    case 6:
        // Same logic as in sha_absy, but we intercept the 6th cycle.

        value := cpu.A & cpu.X
        if cpu.instruction_operands.bytes[LOW] < cpu.Y {
            value &= cpu.instruction_operands.bytes[HIGH] 
            cpu.instruction_operands.bytes[HIGH] &= cpu.A & cpu.X
        } else {
            value &= cpu.instruction_operands.bytes[HIGH] + 1
        }

        indy_write(cpu, bus, cycle, value)
    }
}

shx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2 ..= 4:
        absi_write(cpu, bus, cycle, cpu.Y, 0)

        if cycle == 4 {
            cpu_poll_interrupts(cpu, bus)
        }
    case 5:
        // Same logic as in sha_absy, but the corruption takes the form of X and not A & X.

        value := cpu.X
        if cpu.instruction_operands.bytes[LOW] < cpu.Y { 
            value &= cpu.instruction_operands.bytes[HIGH] 
            cpu.instruction_operands.bytes[HIGH] &= cpu.X
        } else {
            value &= cpu.instruction_operands.bytes[HIGH] + 1
        }

        absi_write(cpu, bus, cycle, cpu.Y, value)
    }
}

shy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2 ..= 4:
        absi_write(cpu, bus, cycle, cpu.X, 0)

        if cycle == 4 {
            cpu_poll_interrupts(cpu, bus)
        }
    case 5:
        // Same logic as in sha_absy, but the corruption takes the form of Y and not A & X.

        value := cpu.Y
        if cpu.instruction_operands.bytes[LOW] < cpu.X { 
            value &= cpu.instruction_operands.bytes[HIGH] 
            cpu.instruction_operands.bytes[HIGH] &= cpu.Y
        } else {
            value &= cpu.instruction_operands.bytes[HIGH] + 1
        }

        absi_write(cpu, bus, cycle, cpu.X, value)
    }
}

slo :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // ASL + ORA
    asl(cpu, bus, value)
    ora(cpu, bus, value^)
}

slo_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, slo)
}

slo_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, slo)
}

slo_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, slo)
}

slo_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, slo)
}

slo_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.Y, slo)
}

slo_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read_modify_write(cpu, bus, cycle, slo)
}

slo_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read_modify_write(cpu, bus, cycle, slo)
}

sre :: proc(cpu: ^CPU, bus: CPU_Bus, value: ^u8) { // LSR + EOR
    lsr(cpu, bus, value)
    eor(cpu, bus, value^)
}

sre_zpg :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, sre)
}

sre_zpgx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, sre)
}

sre_abs :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, sre)
}

sre_absx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, sre)
}

sre_absy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.Y, sre)
}

sre_indx :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indx_read_modify_write(cpu, bus, cycle, sre)
}

sre_indy :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    indy_read_modify_write(cpu, bus, cycle, sre)
}

tas :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) {
    switch cycle {
    case 2 ..= 4:
        absi_write(cpu, bus, cycle, cpu.Y, 0)

        if cycle == 4 {
            cpu_poll_interrupts(cpu, bus)
        }
    case 5:
        // Puts A AND X in SP and stores A AND X AND (high-byte of addr. + 1) at addr.
        // Same logic as in sha_absy, but with an additional action.

        cpu.S = cpu.A & cpu.X

        value := cpu.A & cpu.X
        if cpu.instruction_operands.bytes[LOW] < cpu.Y { 
            value &= cpu.instruction_operands.bytes[HIGH] 
            cpu.instruction_operands.bytes[HIGH] &= cpu.A & cpu.X
        } else {
            value &= cpu.instruction_operands.bytes[HIGH] + 1
        }

        absi_write(cpu, bus, cycle, cpu.Y, value)
    }
}

usbc :: proc(cpu: ^CPU, bus: CPU_Bus, cycle: u8) { // SBC + NOP, effectively the same as SBC
    sbc_imm(cpu, bus, cycle)
}
