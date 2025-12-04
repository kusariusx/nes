package main

NES :: struct {
    ppu: ^PPU,
    apu: ^APU,
    cpu: ^CPU,

    cpu_bus: CPU_Bus,
    ppu_bus: ^NES_PPU_Bus,

    rom: ^ROM,
    mapper: Mapper,
}

nes_init :: proc() -> ^NES {
    ppu := new(PPU)
	apu := new(APU)
    cpu := new(CPU)   
	
	ppu_bus := new(NES_PPU_Bus)
    cpu_bus := new(NES_CPU_Bus)

	ppu_bus.cpu_bus = cpu_bus
    
	cpu_bus.ppu = ppu
    cpu_bus.ppu_bus = ppu_bus
    cpu_bus.apu = apu

    return new_clone(NES{
        ppu = ppu,
        apu = apu,
        cpu = cpu,
        ppu_bus = ppu_bus,
        cpu_bus = cpu_bus,
    })
}

nes_free :: proc(nes: ^NES) {
    free(nes.ppu)
    free(nes.apu)
    free(nes.cpu)

    free(nes.ppu_bus)
    free(nes.cpu_bus)

    if nes.rom != nil {
        
    }
}
