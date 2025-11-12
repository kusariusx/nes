package main

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

UI :: struct {
    window: ^sdl.Window, 
    renderer: ^sdl.Renderer,
}

ui_init :: proc() -> UI {
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

	renderer_flags := sdl.RendererFlags{.ACCELERATED}
	renderer := sdl.CreateRenderer(window, 0, renderer_flags)
	if renderer == nil {
		panic("unable to create renderer")
	}

    return UI{
        window = window,
        renderer = renderer
    }
}