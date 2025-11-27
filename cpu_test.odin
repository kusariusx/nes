package main

import "core:strings"
import "core:os"
import "core:log"
import "core:path/filepath"
import "core:encoding/json"
import "core:testing"

Test_CPU_State :: struct {
	pc:  u16 `json:"pc"`,
	s:   byte `json:"s"`,
	a:   byte `json:"a"`,
	x:   byte `json:"x"`,
	y:   byte `json:"y"`,
	p:   byte `json:"p"`,
	ram: [][2]u16 `json:"ram"`,
}

Test_Data :: struct {
	name:    string `json:"name"`,
	initial: Test_CPU_State `json:"initial"`,
	final:   Test_CPU_State `json:"final"`,
	cycles:  [][3]union{u16, string} `json:"cycles"`,
}

@(test)
test_instructions_json :: proc(t: ^testing.T) {
    walk_proc :: proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (walk_err: os.Error, skip_dir: bool) {
        if info.is_dir || !strings.ends_with(info.name, ".json") {
            return
        }

        // Ignore tests for magic constant-dependent instruction "lxa #"
        if info.name == "ab.json" {
            return
        }

        data, ok := os.read_entire_file(info.fullpath)
        if !ok {
            return
        }
        defer delete(data)

        t := cast(^testing.T)user_data

        test_cases: []Test_Data
        err := json.unmarshal(data, &test_cases)
        testing.expect_value(t, err, nil)

        // Cleanup
        defer {
            for tc in test_cases {
                delete(tc.name)
                delete(tc.initial.ram)
                delete(tc.final.ram)

                for cycle in tc.cycles {
                    delete(cycle[2].(string))
                }

                delete(tc.cycles)
            }

            delete(test_cases)
        }

        for tc in test_cases {
            cpu := CPU{
                PC = tc.initial.pc,
                S = tc.initial.s,
                A = tc.initial.a,
                X = tc.initial.x,
                Y = tc.initial.y,
                P = CPU_Flags(tc.initial.p),
            }

            bus := Test_CPU_Bus{track_memory_access = true}
            for el in tc.initial.ram {
                address, value := el[0], byte(el[1])
                bus.ram[address] = value
            }

            cpu_tick(&cpu, &bus) // 1st cycle (decode instruction)
            for cpu.instruction != nil { // Tick CPU until instruction is fully executed
                cpu_tick(&cpu, &bus)
            }

            test_ok := true

            test_ok &&= testing.expect_value(t, cpu.PC, tc.final.pc)
            test_ok &&= testing.expect_value(t, cpu.S, tc.final.s)
            test_ok &&= testing.expect_value(t, cpu.A, tc.final.a)
            test_ok &&= testing.expect_value(t, cpu.X, tc.final.x)
            test_ok &&= testing.expect_value(t, cpu.Y, tc.final.y)
            test_ok &&= testing.expect_value(t, cpu.P, CPU_Flags(tc.final.p))

            for expected_ram in tc.final.ram {
                test_ok &&= testing.expect_value(t, bus.ram[expected_ram[0]], byte(expected_ram[1]))
            }

            test_ok &&= testing.expect_value(t, bus.memory_access_idx, len(tc.cycles))
            for expected_cycle, i in tc.cycles {
                test_ok &&= testing.expect_value(t, bus.memory_accesses[i].address, expected_cycle[0].(u16))
                test_ok &&= testing.expect_value(t, bus.memory_accesses[i].value, expected_cycle[1].(u16))
                test_ok &&= testing.expect_value(t, bus.memory_accesses[i].operation, expected_cycle[2].(string))
            }

            if !test_ok {
                log.fatalf("test '%s' in file %s has failed", tc.name, info.name)
            }
        }

        return
    }

    filepath.walk("test/cpu/json", walk_proc, t)
}

@(test)
test_instructions_nestest :: proc(t: ^testing.T) {
    rom_data, ok := os.read_entire_file("test/cpu/nestest.nes")
    testing.expect_value(t, ok, true)
    defer delete(rom_data)

    rom, err := rom_parse(rom_data)
    testing.expect_value(t, err, nil)
    defer rom_free(rom)

    m := NROM{}
    bus := NES_CPU_Bus{
        rom = rom,
        mapper = &m,
    }

    cpu := CPU{}
    cpu_reset(&cpu, &bus)
    cpu.PC = 0xC000 // Custom PC for this test ROM

    buffer: [1]byte

    loc02, loc03: u8
    instrs := 0
    for cpu.PC < 0xFFFF && loc02 == 0 && loc03 == 0 && !cpu.halt {
        cpu_tick(&cpu, &bus)
        for cpu.instruction != nil {
            cpu_tick(&cpu, &bus)
        }

        loc02, loc03 = cpu_bus_read(&bus, 0x02), cpu_bus_read(&bus, 0x03)
        instrs += 1
    }

    testing.expect_value(t, loc02, 0)
    testing.expect_value(t, loc03, 0)
}

@(test)
test_instructions_blargg :: proc(t: ^testing.T) {
    walk_proc :: proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (walk_err: os.Error, skip_dir: bool) {
        if info.is_dir || !strings.ends_with(info.name, ".nes") {
            return
        }

        t := cast(^testing.T)user_data
        
        rom_data, ok := os.read_entire_file(info.fullpath)
        testing.expect_value(t, ok, true)
        defer delete(rom_data)

        rom, err := rom_parse(rom_data)
        testing.expect_value(t, err, nil)
        defer rom_free(rom)


        mapper := NROM{}
        cpu_bus := NES_CPU_Bus{
            rom = rom,
            mapper = &mapper,
        }

        cpu := CPU{}
        cpu_reset(&cpu, &cpu_bus)

        ppu := PPU{}
        ppu_bus := NES_PPU_Bus{
            cpu_bus = &cpu_bus,
            rom = rom,
            mapper = &mapper,
        }

        cpu_bus.ppu = &ppu
        cpu_bus.ppu_bus = &ppu_bus

        test_result_loc :: 0x6000

        cpu_bus_write(&cpu_bus, test_result_loc, 0x80) // Test is running
        for cpu_bus_read(&cpu_bus, test_result_loc) == 0x80  {
            cpu_tick(&cpu, &cpu_bus) 
        }

        test_ok := true

        // Validate signature indicating that the test result is valid
        test_ok &&= testing.expect_value(t, cpu_bus_read(&cpu_bus, 0x6001), 0xDE)
        test_ok &&= testing.expect_value(t, cpu_bus_read(&cpu_bus, 0x6002), 0xB0)
        test_ok &&= testing.expect_value(t, cpu_bus_read(&cpu_bus, 0x6003), 0x61)

        // Validate the test result - value 0 means the test passed
        test_ok &&= testing.expect_value(t, cpu_bus_read(&cpu_bus, test_result_loc), 0)

        if !test_ok {
            log.fatalf("test %s has failed", info.name)
        }

        return
    }

    filepath.walk("test/cpu/blargg-singles", walk_proc, t)
}
