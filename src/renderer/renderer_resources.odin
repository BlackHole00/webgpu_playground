#+private
package renderer

import "core:math"
import "core:log"
import "vendor:wgpu"
import "shared:utils"
import wgputils "wgpu"

DEPTH_BUFFER_FORMAT :: wgpu.TextureFormat.Depth24Plus
UI_MAX_QUADS_COUNT :: 1024
UI_MAX_VERTICES_COUNT :: 4 * UI_MAX_QUADS_COUNT
UI_MAX_INDICES_COUNT :: 6 * UI_MAX_QUADS_COUNT

VERTEX_LAYOUTS := [Vertex_Layout_Type]wgpu.VertexBufferLayout {
	.None = wgpu.VertexBufferLayout {
		arrayStride = 0,
		stepMode = .Vertex,
		attributeCount = 0,
	},
	.Basic = wgpu.VertexBufferLayout {
		arrayStride = size_of(Basic_Vertex),
		stepMode = .Vertex,
		attributeCount = 3,
		attributes = raw_data([]wgpu.VertexAttribute {
			{ format = .Float32x3, offset = 0, shaderLocation = 0 },
			{ format = .Float32x2, offset = size_of([3]f32), shaderLocation = 1 },
			{ format = .Float32x3, offset = size_of([3]f32) + size_of([2]f32), shaderLocation = 2},
		}),
	},
	.MicroUI = wgpu.VertexBufferLayout {
		arrayStride = size_of(MicroUI_Vertex),
		stepMode = .Vertex,
		attributeCount = 3,
		attributes = raw_data([]wgpu.VertexAttribute {
			{ format = .Float32x3, offset = 0, shaderLocation = 0 },
			{ format = .Float32x3, offset = size_of([3]f32), shaderLocation = 1 },
			{ format = .Float32x4, offset = size_of([3]f32) + size_of([3]f32), shaderLocation = 2},
		}),
	},
}
#assert(size_of(Basic_Vertex) == size_of([3]f32) + size_of([2]f32) + size_of([3]f32))
#assert(size_of(MicroUI_Vertex) == size_of([3]f32) + size_of([3]f32) + size_of([4]f32))

renderer_get_static_buffer :: proc(renderer: Renderer, type: Static_Buffer_Type) -> wgpu.Buffer {
	return renderer.resources.static_buffers[type]
}
renderer_set_static_buffer :: proc(renderer: ^Renderer, type: Static_Buffer_Type, buffer: wgpu.Buffer) {
	renderer.resources.static_buffers[type] = buffer
}
renderer_get_dynamic_buffer :: proc(renderer: ^Renderer, type: Dynamic_Buffer_Type) -> ^wgputils.Dynamic_Buffer {
	return &renderer.resources.dynamic_buffers[type]
}
renderer_get_mirrored_buffer :: proc(renderer: ^Renderer, type: Mirrored_Buffer_Type) -> ^wgputils.Mirrored_Buffer {
	return &renderer.resources.mirrored_buffers[type]
}

BINDGROUP_LAYOUT_DESCRIPTORS := [Bindgroup_Type]wgpu.BindGroupLayoutDescriptor {
	.Draw_Command = wgpu.BindGroupLayoutDescriptor {
		label = "Application bind group layout",
		entryCount = 2,
		entries = raw_data([]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = (u64)(math.next_power_of_two(size_of(Draw_Command_Application_Uniform))),
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(Draw_Command_Instance_Uniform),
				},
			},
		}),
	},
	.Textures = wgpu.BindGroupLayoutDescriptor {
		label = "Textures bind group layout",
		entryCount = 4,
		entries = raw_data([]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry { // General Texture Atlas
				binding = 0,
				visibility = { .Vertex, .Fragment },
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry { // MicroUI Texture Atlas
				binding = 1,
				visibility = { .Vertex, .Fragment },
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry { // General Sampler
				binding = 2,
				visibility = { .Vertex, .Fragment },
				sampler = wgpu.SamplerBindingLayout {
					type = .Filtering,
				},
			},
			wgpu.BindGroupLayoutEntry { // Pixel Perfect Sampler
				binding = 3,
				visibility = { .Vertex, .Fragment },
				sampler = wgpu.SamplerBindingLayout {
					type = .Filtering,
				},
			},
		}),
	},
}

resources_init :: proc(renderer: ^Renderer) -> (err: Error) {
	defer if err != nil {
		resources_deinit(renderer)
	}

	resources_init_vertex_layouts(renderer)
	if !resources_init_bindgroup_layouts(renderer) {
		log.errorf("Could not init the bindgroup layouts")
		return Common_Error.Bind_Group_Layout_Creation_Failed
	}
	if !resources_init_buffers(renderer) {
		log.errorf("Could not init the buffers")
		return Common_Error.Buffer_Creation_Failed
	}
	if !resources_init_textures(renderer) {
		log.errorf("Could not init the textures")
		return Common_Error.Texture_Creation_Failed
	}
	if !resources_init_samplers(renderer) {
		log.errorf("Could not init the samplers")
		return Common_Error.Sampler_Creation_Failed
	}
	if !resources_init_bindgroups(renderer) {
		log.errorf("Could not init the bing groups")
		return Common_Error.Bind_Group_Creation_Failed
	}
	if !resources_init_pipelines(renderer) {
		log.errorf("Could not init the pipelines")
		return Common_Error.Pipeline_Creation_Failed
	}

	return nil
}

resources_deinit :: proc(renderer: ^Renderer) {
	resources_deinit_buffers(renderer)
	resources_deinit_textures(renderer^)

	for pipeline in renderer.resources.pipelines {
		if pipeline != nil do wgpu.RenderPipelineRelease(pipeline)
	}
	for bindgroup in renderer.resources.bindgroups {
		if bindgroup != nil do wgpu.BindGroupRelease(bindgroup)
	}
	for sampler in renderer.resources.samplers {
		if sampler != nil do wgpu.SamplerRelease(sampler)
	}
	for bindgroup_layout in renderer.resources.bindgroup_layouts {
		if bindgroup_layout != nil do wgpu.BindGroupLayoutRelease(bindgroup_layout)
	}
}

resources_init_vertex_layouts :: proc(renderer: ^Renderer) {
	renderer.resources.vertex_layouts = VERTEX_LAYOUTS
}

resources_init_bindgroup_layouts :: proc(renderer: ^Renderer) -> bool {
	renderer.resources.bindgroup_layouts[.Draw_Command] = wgpu.DeviceCreateBindGroupLayout(
		renderer.core.device,
		&BINDGROUP_LAYOUT_DESCRIPTORS[.Draw_Command],
	)
	renderer.resources.bindgroup_layouts[.Textures] = wgpu.DeviceCreateBindGroupLayout(
		renderer.core.device,
		&BINDGROUP_LAYOUT_DESCRIPTORS[.Textures],
	)

	return utils.typedarray_ensure_all_values_valid(renderer.resources.bindgroup_layouts)
}

// resources_init_textures :: proc(renderer: ^Renderer) -> bool {
// 	window_width, window_heigth := glfw.GetWindowSize(renderer.external.window)

// 	// TODO(Vicix): Actually use a texture atlas
// 	renderer.resources.textures[.General_Atlas] = wgpu.DeviceCreateTexture(
// 		renderer.core.device, 
// 		&wgpu.TextureDescriptor {
// 			label = "General Atlas Texture",
// 			usage = { .TextureBinding, .CopyDst },
// 			dimension = ._2D,
// 			size = { 1, 1, 1 },
// 			format = .RGBA8Unorm,
// 			mipLevelCount = 1,
// 			sampleCount = 1,
// 			viewFormatCount = 1,
// 			viewFormats = raw_data([]wgpu.TextureFormat {
// 				.RGBA8Unorm,
// 			}),
// 		},
// 	)
// 	renderer.resources.textures[.MicroUI_Atlas] = wgpu.DeviceCreateTexture(
// 		renderer.core.device,
// 		&wgpu.TextureDescriptor {
// 			label = "MicroUI Atlas Texture",
// 			usage = { .TextureBinding, .CopyDst },
// 			dimension = ._2D,
// 			size = { ui.DEFAULT_ATLAS_WIDTH, ui.DEFAULT_ATLAS_HEIGHT, 1 },
// 			format = .R8Unorm,
// 			mipLevelCount = 1,
// 			sampleCount = 1,
// 			viewFormatCount = 1,
// 			viewFormats = raw_data([]wgpu.TextureFormat {
// 				.R8Unorm,
// 			}),
// 		},
// 	)
// 	renderer.resources.textures[.Surface_Depth] = wgpu.DeviceCreateTexture(
// 		renderer.core.device,
// 		&wgpu.TextureDescriptor {
// 			label = "Surface Depth",
// 			usage = { .CopySrc, .CopyDst, .RenderAttachment },
// 			dimension = ._2D,
// 			size = { (u32)(window_width), (u32)(window_heigth), 1 },
// 			format = DEPTH_BUFFER_FORMAT,
// 			mipLevelCount = 1,
// 			sampleCount = 1,
// 			viewFormatCount = 1,
// 			viewFormats = raw_data([]wgpu.TextureFormat {
// 				DEPTH_BUFFER_FORMAT,
// 			}),
// 		},
// 	)

// 	if !utils.typedarray_ensure_all_values_valid(renderer.resources.textures) {
// 		return false
// 	}

// 	log.info(ui.DEFAULT_ATLAS_WIDTH, ui.DEFAULT_ATLAS_HEIGHT, len(ui.default_atlas_alpha))
// 	wgpu.QueueWriteTexture(
// 		renderer.core.queue,
// 		&wgpu.ImageCopyTexture {
// 			texture = renderer.resources.textures[.MicroUI_Atlas],
// 			mipLevel = 0,
// 			origin = { 0, 0, 0 },
// 			aspect = .All,
// 		},
// 		&ui.default_atlas_alpha,
// 		len(ui.default_atlas_alpha),
// 		&wgpu.TextureDataLayout {
// 			offset = 0,
// 			bytesPerRow = ui.DEFAULT_ATLAS_WIDTH,
// 			rowsPerImage = ui.DEFAULT_ATLAS_HEIGHT,
// 		},
// 		&wgpu.Extent3D { ui.DEFAULT_ATLAS_WIDTH, ui.DEFAULT_ATLAS_HEIGHT, 1 },
// 	)

// 	return true
// }

resources_init_samplers :: proc(renderer: ^Renderer) -> bool {
	renderer.resources.samplers[.Generic] = wgpu.DeviceCreateSampler(
		renderer.core.device,
		&wgpu.SamplerDescriptor {
			label = "Generic Sampler",
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Linear,
			lodMinClamp = 0.0,
			lodMaxClamp = 1.0,
			compare = .Undefined,
			maxAnisotropy = 1,
		},
	)
	renderer.resources.samplers[.Pixel_Perfect] = wgpu.DeviceCreateSampler(
		renderer.core.device,
		&wgpu.SamplerDescriptor {
			label = "Generic Sampler",
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			addressModeW = .ClampToEdge,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Linear,
			lodMinClamp = 0.0,
			lodMaxClamp = 1.0,
			compare = .Undefined,
			maxAnisotropy = 1,
		},
	)

	return utils.typedarray_ensure_all_values_valid(renderer.resources.samplers)
}

resources_init_bindgroups :: proc(renderer: ^Renderer) -> bool {
	general_atlas_view := wgpu.TextureCreateView(renderer.resources.dynamic_textures[.Texture_Atlas].handle)
	defer wgpu.TextureViewRelease(general_atlas_view)

	renderer.resources.bindgroups[.Draw_Command] = wgpu.DeviceCreateBindGroup(
		renderer.core.device,
		&wgpu.BindGroupDescriptor {
			label = "Draw Command Bind Group",
			layout = renderer.resources.bindgroup_layouts[.Draw_Command],
			entryCount = 2,
			entries = raw_data([]wgpu.BindGroupEntry {
				wgpu.BindGroupEntry {
					binding = 0,
					buffer = renderer.resources.static_buffers[.Uniform_Application_State],
					offset = 0,
					size = (u64)(math.next_power_of_two((size_of(Draw_Command_Application_Uniform)))),
				},
				// TODO(Vicix): Allow for dynamic offsets
				wgpu.BindGroupEntry {
					binding = 1,
					buffer = renderer.resources.dynamic_buffers[.Uniform_Pass_States].handle,
					offset = 0,
					size = size_of(Draw_Command_Instance_Uniform),
				},
			}),
		},
	)
	renderer.resources.bindgroups[.Textures] = wgpu.DeviceCreateBindGroup(
		renderer.core.device,
		&wgpu.BindGroupDescriptor {
			label = "Draw Command Bind Group",
			layout = renderer.resources.bindgroup_layouts[.Textures],
			entryCount = 4,
			entries = raw_data([]wgpu.BindGroupEntry {
				wgpu.BindGroupEntry {
					binding = 0,
					textureView = general_atlas_view,
				},
				wgpu.BindGroupEntry {
					binding = 1,
					textureView = general_atlas_view,
				},
				wgpu.BindGroupEntry {
					binding = 2,
					sampler = renderer.resources.samplers[.Generic],
				},
				wgpu.BindGroupEntry {
					binding = 3,
					sampler = renderer.resources.samplers[.Pixel_Perfect],
				},
			}),
		},
	)

	return renderer.resources.bindgroups[.Draw_Command] != nil &&
		renderer.resources.bindgroup_layouts[.Textures] != nil
}

resources_init_pipelines :: proc(renderer: ^Renderer) -> bool {
	// renderer.resources.pipelines[.MicroUI_To_Rendertarget] = renderpipeline_build(
	// 	renderer,
	// 	&Render_Pipeline_Descriptor {
	// 		source_location = "res/microui.wgsl",
	// 		vertex_entry_point = "vertex_main",
	// 		fragment_entry_point = "fragment_main",
	// 		front_face = .CCW,
	// 		cull_mode = .None,
	// 		vertex_layouts = []Vertex_Layout_Type { .MicroUI },
	// 		bindgroups = []Bindgroup_Type {
	// 			.Draw_Command,
	// 			.Textures,
	// 		},
	// 		render_target = .Default,
	// 		depth_test = false,
	// 		multisample = false,
	// 	},
	// )

	// return renderer.resources.pipelines[.MicroUI_To_Rendertarget] != nil
	return true
}

