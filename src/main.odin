package main

import "core:mem"
import "core:log"
import os "core:os/os2"
import "vendor:glfw"
import "vendor:stb/image"
import "shared:wgpu"
import "project:renderer"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	glfw.Init()
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	window := glfw.CreateWindow(640, 480, "Window", nil, nil)
	defer glfw.DestroyWindow(window)

	core: renderer.Renderer_Core
	assert(renderer.renderercore_create(&core, renderer.Renderer_Core_Descriptor {
		debug = false,
		validation = true,
		trace = false,
		features = {
			.Multi_Draw_Indirect,
			.Texture_Binding_Array,
			.Partially_Bound_Binding_Array,
		},
		logger = context.logger,
		window_handle = window,
	}) == nil)
	defer renderer.renderercore_destroy(&core)

	renderer.renderercore_configure_surface(&core)

	atlas: renderer.Multi_Texture_Atlas
	renderer.multitextureatlas_create(&atlas, renderer.Multi_Texture_Atlas_Descriptor {
		texture_format = .Rgba8_Unorm,
		textures_size = { 4098, 4098 },
		max_texture_count = 64,
		pixel_size = 4,
		border_size = 2,
	}, &core)

	mech3_file, _ := os.read_entire_file("res/textures/mech3.png", context.temp_allocator)
	size: [2]i32
	channels: i32
	mech3_image := image.load_from_memory(
		raw_data(mech3_file),
		cast(i32)len(mech3_file),
		&size.x,
		&size.y,
		&channels,
		4,
	)
	defer image.image_free(mech3_image)
	assert(channels == 4)

	mech3_data := mem.slice_ptr(mech3_image, cast(int)(size.x * size.y * channels))
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })
	renderer.multitextureatlas_add_texture(&atlas, mech3_data, { cast(u32)size.x, cast(u32)size.y })

	renderer.multitextureatlas_upload_pending(&atlas)

	for i in 0..=11 {
		log.info(i, renderer.multitextureatlas_get_texture_absolute_position(atlas, cast(renderer.Multi_Texture_Atlas_Texture_Id)i))
	}

	for !glfw.WindowShouldClose(window) {
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}

		surface_texture, _ := wgpu.surface_get_current_texture(core.surface)
		defer wgpu.surface_texture_release(surface_texture)
		if surface_texture.status != .Success_Optimal && surface_texture.status != .Success_Suboptimal {
			continue
		}
		surface_view := wgpu.texture_create_view(surface_texture.texture)
		defer wgpu.texture_view_release(surface_view)

		encoder := wgpu.device_create_command_encoder(core.device)

		render_pass := wgpu.command_encoder_begin_render_pass(encoder, wgpu.Render_Pass_Descriptor {
			color_attachments = {
				wgpu.Render_Pass_Color_Attachment {
					view = surface_view,
					ops = wgpu.Operations(wgpu.Color) {
						load = .Clear,
						store = .Store,
						clear_value = wgpu.Color { 0, 0, 0, 1 },
					},
				},
			},
		})
		wgpu.render_pass_end(render_pass)
		wgpu.render_pass_release(render_pass)

		command_buffer := wgpu.command_encoder_finish(encoder)
		wgpu.command_encoder_release(encoder)
		defer wgpu.command_buffer_release(command_buffer)

		wgpu.queue_submit(core.queue, command_buffer)

		for {
			res, _ := wgpu.device_poll(core.device, true)
			if res {
				break
			}
		}

		wgpu.surface_present(core.surface)
		glfw.PollEvents()
	}
}
