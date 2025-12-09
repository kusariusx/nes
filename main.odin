package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

import sdl "vendor:sdl2"

TARGET_FPS :: 60.0
FRAME_TIME_MICROSECONDS :: 1000000.0 / TARGET_FPS 

ROM_PATH :: "games/Super_mario_brothers.nes"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer tracking_allocator_report(track)
	}

	rom_data, err_read := os.read_entire_file_from_filename_or_err(ROM_PATH)
	if err_read != nil {
		fmt.eprintfln("unable to read ROM: %v", err_read)
		return
	}
	defer delete(rom_data)

	nes, err_init := nes_init(rom_data)
	if err_init != nil {
		if err_mapper, ok := err_init.(Mapper_Initialization_Error); ok {
			if err_mapper_not_supported, ok := err_mapper.(Mapper_Not_Supported); ok {
				fmt.eprintfln("mapper %d is not supported", err_mapper_not_supported.mapper_number)
				return
			}
		}

		fmt.eprintf("unable to init NES: %v", err_init)
		return
	}
	defer nes_free(nes)

	nes_reset(nes)

	// For now, hardcode the standard controller
	nes_controller := NES_Standard_Controller{}
	nes_attach_peripheral(nes, &nes_controller, IO_Port.Port_1)
	
	nes_controller_mapping := make(map[sdl.Keycode]Peripheral_Action_Proc)
	nes_controller_mapping[sdl.Keycode.A] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .A, key_state) }
	nes_controller_mapping[sdl.Keycode.S] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .B, key_state) }
	nes_controller_mapping[sdl.Keycode.Z] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .Select, key_state) }
	nes_controller_mapping[sdl.Keycode.X] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .Start, key_state) }
	nes_controller_mapping[sdl.Keycode.UP] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .Up, key_state) }
	nes_controller_mapping[sdl.Keycode.DOWN] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .Down, key_state) }
	nes_controller_mapping[sdl.Keycode.LEFT] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .Left, key_state) }
	nes_controller_mapping[sdl.Keycode.RIGHT] = proc(p: Peripheral, key_state: Button_State) { nes_standard_controller_update_button(p.(^NES_Standard_Controller), .Right, key_state) }
	defer delete(nes_controller_mapping)

	ui_controllers := [1]UI_Controller{
		{
			peripheral = &nes_controller,
			mapping = nes_controller_mapping,
		}
	}

	ui := ui_init(ui_controllers[:])
	defer ui_free(&ui)

	for ui_poll_event(&ui) {
		frame_start := time.tick_now()
		is_odd_frame := nes.ppu.is_odd_frame

		// Emulate 1 frame
		for nes.ppu.is_odd_frame == is_odd_frame {
			nes_tick(nes)
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
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes leaked @ %v\n", entry.size, entry.location)
		}
	}

	if len(track.bad_free_array) > 0 {
		fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
		for entry in track.bad_free_array {
			fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
		}
	}
}
