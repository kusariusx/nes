package main

import "core:log"
import sdl "vendor:sdl2"

WINDOW_SCALE :: 3

NES_SCREEN_WIDTH :: 256
NES_SCREEN_HEIGHT :: 240

WINDOW_WIDTH :: NES_SCREEN_WIDTH * WINDOW_SCALE
WINDOW_HEIGHT :: NES_SCREEN_HEIGHT * WINDOW_SCALE

AUDIO_SAMPLE_RATE :: 44100
AUDIO_SAMPLE_BUFFER_SIZE :: AUDIO_SAMPLE_RATE / TARGET_FPS

CPU_FREQUENCY :: 1789773
CPU_CYCLES_PER_SAMPLE :: f32(CPU_FREQUENCY) / f32(AUDIO_SAMPLE_RATE)

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

// On real NTSC TVs, not all 256x240 pixels produced by the PPU are actually visible on the screen.
// Due to different form-factors of the TVs, and due to how PPU signal is interpreted by the TV,
// some of the pixels on the edges of the screen might be cut off.
// This structure defines how many pixels are cut off on each edge.
Overscan_Config :: struct {
    left, top, right, bottom: i32
}

UI_Key_State :: enum {
    Down,
    Up,
}

// We map key presses/releases to actions on peripherals
Peripheral_Mappings :: map[sdl.Keycode][UI_Key_State]Peripheral_Update

// Mappings that can control the entire NES
NES_Mappings :: map[sdl.Keycode][UI_Key_State]proc(nes: ^NES)

UI :: struct {
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    texture: ^sdl.Texture,
    texture_source_rect: sdl.Rect,

    // UI is able to control the entire system
    nes: ^NES,
    nes_mappings: NES_Mappings,
    peripheral_mappings: Peripheral_Mappings,

    audio_device_id: sdl.AudioDeviceID,
    audio_cycle_counter: f32,
    audio_previous_output: f32,
    audio_blip_buffer: Blip_Buffer,
}

ui_init :: proc(
    nes: ^NES, 
    nes_mappings: NES_Mappings, 
    peripheral_mappings: Peripheral_Mappings,
    overscan_config: Overscan_Config,
) -> UI {
    screen_texture_width := NES_SCREEN_WIDTH - overscan_config.left - overscan_config.right
    screen_texture_height := NES_SCREEN_HEIGHT - overscan_config.top - overscan_config.bottom

    // Validate provided overscan config
    if screen_texture_width <= 0 || screen_texture_width > NES_SCREEN_WIDTH || 
        screen_texture_height <= 0 || screen_texture_height > NES_SCREEN_HEIGHT {
        panic("overscan config is invalid")
    }

    window_flags := sdl.WindowFlags{.OPENGL, .ALLOW_HIGHDPI, .RESIZABLE}
	window := sdl.CreateWindow(
		"NES",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		screen_texture_width * WINDOW_SCALE,
		screen_texture_height * WINDOW_SCALE,
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

    // Initialize audio
    res := sdl.Init({.AUDIO})
    if res != 0 {
        panic("unable to initialize audio")
    }

    audio_spec := sdl.AudioSpec{
        freq = AUDIO_SAMPLE_RATE,
        format = sdl.AUDIO_F32SYS,
        channels = 1,
        samples = AUDIO_SAMPLE_BUFFER_SIZE,
    }

    audio_device_id := sdl.OpenAudioDevice(nil, false, &audio_spec, nil, nil)
    sdl.PauseAudioDevice(audio_device_id, false) // Unpause audio

    blip_buffer_init_steps()

    return UI{
        window = window,
        renderer = renderer,
        texture = texture,
        texture_source_rect = sdl.Rect{
            x = overscan_config.left,
            y = overscan_config.top,
            w = screen_texture_width,
            h = screen_texture_height,
        },
        nes = nes,
        nes_mappings = nes_mappings,
        peripheral_mappings = peripheral_mappings,
        audio_device_id = audio_device_id,
        audio_blip_buffer = Blip_Buffer{},
    }
}

ui_tick_audio :: proc(ui: ^UI) {
    time := ui.audio_cycle_counter / CPU_CYCLES_PER_SAMPLE

    current_output := ui.nes.apu.mixer_output
    if current_output != ui.audio_previous_output {
        delta := current_output - ui.audio_previous_output
        blip_buffer_add_delta(&ui.audio_blip_buffer, time, delta)
        ui.audio_previous_output = current_output
    }

    ui.audio_cycle_counter += 1.0
}

ui_flush_audio :: proc(ui: ^UI) {
    blip_buffer_prepare(&ui.audio_blip_buffer)

    sdl.QueueAudio(ui.audio_device_id, &ui.audio_blip_buffer.buffer, u32(AUDIO_SAMPLE_BUFFER_SIZE) * size_of(f32))
    ui.audio_cycle_counter = 0.0

    blip_buffer_clear(&ui.audio_blip_buffer)
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
    sdl.RenderCopy(ui.renderer, ui.texture, &ui.texture_source_rect, nil)    
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

            // When in debug mode, make it possible to toggle tracing/disassembly at runtime
            when DEBUG_FEATURES {
                if event.type == sdl.EventType.KEYDOWN {
                    #partial switch event.key.keysym.sym {
                    case sdl.Keycode.T:
                        TRACING_ENABLED = !TRACING_ENABLED
                        log.infof("tracing %s", TRACING_ENABLED ? "enabled" : "disabled")
                    case sdl.Keycode.D:
                        DISASSEMBLY_ENABLED = !DISASSEMBLY_ENABLED
                        log.infof("disassembly %s", DISASSEMBLY_ENABLED ? "enabled" : "disabled")
                    }
                }
            }

            key_state := event.type == sdl.EventType.KEYDOWN ? UI_Key_State.Down : UI_Key_State.Up

            pm, ok_pm := ui.peripheral_mappings[event.key.keysym.sym]
            if ok_pm && pm[key_state] != nil {
                peripheral_update(pm[key_state])
            }

            nm, ok_nm := ui.nes_mappings[event.key.keysym.sym]
            if ok_nm && nm[key_state] != nil {
                nm[key_state](ui.nes)
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
    if ui.audio_device_id != 0 {
        sdl.CloseAudioDevice(ui.audio_device_id)
    }

    sdl.Quit()
}
