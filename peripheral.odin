package main

Peripheral :: union {
    ^NES_Standard_Controller,
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
