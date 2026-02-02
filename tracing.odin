package main

import "core:log"

TRACING_ENABLED := false

NES_Component :: enum { CPU, APU, PPU, CPU_BUS, IO }

// TODO: configure this using compile-time flags? Or maybe simply at runtime?
TRACE_COMPONENT :: bit_set[NES_Component]{ 
	.CPU, 
	.APU, 
	.PPU, 
	.CPU_BUS, 
	.IO,
}

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

	@(disabled=.IO not_in TRACE_COMPONENT)
	trace_io :: proc($format: string, args: ..any, loc := #caller_location) {
		log.debugf("IO: " + format, ..args, location = loc)
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
	case .IO:
		trace_io(format, ..args, loc = loc)
	}
}
