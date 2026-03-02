package main

import "core:strings"
import "core:os"
import "core:log"
import "core:path/filepath"
import "core:testing"

@(test)
test_instructions_nestest :: proc(t: ^testing.T) {
    rom_data, ok := os.read_entire_file("test/cpu/nestest.nes")
    testing.expect_value(t, ok, true)
    defer delete(rom_data)

    nes, err := nes_init(rom_data)
    testing.expect_value(t, err, nil)
    defer nes_free(nes)

    nes_reset(nes)
    nes.cpu.PC = 0xC000 // Custom PC for this test ROM

    loc02, loc03: u8
    for loc02 == 0 && loc03 == 0 && !nes.cpu.halt {
        cpu_tick(nes.cpu, nes.cpu_bus)

        loc02, loc03 = cpu_bus_read(nes.cpu_bus, 0x02), cpu_bus_read(nes.cpu_bus, 0x03)
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

        nes, err := nes_init(rom_data)
        testing.expect_value(t, err, nil)
        defer nes_free(nes)

        nes_reset(nes)

        test_result_loc :: 0x6000

        cpu_bus_write(nes.cpu_bus, test_result_loc, 0x80) // Test is running
        for cpu_bus_read(nes.cpu_bus, test_result_loc) == 0x80  {
            cpu_tick(nes.cpu, nes.cpu_bus)
        }

        test_ok := true

        // Validate signature indicating that the test result is valid
        test_ok &&= testing.expect_value(t, cpu_bus_read(nes.cpu_bus, 0x6001), 0xDE)
        test_ok &&= testing.expect_value(t, cpu_bus_read(nes.cpu_bus, 0x6002), 0xB0)
        test_ok &&= testing.expect_value(t, cpu_bus_read(nes.cpu_bus, 0x6003), 0x61)

        // Validate the test result - value 0 means the test passed
        test_ok &&= testing.expect_value(t, cpu_bus_read(nes.cpu_bus, test_result_loc), 0)

        if !test_ok {
            log.fatalf("test %s has failed", info.name)
        }

        return
    }

    filepath.walk("test/cpu/blargg-singles", walk_proc, t)
}
