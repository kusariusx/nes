package main

Peripheral :: union {
    ^NES_Standard_Controller,
}

Peripheral_Update :: union {
    NES_Standard_Controller_Update,
}

peripheral_read :: proc(peripheral: Peripheral) -> u8 {
    switch p in peripheral {
    case ^NES_Standard_Controller:
        return nes_standard_controller_read(p)
    }
    
    return 0 // Should not happen since switch is exhaustive
}

peripheral_write :: proc(peripheral: Peripheral, value: u8) {
    switch p in peripheral {
    case ^NES_Standard_Controller:
        nes_standard_controller_write(p, value)
    }
}

peripheral_update :: proc(update: Peripheral_Update) {
    switch u in update {
    case NES_Standard_Controller_Update:
        nes_standard_controller_update(u)
    }
}

// TODO: is it really necessary to abstract strobing to ALL possible peripherals?
// I'm sure that for some of them, strobing isn't even a thing. On the other hand, a lot of peripherals 
// listed on NESDev behave exactly like the standard controller, i.e. you first strobe the shift register,
// then read from it one bit at a time. 
// 
// TODO: Take a look, what percentage of peripherals have the concept of strobing, and decide whether this 
// abstraction is necessary.
peripheral_strobe :: proc(peripheral: Peripheral) {
    switch p in peripheral {
    case ^NES_Standard_Controller:
        nes_standard_controller_strobe(p)
    }
}
