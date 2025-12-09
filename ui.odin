package main

import sdl "vendor:sdl2"

WINDOW_SCALE :: 3

NES_SCREEN_WIDTH :: 256
NES_SCREEN_HEIGHT :: 240

WINDOW_WIDTH :: NES_SCREEN_WIDTH * WINDOW_SCALE
WINDOW_HEIGHT :: NES_SCREEN_HEIGHT * WINDOW_SCALE

// NES palette - 64 colors in RGB format (0xRRGGBB)
NES_PALETTE := [64]u32{
    0x666666, 0x002A88, 0x1412A7, 0x3B00A4, 0x5C007E, 0x6E0040, 0x6C0600, 0x561D00,
    0x333500, 0x0B4800, 0x005200, 0x004F08, 0x00404D, 0x000000, 0x000000, 0x000000,
    0xADADAD, 0x155FD9, 0x4240FF, 0x7527FE, 0xA01ACC, 0xB71E7B, 0xB53120, 0x994E00,
    0x6B6D00, 0x388700, 0x0C9300, 0x008F32, 0x007C8D, 0x000000, 0x000000, 0x000000,
    0xFFFEFF, 0x64B0FF, 0x9290FF, 0xC676FF, 0xF36AFF, 0xFE6ECC, 0xFE8170, 0xEA9E22,
    0xBCBE00, 0x88D800, 0x5CE430, 0x45E082, 0x48CDDE, 0x4F4F4F, 0x000000, 0x000000,
    0xFFFEFF, 0xC0DFFF, 0xD3D2FF, 0xE8C8FF, 0xFBC2FF, 0xFEC4EA, 0xFECCC5, 0xF7D8A5,
    0xE4E594, 0xCFEF96, 0xBDF4AB, 0xB3F3CC, 0xB5EBF2, 0xB8B8B8, 0x000000, 0x000000,
}

Peripheral_Action_Proc :: proc(p: Peripheral, key_state: Button_State)

UI_Controller :: struct {
    peripheral: Peripheral,
    mapping: map[sdl.Keycode]Peripheral_Action_Proc, // We map key presses to actions on the peripheral
}

UI :: struct {
    window: ^sdl.Window, 
    renderer: ^sdl.Renderer,
    texture: ^sdl.Texture,

    controllers: []UI_Controller,
}

ui_init :: proc(controllers: []UI_Controller) -> UI {
    window_flags := sdl.WindowFlags{sdl.WindowFlag.OPENGL}
	window := sdl.CreateWindow(
		"NES",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		window_flags,
	)
	if window == nil {
		panic("unable to create window")
	}

	renderer_flags := sdl.RendererFlags{sdl.RendererFlag.ACCELERATED}
	renderer := sdl.CreateRenderer(window, 0, renderer_flags)
	if renderer == nil {
		panic("unable to create renderer")
	}

	// Create texture for NES framebuffer (256x240)
	texture := sdl.CreateTexture(
		renderer,
		sdl.PixelFormatEnum.RGB888,
		sdl.TextureAccess.STREAMING,
		NES_SCREEN_WIDTH,
		NES_SCREEN_HEIGHT,
	)
	if texture == nil {
		panic("unable to create texture")
	}

    return UI{
        window = window,
        renderer = renderer,
        texture = texture,
        controllers = controllers,
    }
}

ui_update_texture :: proc(ui: ^UI, framebuffer: []u8) {
    // Lock texture for writing
    pixels: rawptr
    pitch: i32
    if sdl.LockTexture(ui.texture, nil, &pixels, &pitch) != 0 {
        return
    }
    defer sdl.UnlockTexture(ui.texture)

	pixels_per_row := int(pitch) / size_of(u32)
    
    // Convert framebuffer (palette indices) to RGB
    pixel_data := cast([^]u32)pixels
    for y in 0 ..< NES_SCREEN_HEIGHT {
        for x in 0 ..< NES_SCREEN_WIDTH {
            fb_index := y * NES_SCREEN_WIDTH + x
            palette_index := framebuffer[fb_index]
            
            // Get RGB color from NES palette
            rgb := NES_PALETTE[palette_index & 0x3F] // Mask to 0-63
            
            pixel_index := y * pixels_per_row + x
            pixel_data[pixel_index] = rgb
        }
    }
}

ui_render :: proc(ui: ^UI) {
    sdl.RenderClear(ui.renderer)    
    sdl.RenderCopy(ui.renderer, ui.texture, nil, nil)    
    sdl.RenderPresent(ui.renderer)
}

ui_poll_event :: proc(ui: ^UI) -> bool {
    event: sdl.Event
	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case sdl.EventType.QUIT:
			return false
		case sdl.EventType.KEYDOWN, sdl.EventType.KEYUP:
            if event.key.keysym.sym == sdl.Keycode.Q {
                return false // Quit the app
            }

            key_state := event.type == sdl.EventType.KEYDOWN ? Button_State.Pressed : Button_State.Released

            for c in ui.controllers {
                action, ok := c.mapping[event.key.keysym.sym]
                if ok {
                    action(c.peripheral, key_state)
                }
            }
		}
	}

	return true
}

ui_free :: proc(ui: ^UI) {
    if ui.texture != nil {
        sdl.DestroyTexture(ui.texture)
    }
    if ui.renderer != nil {
        sdl.DestroyRenderer(ui.renderer)
    }
    if ui.window != nil {
        sdl.DestroyWindow(ui.window)
    }
    sdl.Quit()
}
