package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

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

	rom, err_parsing := rom_parse(rom_data)
	if err_parsing != nil {
		fmt.eprintfln("unable to parse ROM: %v", err_read)
		return
	}
	defer rom_free(rom)

	mapper := mapper_init(rom)
	if mapper == nil {
		fmt.eprintfln("mapper is not supported")
		return
	}
	defer mapper_free(mapper)

	ppu := PPU{}
	
	ppu_bus := NES_PPU_Bus{
		mapper = mapper,
		rom = rom,
	}

	cpu_bus := NES_CPU_Bus{
		mapper = mapper,
		ppu = &ppu,
		ppu_bus = &ppu_bus,
		rom = rom,
	}

	ppu_bus.cpu_bus = &cpu_bus

	cpu := CPU{}
	cpu_reset(&cpu, &cpu_bus)

	ui := ui_init()
	defer ui_free(&ui)

	for ui_poll_event() {
		frame_start := time.tick_now()
		is_odd_frame := ppu.is_odd_frame

		// Emulate 1 frame
		for ppu.is_odd_frame == is_odd_frame {
			cpu_tick(&cpu, &cpu_bus)

			// 3 PPU cycles for every CPU cycle
			ppu_tick(&ppu, &ppu_bus)
			ppu_tick(&ppu, &ppu_bus)
			ppu_tick(&ppu, &ppu_bus)
		}
		
		ui_update_texture(&ui, ppu.framebuffer[:])
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
