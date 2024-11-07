package renderer

import "vendor:wgpu"
import "vendor:glfw"
import la "core:math/linalg"

prepare_test_draw :: proc(renderer: ^Renderer) {
	Object :: struct #packed {
		model: Model,
		_padding: [8]byte,
		object_matrix: matrix[4,4]f32,
	}
	Draw_Call_Info :: struct {
		camera: u32,
		object_offset: u32,
		model_id: u32,
	}
	Camera :: struct {
		view: matrix[4,4]f32,
		proj: matrix[4,4]f32,
	}

	time := glfw.GetTime()
	width, height := glfw.GetWindowSize(renderer.external.window)

	wgpu.QueueWriteBuffer(
		renderer.core.queue,
		renderer.resources.static_buffers[.Application_State],
		0,
		&Application_State {
			time = (f32)(time),
			viewport_size = [2]u32 { (u32)(width), (u32)(height) },
		},
		size_of(Application_State),
	)
	wgpu.QueueWriteBuffer(
		renderer.core.queue,
		renderer.resources.mirrored_buffers[.Objects].handle,
		0,
		&Object {
			model = 0,
			object_matrix = la.matrix4_translate_f32({ 0.0, -4.0, 0.0 }) * la.matrix4_rotate_f32((f32)(time) * 0.3, { 0.0, 1.0, 0.0 }) * la.matrix4_scale_f32({ 4.0, 4.0, 4.0}) * la.identity(matrix[4,4]f32),
		},
		size_of(Object),
	)
	// wgpu.QueueWriteBuffer(
	// 	renderer.core.queue,
	// 	renderer.resources.dynamic_buffers[.Draw_Call_Info].handle,
	// 	0,
	// 	&Draw_Call_Info {},
	// 	size_of(Draw_Call_Info),
	// )
	view := la.matrix4_look_at_f32({ 0.0, 0.0, -5.0 }, { 0.0, 0.0, 0.0 }, { 0.0, 1.0, 0.0 })
	proj := la.matrix4_perspective_f32(la.to_radians((f32)(90)), (f32)(width) / (f32)(height), 0.001, 1000.0)
	c := Camera {
		view = view,
		proj = proj,
	}
	wgpu.QueueWriteBuffer(
		renderer.core.queue,
		renderer.resources.dynamic_buffers[.Cameras].handle,
		0,
		&c,
		size_of(Camera),
	)

	// wgputickerthread_sync(&renderer.ticker_thread)
}

begin_frame :: proc(renderer: ^Renderer) {
	wgputickerthread_begin_frame(&renderer.ticker_thread)

	prepare_test_draw(renderer)
	resources_recreate_volatile_bindgroups(renderer)
	renderer.frame.surface_texture = wgpu.SurfaceGetCurrentTexture(renderer.core.surface)

	depth_view := wgpu.TextureCreateView(renderer.resources.dynamic_textures[.Surface_Depth_Buffer].handle)
	surface_view := wgpu.TextureCreateView(renderer.frame.surface_texture.texture)
	defer wgpu.TextureViewRelease(depth_view)
	defer wgpu.TextureViewRelease(surface_view)

	renderer.frame.command_encoder = wgpu.DeviceCreateCommandEncoder(
		renderer.core.device,
		&wgpu.CommandEncoderDescriptor {
			label = "Frame Command Encoder",
		},
	)

	renderer.frame.render_pass = wgpu.CommandEncoderBeginRenderPass(
		renderer.frame.command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "Surface Render Pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = surface_view,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = renderer.properties.clear_color,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
			depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment {
				view = depth_view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthReadOnly = false,
				depthClearValue = 1.0,
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(renderer.frame.render_pass, renderer.resources.pipelines[.Obj_Draw])
	wgpu.RenderPassEncoderSetBindGroup(renderer.frame.render_pass, 0, renderer.resources.bindgroups[.Data])
	wgpu.RenderPassEncoderSetBindGroup(renderer.frame.render_pass, 1, renderer.resources.bindgroups[.Draw], []u32 { 0 })
	wgpu.RenderPassEncoderSetBindGroup(renderer.frame.render_pass, 2, renderer.resources.bindgroups[.Utilities])
	wgpu.RenderPassEncoderDraw(renderer.frame.render_pass, 720, 1, 0, 0)
}

end_frame :: proc(renderer: ^Renderer) {
	wgpu.RenderPassEncoderEnd(renderer.frame.render_pass)
	wgpu.RenderPassEncoderRelease(renderer.frame.render_pass)

	command_buffer := wgpu.CommandEncoderFinish(renderer.frame.command_encoder)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.CommandEncoderRelease(renderer.frame.command_encoder)

	wgpu.QueueSubmit(renderer.core.queue, []wgpu.CommandBuffer { command_buffer })

	wgputickerthread_end_frame(&renderer.ticker_thread)
}

present :: proc(renderer: ^Renderer) {
	wgpu.SurfacePresent(renderer.core.surface)
	wgpu.TextureRelease(renderer.frame.surface_texture.texture)
	wgputickerthread_sync(&renderer.ticker_thread)
}

// render_ui :: proc(renderer: ^Renderer) {
// 	@static vertices: [UI_MAX_VERTICES_COUNT]MicroUI_Vertex
// 	@static indices: [UI_MAX_INDICES_COUNT]u16
// 	vertex_count := 0
// 	index_count := 0

// 	ui_command: ^ui.Command
// 	for variant in ui.next_command_iterator(renderer.external.ui_context, &ui_command) {
// 		#partial switch cmd in variant {
// 		case ^ui.Command_Rect:
// 			vertices[vertex_count] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x),
// 					(f32)(cmd.rect.y),
// 					0.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0, 
// 					(f32)(cmd.color.a) / 255.0, 
// 				},
// 			}
// 			vertices[vertex_count + 1] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x + cmd.rect.w),
// 					(f32)(cmd.rect.y),
// 					0.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0, 
// 					(f32)(cmd.color.a) / 255.0, 
// 				},
// 			}
// 			vertices[vertex_count + 2] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x + cmd.rect.w),
// 					(f32)(cmd.rect.y + cmd.rect.h),
// 					0.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0, 
// 					(f32)(cmd.color.a) / 255.0, 
// 				},
// 			}
// 			vertices[vertex_count + 3] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x),
// 					(f32)(cmd.rect.y + cmd.rect.h),
// 					0.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0, 
// 					(f32)(cmd.color.a) / 255.0, 
// 				},
// 			}

// 			indices[index_count] = (u16)(vertex_count)
// 			indices[index_count + 1] = (u16)(vertex_count + 1)
// 			indices[index_count + 2] = (u16)(vertex_count + 2)
// 			indices[index_count + 3] = (u16)(vertex_count)
// 			indices[index_count + 4] = (u16)(vertex_count + 2)
// 			indices[index_count + 5] = (u16)(vertex_count + 3)

// 			vertex_count += 4
// 			index_count += 6

// 		case ^ui.Command_Icon:
// 			vertices[vertex_count] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x),
// 					(f32)(cmd.rect.y),
// 					0.0,
// 				},
// 				uv = {
// 					(f32)(ui.default_atlas[cmd.id].x) / ui.DEFAULT_ATLAS_WIDTH,
// 					(f32)(ui.default_atlas[cmd.id].y) / ui.DEFAULT_ATLAS_HEIGHT,
// 					1.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0,
// 					(f32)(cmd.color.a) / 255.0,
// 				},
// 			}
// 			vertices[vertex_count + 1] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x + cmd.rect.w),
// 					(f32)(cmd.rect.y),
// 					0.0,
// 				},
// 				uv = {
// 					(f32)(ui.default_atlas[cmd.id].x + ui.default_atlas[cmd.id].w) / ui.DEFAULT_ATLAS_WIDTH,
// 					(f32)(ui.default_atlas[cmd.id].y) / ui.DEFAULT_ATLAS_HEIGHT,
// 					1.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0,
// 					(f32)(cmd.color.a) / 255.0,
// 				},
// 			}
// 			vertices[vertex_count + 2] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x + cmd.rect.w),
// 					(f32)(cmd.rect.y + cmd.rect.h),
// 					0.0,
// 				},
// 				uv = {
// 					(f32)(ui.default_atlas[cmd.id].x + ui.default_atlas[cmd.id].w) / ui.DEFAULT_ATLAS_WIDTH,
// 					(f32)(ui.default_atlas[cmd.id].y + ui.default_atlas[cmd.id].h) / ui.DEFAULT_ATLAS_HEIGHT,
// 					1.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0,
// 					(f32)(cmd.color.a) / 255.0,
// 				},
// 			}
// 			vertices[vertex_count + 3] = MicroUI_Vertex {
// 				position = { 
// 					(f32)(cmd.rect.x),
// 					(f32)(cmd.rect.y + cmd.rect.h),
// 					0.0,
// 				},
// 				uv = {
// 					(f32)(ui.default_atlas[cmd.id].x) / ui.DEFAULT_ATLAS_WIDTH,
// 					(f32)(ui.default_atlas[cmd.id].y + ui.default_atlas[cmd.id].h) / ui.DEFAULT_ATLAS_HEIGHT,
// 					1.0,
// 				},
// 				color = {
// 					(f32)(cmd.color.r) / 255.0,
// 					(f32)(cmd.color.g) / 255.0,
// 					(f32)(cmd.color.b) / 255.0,
// 					(f32)(cmd.color.a) / 255.0,
// 				},
// 			}

// 			indices[index_count] = (u16)(vertex_count)
// 			indices[index_count + 1] = (u16)(vertex_count + 1)
// 			indices[index_count + 2] = (u16)(vertex_count + 2)
// 			indices[index_count + 3] = (u16)(vertex_count)
// 			indices[index_count + 4] = (u16)(vertex_count + 2)
// 			indices[index_count + 5] = (u16)(vertex_count + 3)

// 			vertex_count += 4
// 			index_count += 6

// 		case ^ui.Command_Text:
// 			letter_height := renderer.external.ui_context.text_height(cmd.font)

// 			current_width: i32 = 0
// 			for rune in cmd.str {
// 				if rune < '0' || rune > 127 {
// 					continue
// 				}

// 				rune_rect := ui.default_atlas[ui.DEFAULT_ATLAS_FONT + (int)(rune)]

// 				vertices[vertex_count] = MicroUI_Vertex {
// 					position = {
// 						(f32)(cmd.pos.x + current_width),
// 						(f32)(cmd.pos.y),
// 						0.0,
// 					},
// 					uv = {
// 						(f32)(rune_rect.x) / ui.DEFAULT_ATLAS_WIDTH,
// 						(f32)(rune_rect.y) / ui.DEFAULT_ATLAS_HEIGHT,
// 						1.0,
// 					},
// 					color = {
// 						(f32)(cmd.color.r) / 255.0,
// 						(f32)(cmd.color.g) / 255.0,
// 						(f32)(cmd.color.b) / 255.0,
// 						(f32)(cmd.color.a) / 255.0,
// 					},
// 				}
// 				vertices[vertex_count + 1] = MicroUI_Vertex {
// 					position = {
// 						(f32)(cmd.pos.x + current_width + rune_rect.w),
// 						(f32)(cmd.pos.y),
// 						0.0,
// 					},
// 					uv = {
// 						(f32)(rune_rect.x + rune_rect.w) / ui.DEFAULT_ATLAS_WIDTH,
// 						(f32)(rune_rect.y) / ui.DEFAULT_ATLAS_HEIGHT,
// 						1.0,
// 					},
// 					color = {
// 						(f32)(cmd.color.r) / 255.0,
// 						(f32)(cmd.color.g) / 255.0,
// 						(f32)(cmd.color.b) / 255.0,
// 						(f32)(cmd.color.a) / 255.0,
// 					},
// 				}
// 				vertices[vertex_count + 2] = MicroUI_Vertex {
// 					position = { 
// 						(f32)(cmd.pos.x + current_width + rune_rect.w),
// 						(f32)(cmd.pos.y + letter_height),
// 						0.0,
// 					},
// 					uv = {
// 						(f32)(rune_rect.x + rune_rect.w) / ui.DEFAULT_ATLAS_WIDTH,
// 						(f32)(rune_rect.y + rune_rect.h) / ui.DEFAULT_ATLAS_HEIGHT,
// 						1.0,
// 					},
// 					color = {
// 						(f32)(cmd.color.r) / 255.0,
// 						(f32)(cmd.color.g) / 255.0,
// 						(f32)(cmd.color.b) / 255.0,
// 						(f32)(cmd.color.a) / 255.0,
// 					},
// 				}
// 				vertices[vertex_count + 3] = MicroUI_Vertex {
// 					position = { 
// 						(f32)(cmd.pos.x + current_width),
// 						(f32)(cmd.pos.y + letter_height),
// 						0.0,
// 					},
// 					uv = {
// 						(f32)(rune_rect.x) / ui.DEFAULT_ATLAS_WIDTH,
// 						(f32)(rune_rect.y + rune_rect.h) / ui.DEFAULT_ATLAS_HEIGHT,
// 						1.0,
// 					},
// 					color = {
// 						(f32)(cmd.color.r) / 255.0,
// 						(f32)(cmd.color.g) / 255.0,
// 						(f32)(cmd.color.b) / 255.0,
// 						(f32)(cmd.color.a) / 255.0,
// 					},
// 				}

// 				indices[index_count] = (u16)(vertex_count)
// 				indices[index_count + 1] = (u16)(vertex_count + 1)
// 				indices[index_count + 2] = (u16)(vertex_count + 2)
// 				indices[index_count + 3] = (u16)(vertex_count)
// 				indices[index_count + 4] = (u16)(vertex_count + 2)
// 				indices[index_count + 5] = (u16)(vertex_count + 3)

// 				vertex_count += 4
// 				index_count += 6
// 				current_width += rune_rect.w
// 			}
// 		}
// 	}

// 	// wgpu.QueueWriteBuffer(
// 	// 	renderer.core.queue,
// 	// 	renderer.resources.buffers[.Vertex_MicroUI],
// 	// 	0,
// 	// 	&vertices[0],
// 	// 	(uint)(vertex_count * size_of(MicroUI_Vertex)),
// 	// )
// 	// wgpu.QueueWriteBuffer(
// 	// 	renderer.core.queue,
// 	// 	renderer.resources.buffers[.Index_MicroUI],
// 	// 	0,
// 	// 	&indices[0],
// 	// 	(uint)(index_count * size_of(u16)),
// 	// )

// 	depth_view := wgpu.TextureCreateView(renderer.resources.dynamic_textures[.Surface_Depth_Buffer].handle)
// 	surface_view := wgpu.TextureCreateView(renderer.frame.surface_texture.texture)
// 	defer wgpu.TextureViewRelease(depth_view)
// 	defer wgpu.TextureViewRelease(surface_view)

// 	command_encoder := wgpu.DeviceCreateCommandEncoder(
// 		renderer.core.device,
// 		&wgpu.CommandEncoderDescriptor {
// 			label = "UI Frame Command Encoder",
// 		},
// 	)

// 	render_pass := wgpu.CommandEncoderBeginRenderPass(
// 		command_encoder,
// 		&wgpu.RenderPassDescriptor {
// 			label = "UI Surface Render Pass",
// 			colorAttachmentCount = 1,
// 			colorAttachments = &wgpu.RenderPassColorAttachment {
// 				view = surface_view,
// 				loadOp = .Load,
// 				storeOp = .Store,
// 				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
// 			},
// 		},
// 	)

// 	// ui_vertices_size := wgpu.BufferGetSize(renderer.resources.buffers[.Vertex_MicroUI])
// 	// ui_indices_size := wgpu.BufferGetSize(renderer.resources.buffers[.Index_MicroUI])
// 	// wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.resources.pipelines[.MicroUI_To_Rendertarget])
// 	// wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, renderer.resources.bindgroups[.Draw_Command])
// 	// wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, renderer.resources.bindgroups[.Textures])
// 	// wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, renderer.resources.buffers[.Vertex_MicroUI], 0, ui_vertices_size)
// 	// wgpu.RenderPassEncoderSetIndexBuffer(render_pass, renderer.resources.buffers[.Index_MicroUI], .Uint16, 0, ui_indices_size)
// 	// wgpu.RenderPassEncoderDrawIndexed(render_pass, (u32)(index_count), 1, 0, 0, 0)
	
// 	wgpu.RenderPassEncoderEnd(render_pass)
// 	wgpu.RenderPassEncoderRelease(render_pass)

// 	command_buffer := wgpu.CommandEncoderFinish(command_encoder)
// 	defer wgpu.CommandBufferRelease(command_buffer)

// 	wgpu.CommandEncoderRelease(command_encoder)

// 	wgpu.QueueSubmit(renderer.core.queue, []wgpu.CommandBuffer { command_buffer })
// }

