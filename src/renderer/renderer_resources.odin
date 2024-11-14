#+private
package renderer

import "core:log"
import "vendor:wgpu"
import "shared:utils"
import wgputils "wgpu"

DEPTH_BUFFER_FORMAT :: wgpu.TextureFormat.Depth24Plus
UI_MAX_QUADS_COUNT :: 1024
UI_MAX_VERTICES_COUNT :: 4 * UI_MAX_QUADS_COUNT
UI_MAX_INDICES_COUNT :: 6 * UI_MAX_QUADS_COUNT

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
	.Data = wgpu.BindGroupLayoutDescriptor {
		label = "Renderer Shared Data BindGroup Layout",
		entryCount = 9,
		entries = raw_data([]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry { // Layout_Infos
				binding = 0,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
				},
			},
			wgpu.BindGroupLayoutEntry { // Layout_Infos
				binding = 1,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
				},
			},
			wgpu.BindGroupLayoutEntry { // Model_Infos
				binding = 2,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
			wgpu.BindGroupLayoutEntry { // Texture_Infos
				binding = 3,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
			wgpu.BindGroupLayoutEntry { // Vertices
				binding = 4,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
			wgpu.BindGroupLayoutEntry { // Indices
				binding = 5,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
			wgpu.BindGroupLayoutEntry { // Object Instances
				binding = 6,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
			wgpu.BindGroupLayoutEntry { // Texture Atlas
				binding = 7,
				visibility = { .Vertex, .Fragment },
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
				nextInChain = &wgpu.BindGroupLayoutEntryExtras {
					sType = .BindGroupLayoutEntryExtras,
					count = TEXTURE_ATLAS_COUNT,
				},
			},
			wgpu.BindGroupLayoutEntry { // Atlas Info
				binding = 8,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
		}),
	},
	.Draw = wgpu.BindGroupLayoutDescriptor {
		label = "Renderer Draw Data BindGroup Layout",
		entryCount = 3,
		entries = raw_data([]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry { // Info
				binding = 0,
				visibility = { .Vertex, .Fragment, },
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = true,
				},
			},
			wgpu.BindGroupLayoutEntry { // Cameras
				binding = 1,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
			wgpu.BindGroupLayoutEntry { // Objects
				binding = 2,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = false,
					minBindingSize = 0,
				},
			},
		}),
	},
	.Utilities = wgpu.BindGroupLayoutDescriptor {
		label = "Renderer Utilities BindGroup Layout",
		entryCount = 2,
		entries = raw_data([]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry { // Generic Sampler
				binding = 0,
				visibility = { .Vertex, .Fragment },
				sampler = wgpu.SamplerBindingLayout {
					type = .Filtering,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = { .Vertex, .Fragment },
				sampler = wgpu.SamplerBindingLayout { // Pixel Perfect Sampler
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
	// if !resources_init_pipelines(renderer) {
	// 	log.errorf("Could not init the pipelines")
	// 	return Common_Error.Pipeline_Creation_Failed
	// }

	return nil
}

resources_deinit :: proc(renderer: ^Renderer) {
	resources_deinit_buffers(renderer)
	resources_deinit_textures(renderer^)

	for pipeline in renderer.resources.pipelines {
		if pipeline != nil {
			wgpu.RenderPipelineRelease(pipeline)
		}
	}
	for bindgroup in renderer.resources.bindgroups {
		if bindgroup != nil {
			wgpu.BindGroupRelease(bindgroup)
		}
	}
	for sampler in renderer.resources.samplers {
		if sampler != nil {
			wgpu.SamplerRelease(sampler)
		}
	}
	for bindgroup_layout in renderer.resources.bindgroup_layouts {
		if bindgroup_layout != nil {
			wgpu.BindGroupLayoutRelease(bindgroup_layout)
		}
	}
}

resources_init_bindgroup_layouts :: proc(renderer: ^Renderer) -> bool {
	for &descriptor, type in BINDGROUP_LAYOUT_DESCRIPTORS {
		renderer.resources.bindgroup_layouts[type] = wgpu.DeviceCreateBindGroupLayout(
			renderer.core.device,
			&descriptor,
		)
	}

	return utils.typedarray_ensure_all_values_valid(renderer.resources.bindgroup_layouts)
}

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

resources_recreate_volatile_bindgroups :: proc(renderer: ^Renderer) -> bool {
	if renderer.resources.bindgroups[.Data] != nil {
		wgpu.BindGroupRelease(renderer.resources.bindgroups[.Data])
	}
	if renderer.resources.bindgroups[.Draw] != nil {
		wgpu.BindGroupRelease(renderer.resources.bindgroups[.Draw])
	}

	texture_atlas_rgba8_view := wgputils.dynamictexture_as_view(
		renderer.resources.dynamic_textures[.Texture_Atlas_RGBA8],
	)
	defer wgpu.TextureViewRelease(texture_atlas_rgba8_view)
	texture_atlas_rg8_view := wgputils.dynamictexture_as_view(
		renderer.resources.dynamic_textures[.Texture_Atlas_RG8],
	)
	defer wgpu.TextureViewRelease(texture_atlas_rg8_view)
	texture_atlas_r8_view := wgputils.dynamictexture_as_view(
		renderer.resources.dynamic_textures[.Texture_Atlas_R8],
	)
	defer wgpu.TextureViewRelease(texture_atlas_r8_view)

	renderer.resources.bindgroups[.Data] = wgpu.DeviceCreateBindGroup(
		renderer.core.device,
		&wgpu.BindGroupDescriptor {
			label = "Renderer Shared Data BindGroup Layout",
			layout = renderer.resources.bindgroup_layouts[.Data],
			entryCount = 9,
			entries = raw_data([]wgpu.BindGroupEntry {
				wgpu.BindGroupEntry {
					binding = 0,
					buffer = renderer.resources.static_buffers[.Application_State],
					offset = 0,
					size = wgpu.WHOLE_SIZE,
				},
				wgpu.BindGroupEntry {
					binding = 1,
					buffer = renderer.resources.static_buffers[.Memory_Layout_Info],
					offset = 0,
					size = MAX_LAYOUTS * size_of(Memory_Layout_Info),
				},
				wgpu.BindGroupEntry {
					binding = 2,
					buffer = renderer.resources.mirrored_buffers[.Model_Info].handle,
					offset = 0,
					size = wgpu.WHOLE_SIZE,
				},
				wgpu.BindGroupEntry {
					binding = 3,
					buffer = renderer.resources.dynamic_buffers[.Texture_Info].handle,
					offset = 0,
					size = (u64)(wgputils.dynamicbuffer_cap(
						renderer.resources.dynamic_buffers[.Texture_Info],
					)),
				},
				wgpu.BindGroupEntry {
					binding = 4,
					buffer = renderer.resources.dynamic_buffers[.Model_Vertices].handle,
					offset = 0,
					size = (u64)(wgputils.dynamicbuffer_cap(
						renderer.resources.dynamic_buffers[.Model_Vertices],
					)),
				},
				wgpu.BindGroupEntry {
					binding = 5,
					buffer = renderer.resources.dynamic_buffers[.Model_Indices].handle,
					offset = 0,
					size = (u64)(wgputils.dynamicbuffer_cap(
						renderer.resources.dynamic_buffers[.Model_Indices],
					)),
				},
				wgpu.BindGroupEntry {
					binding = 6,
					buffer = renderer.resources.mirrored_buffers[.Objects].handle,
					offset = 0,
					size = (u64)(wgputils.mirroredbuffer_cap(
						renderer.resources.mirrored_buffers[.Objects],
					)),
				},
				wgpu.BindGroupEntry {
					binding = 7,
					nextInChain = &wgpu.BindGroupEntryExtras {
						sType = .BindGroupEntryExtras,
						textureViewCount = TEXTURE_ATLAS_COUNT,
						textureViews = raw_data([]wgpu.TextureView {
							texture_atlas_r8_view,
							texture_atlas_rg8_view,
							texture_atlas_rgba8_view,
						}),
					},
				},
				wgpu.BindGroupEntry {
					binding = 8,
					buffer = renderer.resources.static_buffers[.Atlas_Info],
					offset = 0,
					size = size_of(Atlas_Gpu_Info),
				},
			}),
		},
	)
	renderer.resources.bindgroups[.Draw] = wgpu.DeviceCreateBindGroup(
		renderer.core.device,
		&wgpu.BindGroupDescriptor {
			label = "Renderer Draw Data BindGroup Layout",
			layout = renderer.resources.bindgroup_layouts[.Draw],
			entryCount = 3,
			entries = raw_data([]wgpu.BindGroupEntry {
				wgpu.BindGroupEntry {
					binding = 0,
					buffer = renderer.resources.dynamic_buffers[.Draw_Call_Info].handle,
					offset = 0,
					size = wgpu.WHOLE_SIZE,
				},
				wgpu.BindGroupEntry {
					binding = 1,
					buffer = renderer.resources.dynamic_buffers[.Cameras].handle,
					offset = 0,
					size = wgpu.WHOLE_SIZE,
				},
				wgpu.BindGroupEntry {
					binding = 2,
					buffer = renderer.resources.dynamic_buffers[.Object_Instances].handle,
					offset = 0,
					size = (u64)(wgputils.dynamicbuffer_cap(
						renderer.resources.dynamic_buffers[.Object_Instances],
					)),
				},
			}),
		},
	)

	return renderer.resources.bindgroups[.Draw] != nil &&
		renderer.resources.bindgroups[.Draw] != nil
}

resources_init_bindgroups :: proc(renderer: ^Renderer) -> bool {
	renderer.resources.bindgroups[.Utilities] = wgpu.DeviceCreateBindGroup(
		renderer.core.device,
		&wgpu.BindGroupDescriptor {
			label = "Renderer Utilities BindGroup Layout",
			layout = renderer.resources.bindgroup_layouts[.Utilities],
			entryCount = 2,
			entries = raw_data([]wgpu.BindGroupEntry {
				wgpu.BindGroupEntry {
					binding = 0,
					sampler = renderer.resources.samplers[.Generic],
				},
				wgpu.BindGroupEntry {
					binding = 1,
					sampler = renderer.resources.samplers[.Pixel_Perfect],
				},
			}),
		},
	)

	resources_recreate_volatile_bindgroups(renderer)

	return utils.typedarray_ensure_all_values_valid(renderer.resources.bindgroups)
}

resources_init_pipelines :: proc(renderer: ^Renderer) -> bool {
	renderer.resources.pipelines[.Obj_Draw], _ = renderpipelinemanager_create_wgpupipeline(
		&renderer.render_pipeline_manager,
		Render_Pipeline_Descriptor {
			layout = 0,
			render_target_layout = .DepthColor,
			label = "Obj Draw",
			source = "res/shaders/renderer/obj_draw.wgsl",
			front_face = .CCW,
			cull_mode = .Back,
			vertex_entry_point = "vertex_main",
			fragment_entry_point = "fragment_main",
			blend_state = .Default,
		},
	)

	return utils.typedarray_ensure_all_values_valid(renderer.resources.pipelines)
}

