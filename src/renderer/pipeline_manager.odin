package renderer

import "core:log"
import "core:strings"
import vmem "core:mem/virtual"
import "vendor:wgpu"
import "shader_preprocessor"

// A Render_Pipeline is a handle to a specific pipeline used to draw things to a
// specific type of Render_Target.
// A Render_Pipeline MUST accept the following default bind_groups:
//		- 0 = Data
//		- 1 = Draw
//		- 2 = Utilities
// TODO(Vicix): One a BindGroupManager is implemented, allow for custom 
// bindgroups
Render_Pipeline :: distinct u32

INVALID_RENDER_PIPELINE :: max(Render_Pipeline)

// TODO(Vicix): Make this dynamic
Render_Target_Layout :: enum {
	Color,
	DepthColor,
	Deferred,
}

Blend_State :: enum {
	Disabled,
	Default,
}

Render_Pipeline_Descriptor :: struct {
	layout: Memory_Layout,
	render_target_layout: Render_Target_Layout,
	label: string,
	source: string,
	front_face: wgpu.FrontFace,
	cull_mode: wgpu.CullMode,
	vertex_entry_point: string,
	fragment_entry_point: string,
	blend_state: Blend_State,
}

Render_Pipeline_Info :: struct {
	using descriptor: Render_Pipeline_Descriptor,
	pipeline_handle: wgpu.RenderPipeline,
}

Render_Pipeline_Manager :: struct {
	arena: vmem.Arena,
	device: wgpu.Device,
	// TODO(Vicix): Move to render_target_layout
	surface_format: wgpu.TextureFormat,
	layout_manager: ^Memory_Layout_Manager,
	shader_preprocessor: shader_preprocessor.Shader_Preprocessor,
	bindgroup_layouts: ^[Bindgroup_Type]wgpu.BindGroupLayout,
	pipelines: [dynamic]Render_Pipeline_Info,
}

renderpipelinemanager_create :: proc(
	manager: ^Render_Pipeline_Manager,
	layout_manager: ^Memory_Layout_Manager,
	device: wgpu.Device,
	surface_format: wgpu.TextureFormat,
	bindgroup_layouts: ^[Bindgroup_Type]wgpu.BindGroupLayout,
	allocator := context.allocator,
) -> bool {
	manager.layout_manager = layout_manager
	manager.device = device
	manager.surface_format = surface_format
	manager.bindgroup_layouts = bindgroup_layouts

	manager.pipelines = make([dynamic]Render_Pipeline_Info, allocator)
	if err := shader_preprocessor.create(&manager.shader_preprocessor, allocator); err != nil {
		log.errorf("Could not create a Render_Pipeline: The preprocessor creation failed with error %v", err)
		return false
	}
	if vmem.arena_init_growing(&manager.arena) != .None {
		log.errorf("Could not create a Render_Pipeline: Could not create an arena")
		return false
	}

	if err := shader_preprocessor.add_include_path(
		&manager.shader_preprocessor,
		"res/shaders",
	); err != nil {
		log.warnf("Could not add the shader standard library to the include path. Got error %v", err)
	}
	
	return true
}

renderpipelinemanager_destroy :: proc(manager: Render_Pipeline_Manager) {
	delete(manager.pipelines)
}

renderpipelinemanager_register_pipeline :: proc(
	manager: ^Render_Pipeline_Manager,
	descriptor: Render_Pipeline_Descriptor,
) -> (Render_Pipeline, bool) {
	return INVALID_RENDER_PIPELINE, false
}

@(private="file")
Shader_Constant :: enum {
	Indices_Count = 0,
	Index_0_Size = 1,
	Index_1_Size = 2,
	Index_2_Size = 3,
	Index_3_Size = 4,
	Index_4_Size = 5,
	Index_5_Size = 6,
	Index_6_Size = 7,
	Index_7_Size = 8,
}

@(private="file")
SHADER_CONSTANT_NAME := [Shader_Constant]cstring {
	.Indices_Count = "config__memory_layout_indices_count",
	.Index_0_Size = "config__memory_layout_index_0_size",
	.Index_1_Size = "config__memory_layout_index_1_size",
	.Index_2_Size = "config__memory_layout_index_2_size",
	.Index_3_Size = "config__memory_layout_index_3_size",
	.Index_4_Size = "config__memory_layout_index_4_size",
	.Index_5_Size = "config__memory_layout_index_5_size",
	.Index_6_Size = "config__memory_layout_index_6_size",
	.Index_7_Size = "config__memory_layout_index_7_size",
}

// @(private="file")
renderpipelinemanager_create_wgpupipeline :: proc(
	manager: ^Render_Pipeline_Manager,
	descriptor: Render_Pipeline_Descriptor,
) -> (wgpu.RenderPipeline, bool) {
	assert(descriptor.render_target_layout == .DepthColor, "Other render targets are not yet supported")

	layout_info, layout_info_ok := memorylayoutmanager_get_info(manager.layout_manager^, descriptor.layout)
	if !layout_info_ok {
		log.errorf(
			"Could not create the wgpuRenderPipeline %s: The provided layout is not valid",
			descriptor.label,
		)
		return nil, false
	}

	shader_source, preprocess_err := shader_preprocessor.preprocess(
		&manager.shader_preprocessor,
		descriptor.source,
		allocator = context.temp_allocator,
	)
	if preprocess_err != nil {
		log.errorf(
			"Could not create the wgpuRenderPipeline %s: Could not preprocess the source, got error %v",
			descriptor.label,
			preprocess_err,
		)
		return nil, false
	}

	shader_module := wgpu.DeviceCreateShaderModule(
		manager.device,
		&wgpu.ShaderModuleDescriptor {
			label = strings.clone_to_cstring(descriptor.label, context.temp_allocator),
			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
				sType = .ShaderModuleWGSLDescriptor,
				code = strings.clone_to_cstring(shader_source, context.temp_allocator),
			},
		},
	)
	if shader_module == nil {
		log.errorf(
			"Could not create the wgpuRenderPipeline %s: Could not create a shader module",
			descriptor.label,
		)
	}
	defer wgpu.ShaderModuleRelease(shader_module)

	constants_values: [Shader_Constant]f64
	constants_values[.Indices_Count] = (f64)(layout_info.indices_count)
	for size, i in layout_info.source_sizes {
		constant := (Shader_Constant)((int)(Shader_Constant.Index_0_Size) + i)
		constants_values[constant] = (f64)(size)
	}

	constants_entries: [len(Shader_Constant)]wgpu.ConstantEntry
	for value, key in constants_values {
		key_string := SHADER_CONSTANT_NAME[key]
		constants_entries[key] = wgpu.ConstantEntry {
			key = key_string,
			value = value,
		}
	}

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		manager.device,
		&wgpu.PipelineLayoutDescriptor {
			label = strings.clone_to_cstring(descriptor.label),
			bindGroupLayoutCount = 3,
			bindGroupLayouts = raw_data([]wgpu.BindGroupLayout {
				manager.bindgroup_layouts[.Data],
				manager.bindgroup_layouts[.Draw],
				manager.bindgroup_layouts[.Utilities],
			}),
		},
	)
	if pipeline_layout == nil {
		log.errorf(
			"Could not create the wgpuRenderPipeline %s: Could not create a wgpu pipeline layout",
			descriptor.label,
		)
		return nil, false
	}
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	blend: wgpu.BlendState
	blend_ptr: ^wgpu.BlendState
	switch descriptor.blend_state {
	case .Default:
		blend = wgpu.BlendState {
			color = wgpu.BlendComponent {
				operation = .Add,
				srcFactor = .SrcAlpha,
				dstFactor = .OneMinusSrcAlpha,
			},
			alpha = wgpu.BlendComponent {
				operation = .Add,
				srcFactor = .Zero,
				dstFactor = .One,
			},
		}
		blend_ptr = &blend

	case .Disabled:
		blend_ptr = nil
	}

	pipeline := wgpu.DeviceCreateRenderPipeline(
		manager.device,
		&wgpu.RenderPipelineDescriptor {
			label = strings.clone_to_cstring(descriptor.label, context.temp_allocator),
			layout = pipeline_layout,
			primitive = wgpu.PrimitiveState {
				topology = .TriangleList,
				frontFace = descriptor.front_face,
				cullMode = descriptor.cull_mode,
			},
			vertex = wgpu.VertexState {
				module = shader_module,
				entryPoint = strings.clone_to_cstring(descriptor.vertex_entry_point, context.temp_allocator),
				constantCount = len(constants_entries),
				constants = &constants_entries[0],
			},
			fragment = &wgpu.FragmentState {
				module = shader_module,
				entryPoint = strings.clone_to_cstring(descriptor.fragment_entry_point, context.temp_allocator),
				constantCount = len(constants_entries),
				constants = &constants_entries[0],
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = manager.surface_format,
					blend = blend_ptr,
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			depthStencil = &wgpu.DepthStencilState {
				format = DEPTH_BUFFER_FORMAT,
				depthWriteEnabled = true,
				depthCompare = .Less,
				stencilWriteMask = max(u32),
				stencilReadMask = max(u32),
				stencilFront = wgpu.StencilFaceState {
					compare = .Always,
				},
				stencilBack = wgpu.StencilFaceState {
					compare = .Always,
				},
			},
			multisample = wgpu.MultisampleState {
				count = 1,
				mask = max(u32),
				alphaToCoverageEnabled = false,
			},
		},
	)
	if pipeline == nil {
		log.errorf(
			"Could not create the wgpuRenderPipeline %s: Could not create a wgpu pipeline",
			descriptor.label,
		)
		return nil, false
	}

	return pipeline, true
}
