package main

Button_State :: enum {
    Released,
    Pressed,
}

NES_Standard_Controller_Button :: enum {
    A,
    B,
    Select,
    Start,
    Up,
    Down,
    Left,
    Right,
}

NES_Standard_Controller :: struct {
    button_states: u8, // This holds real-time button states (0 - not pressed, 1 - pressed)
    strobe: bool, // While this is true - button states will be continuosly latched into the shift register
    shift_register: u8, // This holds latched button states, shifts after every read
}

nes_standard_controller_read :: proc(c: ^NES_Standard_Controller) -> u8 {
    if c.strobe { // Reload shift register
        c.shift_register = c.button_states
    }

    result := c.shift_register & 1

    // Shift register right and put 1 into the highest bit because after 8 reads all subsequent reads must return 1 
    c.shift_register = (1 << 7) | (c.shift_register >> 1)

    return result
}

nes_standard_controller_write :: proc(c: ^NES_Standard_Controller, value: u8) {
    c.strobe = value & 1 == 1

    // Start reloading the shift register immediately after write
    if c.strobe {
        c.shift_register = c.button_states
    }
}

nes_standard_controller_update_button :: proc(c: ^NES_Standard_Controller, b: NES_Standard_Controller_Button, s: Button_State) {
    target_bit := u8(1) << u8(b)
    target_state := u8(s) << u8(b)

    c.button_states = (c.button_states & ~target_bit) | target_state // Set corresponding bit
}
