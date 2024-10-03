package renderer

import "vendor:wgpu"
// import "vendor:glfw"
import ui "vendor:microui"

begin_frame :: proc(renderer: ^Renderer) {
	renderer.frame.surface_texture = wgpu.SurfaceGetCurrentTexture(renderer.core.surface)
	// window_width, window_heigth := glfw.GetWindowSize(renderer.external.window)

	// wgpu.QueueWriteBuffer(
	// 	renderer.core.queue,
	// 	renderer.resources.buffers[.Uniform_Draw_Command_Application],
	// 	0,
	// 	&Draw_Command_Application_Uniform {
	// 		time = (f32)(glfw.GetTime()),
	// 		viewport_size = { (u32)(window_width), (u32)(window_heigth) },
	// 	},
	// 	size_of(Draw_Command_Application_Uniform),
	// )

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
			},
		},
	)
}

end_frame :: proc(renderer: Renderer) {
	wgpu.RenderPassEncoderEnd(renderer.frame.render_pass)
	wgpu.RenderPassEncoderRelease(renderer.frame.render_pass)

	command_buffer := wgpu.CommandEncoderFinish(renderer.frame.command_encoder)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.CommandEncoderRelease(renderer.frame.command_encoder)

	wgpu.QueueSubmit(renderer.core.queue, []wgpu.CommandBuffer { command_buffer })
}

present :: proc(renderer: Renderer) {
	wgpu.SurfacePresent(renderer.core.surface)
	wgpu.TextureRelease(renderer.frame.surface_texture.texture)
}

render_ui :: proc(renderer: ^Renderer) {
	@static vertices: [UI_MAX_VERTICES_COUNT]MicroUI_Vertex
	@static indices: [UI_MAX_INDICES_COUNT]u16
	vertex_count := 0
	index_count := 0

	ui_command: ^ui.Command
	for variant in ui.next_command_iterator(renderer.external.ui_context, &ui_command) {
		#partial switch cmd in variant {
		case ^ui.Command_Rect:
			vertices[vertex_count] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x),
					(f32)(cmd.rect.y),
					0.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0, 
					(f32)(cmd.color.a) / 255.0, 
				},
			}
			vertices[vertex_count + 1] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x + cmd.rect.w),
					(f32)(cmd.rect.y),
					0.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0, 
					(f32)(cmd.color.a) / 255.0, 
				},
			}
			vertices[vertex_count + 2] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x + cmd.rect.w),
					(f32)(cmd.rect.y + cmd.rect.h),
					0.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0, 
					(f32)(cmd.color.a) / 255.0, 
				},
			}
			vertices[vertex_count + 3] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x),
					(f32)(cmd.rect.y + cmd.rect.h),
					0.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0, 
					(f32)(cmd.color.a) / 255.0, 
				},
			}

			indices[index_count] = (u16)(vertex_count)
			indices[index_count + 1] = (u16)(vertex_count + 1)
			indices[index_count + 2] = (u16)(vertex_count + 2)
			indices[index_count + 3] = (u16)(vertex_count)
			indices[index_count + 4] = (u16)(vertex_count + 2)
			indices[index_count + 5] = (u16)(vertex_count + 3)

			vertex_count += 4
			index_count += 6

		case ^ui.Command_Icon:
			vertices[vertex_count] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x),
					(f32)(cmd.rect.y),
					0.0,
				},
				uv = {
					(f32)(ui.default_atlas[cmd.id].x) / ui.DEFAULT_ATLAS_WIDTH,
					(f32)(ui.default_atlas[cmd.id].y) / ui.DEFAULT_ATLAS_HEIGHT,
					1.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0,
					(f32)(cmd.color.a) / 255.0,
				},
			}
			vertices[vertex_count + 1] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x + cmd.rect.w),
					(f32)(cmd.rect.y),
					0.0,
				},
				uv = {
					(f32)(ui.default_atlas[cmd.id].x + ui.default_atlas[cmd.id].w) / ui.DEFAULT_ATLAS_WIDTH,
					(f32)(ui.default_atlas[cmd.id].y) / ui.DEFAULT_ATLAS_HEIGHT,
					1.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0,
					(f32)(cmd.color.a) / 255.0,
				},
			}
			vertices[vertex_count + 2] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x + cmd.rect.w),
					(f32)(cmd.rect.y + cmd.rect.h),
					0.0,
				},
				uv = {
					(f32)(ui.default_atlas[cmd.id].x + ui.default_atlas[cmd.id].w) / ui.DEFAULT_ATLAS_WIDTH,
					(f32)(ui.default_atlas[cmd.id].y + ui.default_atlas[cmd.id].h) / ui.DEFAULT_ATLAS_HEIGHT,
					1.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0,
					(f32)(cmd.color.a) / 255.0,
				},
			}
			vertices[vertex_count + 3] = MicroUI_Vertex {
				position = { 
					(f32)(cmd.rect.x),
					(f32)(cmd.rect.y + cmd.rect.h),
					0.0,
				},
				uv = {
					(f32)(ui.default_atlas[cmd.id].x) / ui.DEFAULT_ATLAS_WIDTH,
					(f32)(ui.default_atlas[cmd.id].y + ui.default_atlas[cmd.id].h) / ui.DEFAULT_ATLAS_HEIGHT,
					1.0,
				},
				color = {
					(f32)(cmd.color.r) / 255.0,
					(f32)(cmd.color.g) / 255.0,
					(f32)(cmd.color.b) / 255.0,
					(f32)(cmd.color.a) / 255.0,
				},
			}

			indices[index_count] = (u16)(vertex_count)
			indices[index_count + 1] = (u16)(vertex_count + 1)
			indices[index_count + 2] = (u16)(vertex_count + 2)
			indices[index_count + 3] = (u16)(vertex_count)
			indices[index_count + 4] = (u16)(vertex_count + 2)
			indices[index_count + 5] = (u16)(vertex_count + 3)

			vertex_count += 4
			index_count += 6

		case ^ui.Command_Text:
			letter_height := renderer.external.ui_context.text_height(cmd.font)

			current_width: i32 = 0
			for rune in cmd.str {
				if rune < '0' || rune > 127 {
					continue
				}

				rune_rect := ui.default_atlas[ui.DEFAULT_ATLAS_FONT + (int)(rune)]

				vertices[vertex_count] = MicroUI_Vertex {
					position = {
						(f32)(cmd.pos.x + current_width),
						(f32)(cmd.pos.y),
						0.0,
					},
					uv = {
						(f32)(rune_rect.x) / ui.DEFAULT_ATLAS_WIDTH,
						(f32)(rune_rect.y) / ui.DEFAULT_ATLAS_HEIGHT,
						1.0,
					},
					color = {
						(f32)(cmd.color.r) / 255.0,
						(f32)(cmd.color.g) / 255.0,
						(f32)(cmd.color.b) / 255.0,
						(f32)(cmd.color.a) / 255.0,
					},
				}
				vertices[vertex_count + 1] = MicroUI_Vertex {
					position = {
						(f32)(cmd.pos.x + current_width + rune_rect.w),
						(f32)(cmd.pos.y),
						0.0,
					},
					uv = {
						(f32)(rune_rect.x + rune_rect.w) / ui.DEFAULT_ATLAS_WIDTH,
						(f32)(rune_rect.y) / ui.DEFAULT_ATLAS_HEIGHT,
						1.0,
					},
					color = {
						(f32)(cmd.color.r) / 255.0,
						(f32)(cmd.color.g) / 255.0,
						(f32)(cmd.color.b) / 255.0,
						(f32)(cmd.color.a) / 255.0,
					},
				}
				vertices[vertex_count + 2] = MicroUI_Vertex {
					position = { 
						(f32)(cmd.pos.x + current_width + rune_rect.w),
						(f32)(cmd.pos.y + letter_height),
						0.0,
					},
					uv = {
						(f32)(rune_rect.x + rune_rect.w) / ui.DEFAULT_ATLAS_WIDTH,
						(f32)(rune_rect.y + rune_rect.h) / ui.DEFAULT_ATLAS_HEIGHT,
						1.0,
					},
					color = {
						(f32)(cmd.color.r) / 255.0,
						(f32)(cmd.color.g) / 255.0,
						(f32)(cmd.color.b) / 255.0,
						(f32)(cmd.color.a) / 255.0,
					},
				}
				vertices[vertex_count + 3] = MicroUI_Vertex {
					position = { 
						(f32)(cmd.pos.x + current_width),
						(f32)(cmd.pos.y + letter_height),
						0.0,
					},
					uv = {
						(f32)(rune_rect.x) / ui.DEFAULT_ATLAS_WIDTH,
						(f32)(rune_rect.y + rune_rect.h) / ui.DEFAULT_ATLAS_HEIGHT,
						1.0,
					},
					color = {
						(f32)(cmd.color.r) / 255.0,
						(f32)(cmd.color.g) / 255.0,
						(f32)(cmd.color.b) / 255.0,
						(f32)(cmd.color.a) / 255.0,
					},
				}

				indices[index_count] = (u16)(vertex_count)
				indices[index_count + 1] = (u16)(vertex_count + 1)
				indices[index_count + 2] = (u16)(vertex_count + 2)
				indices[index_count + 3] = (u16)(vertex_count)
				indices[index_count + 4] = (u16)(vertex_count + 2)
				indices[index_count + 5] = (u16)(vertex_count + 3)

				vertex_count += 4
				index_count += 6
				current_width += rune_rect.w
			}
		}
	}

	// wgpu.QueueWriteBuffer(
	// 	renderer.core.queue,
	// 	renderer.resources.buffers[.Vertex_MicroUI],
	// 	0,
	// 	&vertices[0],
	// 	(uint)(vertex_count * size_of(MicroUI_Vertex)),
	// )
	// wgpu.QueueWriteBuffer(
	// 	renderer.core.queue,
	// 	renderer.resources.buffers[.Index_MicroUI],
	// 	0,
	// 	&indices[0],
	// 	(uint)(index_count * size_of(u16)),
	// )

	depth_view := wgpu.TextureCreateView(renderer.resources.dynamic_textures[.Surface_Depth_Buffer].handle)
	surface_view := wgpu.TextureCreateView(renderer.frame.surface_texture.texture)
	defer wgpu.TextureViewRelease(depth_view)
	defer wgpu.TextureViewRelease(surface_view)

	command_encoder := wgpu.DeviceCreateCommandEncoder(
		renderer.core.device,
		&wgpu.CommandEncoderDescriptor {
			label = "UI Frame Command Encoder",
		},
	)

	render_pass := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "UI Surface Render Pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = surface_view,
				loadOp = .Load,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
		},
	)

	// ui_vertices_size := wgpu.BufferGetSize(renderer.resources.buffers[.Vertex_MicroUI])
	// ui_indices_size := wgpu.BufferGetSize(renderer.resources.buffers[.Index_MicroUI])
	// wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.resources.pipelines[.MicroUI_To_Rendertarget])
	// wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, renderer.resources.bindgroups[.Draw_Command])
	// wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, renderer.resources.bindgroups[.Textures])
	// wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, renderer.resources.buffers[.Vertex_MicroUI], 0, ui_vertices_size)
	// wgpu.RenderPassEncoderSetIndexBuffer(render_pass, renderer.resources.buffers[.Index_MicroUI], .Uint16, 0, ui_indices_size)
	// wgpu.RenderPassEncoderDrawIndexed(render_pass, (u32)(index_count), 1, 0, 0, 0)
	
	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.CommandEncoderRelease(command_encoder)

	wgpu.QueueSubmit(renderer.core.queue, []wgpu.CommandBuffer { command_buffer })
}

