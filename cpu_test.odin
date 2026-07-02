package main

import "core:strings"
import "core:os"
import "core:log"
import "core:testing"

@(test)
test_instructions_nestest :: proc(t: ^testing.T) {
    rom_data, err_read := os.read_entire_file("test/cpu/nestest.nes", context.allocator)
    testing.expect_value(t, err_read, nil)
    defer delete(rom_data)

    nes, err_init := nes_init(rom_data, .NTSC)
    testing.expect_value(t, err_init, nil)
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
    w := os.walker_create("test/cpu/blargg-singles")
    defer os.walker_destroy(&w)

    for info in os.walker_walk(&w) {
        if info.type == .Directory || !strings.ends_with(info.name, ".nes") {
            os.walker_skip_dir(&w)
            continue
        }

        rom_data, err_read := os.read_entire_file(info.fullpath, context.allocator)
        testing.expect_value(t, err_read, nil)
        defer delete(rom_data)

        nes, err_init := nes_init(rom_data, .NTSC)
        testing.expect_value(t, err_init, nil)
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
    }

    _, err_walk := os.walker_error(&w)
    testing.expect_value(t, err_walk, nil)
}
