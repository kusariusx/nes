package main

import "core:fmt"
import "core:io"

DISASSEMBLY_ENABLED := false

@(private="file")
Disassembler :: struct {
    opcode: u8,
    instruction: ^Instruction,
    operand: [2]byte,
    operand_index: int,
    cpu_state: CPU_State,
    
    output_writer: io.Writer,
}

// TODO: is it OK to have a singleton disassembler? Any possibility of needing more than one?
@(private="file")
d: Disassembler

@(private="file")
branch_opcodes :: [?]u8{
    0x10, // bpl
    0x30, // bmi
    0x50, // bvc
    0x70, // bvs
    0x90, // bcc
    0xB0, // bcs
    0xD0, // bne
    0xF0, // beq
}

disassembler_set_output_stream :: proc(output_writer: io.Writer) {
    d.output_writer = output_writer
}

@(disabled=!ODIN_DEBUG)
disassembler_start_instruction :: proc(opcode: u8, instruction: ^Instruction, cpu_state: CPU_State) {
    d.opcode = opcode
    d.instruction = instruction
    d.cpu_state = cpu_state
}

@(disabled=!ODIN_DEBUG)
disassembler_set_operand :: proc(operand: byte) {
    d.operand[d.operand_index] = operand
    d.operand_index += 1
}

@(disabled=!ODIN_DEBUG)
disassembler_end_instruction :: proc() {
    defer {
        d.operand = {0, 0}
        d.operand_index = 0
    }

    if d.output_writer.procedure == nil || !DISASSEMBLY_ENABLED {
        return
    }

    cpu_state_buf, instruction_bytes_buf, instruction_buf: [256]byte = ---, ---, ---
    cpu_state_str, instruction_bytes_str, instruction_str: string

    cpu := d.cpu_state
    cpu_state_str = fmt.bprintf(cpu_state_buf[:], "[PC:%04X P:%02X S:%02X A:%02X X:%02X Y:%02X]", cpu.PC, u8(cpu.P), cpu.S, cpu.A, cpu.X, cpu.Y)

    instruction_format := d.instruction.format != "" ? d.instruction.format : d.instruction.mnemonic

    switch d.operand_index {
    case 0: // No operands
        instruction_bytes_str = fmt.bprintf(instruction_bytes_buf[:], "%02X      ", d.opcode)
        instruction_str = fmt.bprintf(instruction_buf[:], "%s", d.instruction.mnemonic)
    case 1: // 1-byte operand
        is_branch_instruction := false
        for op in branch_opcodes {
            if d.opcode == op {
                is_branch_instruction = true
                break
            }
        }

        instruction_bytes_str = fmt.bprintf(instruction_bytes_buf[:], "%02X %02X   ", d.opcode, d.operand[0])

        if is_branch_instruction {
            offset := i8(d.operand[0])

            target_address := cpu.PC + 2 // Branch instructions are 2 bytes long
            if offset < 0 {
                target_address -= u16(-offset)
            } else {
                target_address += u16(offset)
            }

            instruction_str = fmt.bprintf(instruction_buf[:], instruction_format, target_address)   
        } else {
            instruction_str = fmt.bprintf(instruction_buf[:], instruction_format, d.operand[0])
        }
    case 2: // 2-byte operand
        instruction_bytes_str = fmt.bprintf(instruction_bytes_buf[:], "%02X %02X %02X", d.opcode, d.operand[0], d.operand[1])
        instruction_str = fmt.bprintf(instruction_buf[:], instruction_format, d.operand[1], d.operand[0])
    }

    output_buffer: [256]byte = ---
    output := fmt.bprintfln(output_buffer[:], "%s | %s | %s", cpu_state_str, instruction_bytes_str, instruction_str)

    io.write_string(d.output_writer, output)
}
