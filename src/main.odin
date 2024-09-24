package main

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:thread"
import "core:time"
import la "core:math/linalg"
import "vendor:glfw"
import "vendor:wgpu"
import "renderer"
import ui "vendor:microui"

r: renderer.Renderer

logger: runtime.Logger
window: glfw.WindowHandle

ui_context: ui.Context

General_State_Uniforms :: struct #packed {
	time: f32,
	aspect_rateo: f32,
}

Instance_Uniforms :: struct #packed {
	model: la.Matrix4x4f32,
	view: la.Matrix4x4f32,
	proj: la.Matrix4x4f32,
}

RVertex :: struct #packed {
	position: [3]f32,
	color: [3]f32,
	uv: [2]f32,
}

VERTICES := [?]RVertex {
	{ { -0.5, 0.0, -0.5 }, { 1.0, 0.0, 0.0 }, { 0.0, 0.0 } },
	{ {  0.5, 0.0, -0.5 }, { 0.0, 1.0, 0.0 }, { 1.0, 0.0 } },
	{ { -0.5, 0.0,  0.5 }, { 0.0, 0.0, 1.0 }, { 0.0, 1.0 } },
	{ {  0.5, 0.0,  0.5 }, { 0.0, 1.0, 0.0 }, { 1.0, 1.0 } },
}

INDICES := [?]u16 {
	0, 1, 2,
	2, 3, 1,
}

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

	ui.init(&ui_context)
	ui_context.text_width = ui.default_atlas_text_width
	ui_context.text_height = ui.default_atlas_text_height

	glfw.SetWindowSizeCallback(window, proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		
		// general_state_uniforms.aspect_rateo = (f32)(width) / (f32)(height)
		renderer.resize_surface(&r)
	})
	glfw.SetMouseButtonCallback(window, proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
		context = runtime.default_context()
		mouse_x, mouse_y := glfw.GetCursorPos(window)

		ui_button: ui.Mouse
		switch button {
		case glfw.MOUSE_BUTTON_LEFT:
			ui_button = .LEFT
		case glfw.MOUSE_BUTTON_RIGHT:
			ui_button = .RIGHT
		case glfw.MOUSE_BUTTON_MIDDLE:
			ui_button = .MIDDLE
		case:
			return
		}

		if action == glfw.PRESS {
			ui.input_mouse_down(&ui_context, (i32)(mouse_x), (i32)(mouse_y), ui_button)
		} else {
			ui.input_mouse_up(&ui_context, (i32)(mouse_x), (i32)(mouse_y), ui_button)
		}
	})

	assert(renderer.create(&r, renderer.Descriptor {
		window = window,
		ui_context = &ui_context,
		clear_color = wgpu.Color { 0.1, 0.2, 0.3, 1.0 },
	}) == nil, "Could not initialize the renderer")
	defer renderer.destroy(&r)
	
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

		mouse_x, mouse_y := glfw.GetCursorPos(window)
		ui.input_mouse_move(&ui_context, (i32)(mouse_x), (i32)(mouse_y))

		ui.begin(&ui_context)
		if ui.window(&ui_context, "Window", ui.Rect { 0, 0, 320, 240, }) {
			if ui.Result.SUBMIT in ui.button(&ui_context, "BUTTON") {
				ui.label(&ui_context, "Pressed")
			}
		} else {
			glfw.SetWindowShouldClose(window, true)
		}
		ui.end(&ui_context)
		
		duration := time.tick_since(now)
		now = time.tick_now()
		
		fps := 1000.0 / time.duration_milliseconds(duration)
		new_window_title := fmt.ctprintf("Window - Frame: %v - Fps: %f", duration, fps)

		glfw.SetWindowTitle(window, new_window_title)

		renderer.begin_frame(&r)
		renderer.end_frame(r)
		renderer.render_ui(&r)

		renderer.present(r)
	}

	for !wgpu.DevicePoll(r.core.device, false, nil) {
		thread.yield()
	}
}
