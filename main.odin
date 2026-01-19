package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:time"

import sdl "vendor:sdl2"

TARGET_FPS :: 60.0
FRAME_TIME_MICROSECONDS :: 1000000.0 / TARGET_FPS 

ROM_PATH :: "test/other/AccuracyCoin/AccuracyCoin.nes"

TRACING_ENABLED := false

main :: proc() {
	when ODIN_DEBUG {
		// Set up tracking allocator
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer tracking_allocator_report(track)
	}

	// Set up logger
	logger := log.create_console_logger(opt = {})
	context.logger = logger
	defer log.destroy_console_logger(logger)

	rom_data, err_read := os.read_entire_file_from_filename_or_err(ROM_PATH)
	if err_read != nil {
		log.errorf("unable to read ROM: %v", err_read)
		return
	}
	defer delete(rom_data)

	nes, err_init := nes_init(rom_data)
	if err_init != nil {
		if err_mapper, ok := err_init.(Mapper_Initialization_Error); ok {
			if err_mapper_not_supported, ok := err_mapper.(Mapper_Not_Supported); ok {
				log.errorf("mapper %d is not supported", err_mapper_not_supported.mapper_number)
				return
			}
		}

		log.errorf("unable to init NES: %v", err_init)
		return
	}
	defer nes_free(nes)

	log.infof("successfully loaded ROM with mapper %d", mapper_number(nes.rom))

	nes_reset(nes)

	nes_mappings := make(map[sdl.Keycode][UI_Key_State]proc(nes: ^NES))
	nes_mappings[.B] = #partial {.Down = proc(nes: ^NES) { 
		nes.breakpoint = !nes.breakpoint 
		log.infof("breakpoint %s", nes.breakpoint ? "enabled" : "disabled")
	}}
	nes_mappings[.V] = #partial {.Down = proc(nes: ^NES) { 
		if nes.breakpoint {
			nes_debug_run_cpu_instruction(nes) 
		}
	}}
	// TODO: remove this after testing is done
	nes_mappings[.P] = #partial {.Down = proc(nes: ^NES) { 
		buf: [0xFF]byte
		for i in u16(0) ..< 0xFF {
			buf[i] = cpu_bus_read(nes.cpu_bus, 0x500 + i)
		}

		for i in 0 ..< 4 {
			for j in 0 ..< 32 {
				fmt.printf("$%02X, ", buf[i*32 + j])
			}
			fmt.printf("\n")
		}
	}}
	defer delete(nes_mappings)

	// For now, hardcode the standard controller
	nes_controller := NES_Standard_Controller{}
	nes_attach_peripheral(nes, &nes_controller, IO_Port.Port_1)
	
	peripheral_mappings := make(map[sdl.Keycode][UI_Key_State]Peripheral_Update)
	peripheral_mappings[.A] = {.Down = NES_Standard_Controller_Update{&nes_controller, .A, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .A, .Released}}
	peripheral_mappings[.S] = {.Down = NES_Standard_Controller_Update{&nes_controller, .B, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .B, .Released}}
	peripheral_mappings[.Z] = {.Down = NES_Standard_Controller_Update{&nes_controller, .Select, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .Select, .Released}}
	peripheral_mappings[.X] = {.Down = NES_Standard_Controller_Update{&nes_controller, .Start, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .Start, .Released}}
	peripheral_mappings[.UP] = {.Down = NES_Standard_Controller_Update{&nes_controller, .Up, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .Up, .Released}}
	peripheral_mappings[.DOWN] = {.Down = NES_Standard_Controller_Update{&nes_controller, .Down, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .Down, .Released}}
	peripheral_mappings[.LEFT] = {.Down = NES_Standard_Controller_Update{&nes_controller, .Left, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .Left, .Released}}
	peripheral_mappings[.RIGHT] = {.Down = NES_Standard_Controller_Update{&nes_controller, .Right, .Pressed}, .Up = NES_Standard_Controller_Update{&nes_controller, .Right, .Released}}
	defer delete(peripheral_mappings)

	ui := ui_init(nes, nes_mappings, peripheral_mappings, Overscan_Config{0, 0, 0, 0})
	defer ui_free(&ui)

	for ui_poll_event(&ui) {
		frame_start := time.tick_now()
		is_odd_frame := nes.ppu.is_odd_frame

		if !nes.breakpoint {
			// Emulate 1 frame
			for nes.ppu.is_odd_frame == is_odd_frame {
				nes_tick(nes)
			}
		} else {
			// When breakpoint is active, steps of the system will be controlled by user inputs
		}
		
		ui_update_texture(&ui, nes.ppu.framebuffer[:])
		ui_render(&ui)
		
		// Limit to 60 FPS
		elapsed := time.duration_microseconds(time.tick_since(frame_start))
		if elapsed < FRAME_TIME_MICROSECONDS {
			to_sleep := time.Duration(FRAME_TIME_MICROSECONDS - elapsed) * time.Microsecond
			time.sleep(to_sleep)
		}
	}
}

tracking_allocator_report :: proc(track: mem.Tracking_Allocator) {
	if len(track.allocation_map) > 0 {
		log.errorf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			log.errorf("- %v bytes leaked @ %v\n", entry.size, entry.location)
		}
	}

	if len(track.bad_free_array) > 0 {
		log.errorf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
		for entry in track.bad_free_array {
			log.errorf("- %p @ %v\n", entry.memory, entry.location)
		}
	}
}

NES_Component :: enum { CPU, APU, PPU, CPU_BUS }

// TODO: configure this using compile-time flags? Or maybe simply at runtime?
TRACE_COMPONENT :: bit_set[NES_Component]{ .CPU, .APU, .PPU, .CPU_BUS }

@(disabled=!ODIN_DEBUG) // Disabled when not in debug
trace :: proc(component: NES_Component, $format: string, args: ..any, loc := #caller_location) {
	if !TRACING_ENABLED { // Tracing is also protected with runtime switch
		return
	}

	@(disabled=.CPU not_in TRACE_COMPONENT)
	trace_cpu :: proc($format: string, args: ..any, loc := #caller_location) {
		log.debugf("CPU: " + format, ..args, location = loc)
	}

	@(disabled=.PPU not_in TRACE_COMPONENT)
	trace_ppu :: proc($format: string, args: ..any, loc := #caller_location) {
		log.debugf("PPU: " + format, ..args, location = loc)
	}
	
	@(disabled=.APU not_in TRACE_COMPONENT)
	trace_apu :: proc($format: string, args: ..any, loc := #caller_location) {
		log.debugf("APU: " + format, ..args, location = loc)
	}

	@(disabled=.CPU_BUS not_in TRACE_COMPONENT)
	trace_cpu_bus :: proc($format: string, args: ..any, loc := #caller_location) {
		log.debugf("CPU BUS: " + format, ..args, location = loc)
	}
	
	switch component {
	case .CPU:
		trace_cpu(format, ..args, loc = loc)
	case .PPU:
		trace_ppu(format, ..args, loc = loc)
	case .APU: 
		trace_apu(format, ..args, loc = loc)
	case .CPU_BUS:
		trace_cpu_bus(format, ..args, loc = loc)
	}
}
