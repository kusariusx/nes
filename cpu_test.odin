package main

import "core:time"
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
test_instructions :: proc(t: ^testing.T) {
    walk_proc :: proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (walk_err: os.Error, skip_dir: bool) {
        if info.is_dir {
            return
        }

        // if info.name != "02.json" {
        //     return
        // }

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

            bus := Test_Bus{}
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

    filepath.walk("test", walk_proc , t)
}
