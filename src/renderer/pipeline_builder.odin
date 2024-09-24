//+private
package renderer

import "core:os"
import "vendor:wgpu"

Render_Pipeline_Descriptor :: struct {
	source_location: string,
	vertex_entry_point: cstring,
	fragment_entry_point: cstring,

	front_face: wgpu.FrontFace,
	cull_mode: wgpu.CullMode,

	vertex_layouts: []Vertex_Layout_Type,
	bindgroups: []Bindgroup_Type,

	render_target: Render_Target,
	depth_test: bool,

	multisample: bool,
}

renderpipeline_build :: proc(renderer: ^Renderer, descriptor: ^Render_Pipeline_Descriptor) -> (wgpu.RenderPipeline, bool) #optional_ok {
	bind_group_layouts: [32]wgpu.BindGroupLayout
	vertex_buffer_layouts: [8]wgpu.VertexBufferLayout

	source, source_ok := os.read_entire_file(descriptor.source_location, context.temp_allocator)
	if !source_ok {
		return nil, false
	}

	shader_module := wgpu.DeviceCreateShaderModule(
		renderer.core.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
				sType = .ShaderModuleWGSLDescriptor,
				code = (cstring)(raw_data(source)),
			},
		},
	)
	if shader_module == nil {
		return nil, false
	}
	defer wgpu.ShaderModuleRelease(shader_module)

	for bindgroup_type, i in descriptor.bindgroups {
		bind_group_layouts[i] = renderer.resources.bindgroup_layouts[bindgroup_type]
	}
	layout := wgpu.DeviceCreatePipelineLayout(renderer.core.device, &wgpu.PipelineLayoutDescriptor {
		bindGroupLayoutCount = len(descriptor.bindgroups),
		bindGroupLayouts = &bind_group_layouts[0],
	})
	if layout == nil {
		return nil, false
	}
	defer wgpu.PipelineLayoutRelease(layout)

	depth_stencil_state: wgpu.DepthStencilState
	depth_stencil_state_ptr: ^wgpu.DepthStencilState
	if descriptor.depth_test {
		switch descriptor.render_target {
		case .Default:
			depth_stencil_state.format = DEPTH_BUFFER_FORMAT
		}

		depth_stencil_state.depthWriteEnabled = true
		depth_stencil_state.depthCompare = .LessEqual
		depth_stencil_state.stencilWriteMask = 0
		depth_stencil_state.stencilReadMask = 0
		depth_stencil_state.stencilFront.compare = .Never
		depth_stencil_state.stencilBack.compare = .Never

		depth_stencil_state_ptr = &depth_stencil_state
	}

	multisample_state: wgpu.MultisampleState
	if descriptor.multisample {
		multisample_state = wgpu.MultisampleState {
			count = 4,
			mask = max(u32),
			alphaToCoverageEnabled = false,
		}
	}

	target_format: wgpu.TextureFormat
	switch descriptor.render_target {
	case .Default:
		target_format = renderer.core.surface_capabilities.formats[0]
	}

	for vertex_layout_type, i in descriptor.vertex_layouts {
		vertex_buffer_layouts[i] = renderer.resources.vertex_layouts[vertex_layout_type]
	}
	pipeline := wgpu.DeviceCreateRenderPipeline(renderer.core.device, &wgpu.RenderPipelineDescriptor {
		layout = layout,
		primitive = wgpu.PrimitiveState {
			topology = .TriangleList,
			frontFace = descriptor.front_face,
			cullMode = descriptor.cull_mode,
		},
		depthStencil = depth_stencil_state_ptr,
		vertex = wgpu.VertexState {
			module = shader_module,
			entryPoint = descriptor.vertex_entry_point,
			bufferCount = len(descriptor.vertex_layouts),
			buffers = &vertex_buffer_layouts[0],
		},
		fragment = &wgpu.FragmentState {
			module = shader_module,
			entryPoint = descriptor.fragment_entry_point,
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = target_format,
				writeMask = wgpu.ColorWriteMaskFlags_All,
				blend = &wgpu.BlendState {
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
				},
			},
		},
		multisample = wgpu.MultisampleState {
			count = 4 if descriptor.multisample else 1,
			mask = max(u32),
			alphaToCoverageEnabled = false,
		},
	})

	return pipeline, pipeline != nil
}
