package main

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:thread"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"
import "renderer"

r: renderer.Renderer

logger: runtime.Logger
window: glfw.WindowHandle

main :: proc() {
	logger = log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger
	
	assert(glfw.Init() == true, "Could not init glfw")
	defer glfw.Terminate()
	
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	window = glfw.CreateWindow(640, 480, "Window", nil, nil)
	assert(window != nil, "Could not create a window")
	defer glfw.DestroyWindow(window)

	glfw.SetWindowSizeCallback(window, proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		renderer.resize_surface(&r)
	})
	glfw.SetMouseButtonCallback(window, proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
		context = runtime.default_context()
	})

	assert(renderer.create(&r, renderer.Descriptor {
		window = window,
		clear_color = wgpu.Color { 0.1, 0.2, 0.3, 1.0 },
	}) == nil, "Could not initialize the renderer")
	defer renderer.destroy(&r)

	_, model_ok := renderer.register_model(&r, "res/model.obj")
	assert(model_ok)

	renderer.texturemanager_register_texture_from_file(&r.texture_manager, "res/textures/gradient.png")
	renderer.texturemanager_register_texture_from_file(&r.texture_manager, "res/textures/mech3.png")
	renderer.texturemanager_register_texture_from_file(&r.texture_manager, "res/textures/Grass.png")
	renderer.texturemanager_register_texture_from_file(&r.texture_manager, "res/textures/8BitGuy.png")
	renderer.texturemanager_upload_textures(&r.texture_manager)

	for !wgpu.DevicePoll(r.core.device, false) {
		thread.yield()
	}
	
	now := time.tick_now()
	
	for !glfw.WindowShouldClose(window) {
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}
		defer wgpu.DevicePoll(r.core.device, false, nil)
		defer glfw.PollEvents()
		defer free_all(context.temp_allocator)

		duration := time.tick_since(now)
		now = time.tick_now()
		
		fps := 1000.0 / time.duration_milliseconds(duration)
		new_window_title := fmt.ctprintf("Window - Frame: %v - Fps: %f", duration, fps)

		glfw.SetWindowTitle(window, new_window_title)

		renderer.begin_frame(&r)
		renderer.end_frame(r)
		renderer.present(r)
	}

	for !wgpu.DevicePoll(r.core.device, false, nil) {
		thread.yield()
	}
}
