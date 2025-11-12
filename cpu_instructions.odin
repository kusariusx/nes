package main

adc :: proc(cpu: ^CPU, bus: Bus, value: u8) { // Add with Carry
    result_full := u16(cpu.A) + u16(value) + u16(cpu.P.C)
    result := byte(result_full & 0xFF)

    cpu.P.C = byte(result_full >> 8)
    cpu.P.Z = result == 0 ? 1 : 0
    cpu.P.V = ((result ~ cpu.A) & (result ~ value)) >> 7 // Signed overflow/underflow (result sign is different from both A and value)
    cpu.P.N = result >> 7

    cpu.A = result
}

adc_imm :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	imm(cpu, bus, cycle, adc)
}

adc_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	zpg_read(cpu, bus, cycle, adc)
}

adc_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	zpgi_read(cpu, bus, cycle, cpu.X, adc)
}

adc_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	abs_read(cpu, bus, cycle, adc)
}

adc_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.X, adc)
}

adc_absy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.Y, adc)
}

adc_indx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	indx_read(cpu, bus, cycle, adc)
}

adc_indy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	indy_read(cpu, bus, cycle, adc)
}

and :: proc(cpu: ^CPU, bus: Bus, value: u8) {
    result := cpu.A & value

    cpu.P.Z = result == 0 ? 1 : 0
    cpu.P.N = result >> 7

    cpu.A = result
}

and_imm :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	imm(cpu, bus, cycle, and)
}

and_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	zpg_read(cpu, bus, cycle, and)
}

and_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	zpgi_read(cpu, bus, cycle, cpu.X, and)
}

and_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	abs_read(cpu, bus, cycle, and)
}

and_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.X, and)
}

and_absy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	absi_read(cpu, bus, cycle, cpu.Y, and)
}

and_indx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	indx_read(cpu, bus, cycle, and)
}

and_indy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
	indy_read(cpu, bus, cycle, and)
}

asl :: proc(cpu: ^CPU, bus: Bus, value: ^u8) { // Arithmetic shift right
    cpu.P.C = value^ >> 7
    value^ <<= 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

asl_a :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { 
    switch cycle {
    case 2:
        // Dummy read next instruction byte, perform action, done
        bus_read(bus, cpu.PC)
        asl(cpu, bus, &cpu.A)
        cpu_instruction_done(cpu)
    }
}
  
asl_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { 
    zpg_read_modify_write(cpu, bus, cycle, asl)
}

asl_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { 
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, asl)
}

asl_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { 
    abs_read_modify_write(cpu, bus, cycle, asl)
}

asl_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { 
    absi_read_modify_write(cpu, bus, cycle, cpu.X, asl)
}

bcc :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Carry Clear
    rel(cpu, bus, cycle, cpu.P.C == 0)
}

bcs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Carry Set
    rel(cpu, bus, cycle, cpu.P.C == 1)
}

beq :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Equal
    rel(cpu, bus, cycle, cpu.P.Z == 1)
}

bit :: proc(cpu: ^CPU, bus: Bus, value: u8) { // Bit test
    result := cpu.A & value

    cpu.P.Z = result == 0 ? 1 : 0
    cpu.P.V = (value >> 6) & 1
    cpu.P.N = value >> 7 
}

bit_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, bit)
}

bit_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, bit)
}

bmi :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Minus
    rel(cpu, bus, cycle, cpu.P.N == 1)
}

bne :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Not Equal
    rel(cpu, bus, cycle, cpu.P.Z == 0)
}

bpl :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Plus
    rel(cpu, bus, cycle, cpu.P.N == 0)
}

brk :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Break
    switch cycle {
    case 2:
        // Dummy read operand, increment PC
        bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 3:
        // Push PCH on the stack
        stack_push(cpu, bus, cpu.PCH)
    case 4:
        // Push PCL on the stack
        stack_push(cpu, bus, cpu.PCL)
    case 5:
        // Push P on the stack (with B flag set)
        p := cpu.P
        p.B = 1

        stack_push(cpu, bus, byte(p))
    case 6:
        // Fetch PCL
        cpu.PCL = bus_read(bus, 0xFFFE)
    case 7:
        // Fetch PCH, set flags, done
        cpu.PCH = bus_read(bus, 0xFFFF)
        cpu.P.I = 1
        cpu_instruction_done(cpu)
    }
}

bvc :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Overflow Clear
    rel(cpu, bus, cycle, cpu.P.V == 0)
}

bvs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Branch if Overflow Set
    rel(cpu, bus, cycle, cpu.P.V == 1)
}

clc :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Clear Carry
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { cpu.P.C = 0 })
}

cld :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Clear Decimal
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { cpu.P.D = 0 })
}

cli :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Clear Interrupt Disable
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { cpu.P.I = 0 })
}

clv :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Clear Overflow
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { cpu.P.V = 0 })
}

compare :: proc(cpu: ^CPU, a, b: u8) {
    result := a - b

    cpu.P.C = a >= b ? 1 : 0
    cpu.P.Z = a == b ? 1 : 0
    cpu.P.N = result >> 7 
}

cmp :: proc(cpu: ^CPU, bus: Bus, value: u8) { // Compare A
    compare(cpu, cpu.A, value)
}

cmp_imm :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    imm(cpu, bus, cycle, cmp)
}

cmp_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, cmp)
}

cmp_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, cmp)
}

cmp_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, cmp)
}

cmp_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, cmp)
}

cmp_absy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, cmp)
}

cmp_indx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, cmp)
}

cmp_indy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, cmp)
}

cpx :: proc(cpu: ^CPU, bus: Bus, value: u8) { // Compare X
    compare(cpu, cpu.X, value)
}

cpx_imm :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    imm(cpu, bus, cycle, cpx)
}

cpx_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, cpx)
}

cpx_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, cpx)
}

cpy :: proc(cpu: ^CPU, bus: Bus, value: u8) { // Compare Y
    compare(cpu, cpu.Y, value)
}

cpy_imm :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    imm(cpu, bus, cycle, cpy)
}

cpy_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, cpy)
}

cpy_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, cpy)
}

dec :: proc(cpu: ^CPU, bus: Bus, value: ^u8) { // Decrement Memory
    value^ -= 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

dec_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, dec)
}

dec_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, dec)
}

dec_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, dec)
}

dec_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, dec)
}

dex :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Decrement X
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { dec(cpu, bus, &cpu.X) })
}

dey :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Decrement Y
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { dec(cpu, bus, &cpu.Y) })
}

eor :: proc(cpu: ^CPU, bus: Bus, value: u8) { // Bitwise Exclusive OR
    cpu.A ~= value

    cpu.P.Z = cpu.A == 0 ? 1 : 0
    cpu.P.N = cpu.A >> 7
}

eor_imm :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    imm(cpu, bus, cycle, eor)
}

eor_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read(cpu, bus, cycle, eor)
}

eor_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpgi_read(cpu, bus, cycle, cpu.X, eor)
}

eor_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read(cpu, bus, cycle, eor)
}

eor_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.X, eor)
}

eor_absy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    absi_read(cpu, bus, cycle, cpu.Y, eor)
}

eor_indx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    indx_read(cpu, bus, cycle, eor)
}

eor_indy :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    indy_read(cpu, bus, cycle, eor)
}

inc :: proc(cpu: ^CPU, bus: Bus, value: ^u8) { // Increment Memory
    value^ += 1

    cpu.P.Z = value^ == 0 ? 1 : 0
    cpu.P.N = value^ >> 7
}

inc_zpg :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpg_read_modify_write(cpu, bus, cycle, inc)
}

inc_zpgx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    zpgi_read_modify_write(cpu, bus, cycle, cpu.X, inc)
}

inc_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    abs_read_modify_write(cpu, bus, cycle, inc)
}

inc_absx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    absi_read_modify_write(cpu, bus, cycle, cpu.X, inc)
}

inx :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Increment X
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { inc(cpu, bus, &cpu.X) })
}

iny :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Increment Y
    implied(cpu, bus, cycle, proc(cpu: ^CPU, bus: Bus) { inc(cpu, bus, &cpu.Y) })
}

jmp_abs :: proc(cpu: ^CPU, bus: Bus, cycle: u8) { // Jump Absolute
    switch cycle {
    case 2:
        // Fetch low address byte, increment PC
        cpu.instruction_operand = bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 3:
        // Copy low address byte to PCL, fetch high address byte to PCH, done
        cpu.PCH = bus_read(bus, cpu.PC)
        cpu.PCL = cpu.instruction_operand
        cpu_instruction_done(cpu)
    }
}

// Jump Indirect (operand is a 16-bit address of a low byte of the effective address)
jmp_ind :: proc(cpu: ^CPU, bus: Bus, cycle: u8) {
    switch cycle {
    case 2:
        // Fetch pointer address low, increment PC
        cpu.instruction_operands.bytes[LOW] = bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 3:
        // Fetch pointer address high, increment PC
        cpu.instruction_operands.bytes[HIGH] = bus_read(bus, cpu.PC)
        cpu.PC += 1
    case 4:
        // Fetch low address to latch
        cpu.instruction_temp_value = bus_read(bus, cpu.instruction_operands.whole)
    case 5:
        // Fetch PCH, copy latch to PCL, done
        cpu.instruction_operands.bytes[LOW] += 1 // Deliberately ignore page crossing and just increment the low byte (hardware bug)
        cpu.PCH = bus_read(bus, cpu.instruction_operands.whole)

        cpu.PCL = cpu.instruction_temp_value

        cpu_instruction_done(cpu)
    }
}
