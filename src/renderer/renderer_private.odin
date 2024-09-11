//+private
package renderer

import "core:os"
import "vendor:wgpu"

renderer_init_pipelines :: proc(renderer: ^Renderer) -> bool {
	return renderer_init_basic_pipeline(renderer)
}

renderer_init_bind_group_layouts :: proc(renderer: ^Renderer) -> bool {
	renderer.bind_groups.general_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.core.device, 
		&wgpu.BindGroupLayoutDescriptor {
			label = "general_bind_group_layout",
			entryCount = 2,
			entries = raw_data([]wgpu.BindGroupLayoutEntry {
				wgpu.BindGroupLayoutEntry {
					binding = 0,
					visibility = { .Vertex, .Fragment },
					buffer = wgpu.BufferBindingLayout {
						type = .Uniform,
						minBindingSize = size_of(General_State_Uniform),
					},
				},
				wgpu.BindGroupLayoutEntry {
					binding = 1,
					visibility = { .Vertex, .Fragment },
					buffer = wgpu.BufferBindingLayout {
						type = .Uniform,
						minBindingSize = size_of(Instance_State_Uniform),
					},
				},
			}),
		},
	)
	if renderer.bind_groups.general_layout == nil {
		return false
	}
	
	renderer.bind_groups.textures_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.core.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "texture_bind_group_layout",
			entryCount = 2,
			entries = raw_data([]wgpu.BindGroupLayoutEntry {
				wgpu.BindGroupLayoutEntry {
					binding = 0,
					visibility = { .Vertex, .Fragment },
					texture = wgpu.TextureBindingLayout {
						sampleType = .Float,
						viewDimension = ._2D,
						multisampled = false,
					},
				},
				wgpu.BindGroupLayoutEntry {
					binding = 1,
					visibility = { .Vertex, .Fragment },
					sampler = wgpu.SamplerBindingLayout {
						type = .Filtering,
					},
				},
			}),
		},
	)
	if renderer.bind_groups.general_layout == nil {
		return false
	}
	
	return true
}

renderer_init_basic_pipeline :: proc(renderer: ^Renderer) -> bool {
	source, source_ok := os.read_entire_file("res/basic.wgsl", context.temp_allocator)
	if !source_ok {
		return false
	}
	
	basic_shader_module := wgpu.DeviceCreateShaderModule(
		renderer.core.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
				sType = .ShaderModuleWGSLDescriptor,
				code = (cstring)(&source[0]),
			},
		},
	)
	if basic_shader_module == nil {
		return false
	}
	defer wgpu.ShaderModuleRelease(basic_shader_module)

	basic_pipeline_layout := wgpu.DeviceCreatePipelineLayout(renderer.core.device, &wgpu.PipelineLayoutDescriptor {
		bindGroupLayoutCount = 2,
		bindGroupLayouts = raw_data([]wgpu.BindGroupLayout {
			renderer.bind_groups.general_layout,
			renderer.bind_groups.textures_layout,
		}),
	})
	if basic_pipeline_layout == nil {
		return false
	}
	defer wgpu.PipelineLayoutRelease(basic_pipeline_layout)
	
	// TODO(Vicix): Do layout
	wgpu.DeviceCreateRenderPipeline(renderer.core.device, &wgpu.RenderPipelineDescriptor {
		primitive = wgpu.PrimitiveState {
			topology = .TriangleList,
			frontFace = .CCW,
			// TODO(Vicix): Change to .Back
			cullMode = .None,
		},
		layout = basic_pipeline_layout,
		vertex = wgpu.VertexState {
			module = basic_shader_module,
			entryPoint = "vertex_main",
			bufferCount = 2,
			buffers = raw_data([]wgpu.VertexBufferLayout {
				wgpu.VertexBufferLayout {
					arrayStride = size_of(Basic_Vertex),
					stepMode = .Vertex,
					attributeCount = 2,
					attributes = raw_data([]wgpu.VertexAttribute {
						{ format = .Float32x3, offset = 0, shaderLocation = 0 },
						{ format = .Float32x2, offset = size_of([3]f32), shaderLocation = 1 },
					}),
				},
				wgpu.VertexBufferLayout {
					arrayStride = size_of(Basic_Instance_Data),
					stepMode = .Instance,
					attributeCount = 1,
					attributes = raw_data([]wgpu.VertexAttribute {
						{ format = .Float32x3, offset = 0, shaderLocation = 2 },
					}),
				},
			}),
		},
		fragment = &wgpu.FragmentState {
			module = basic_shader_module,
			entryPoint = "fragment_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = renderer.core.surface_capabilities.formats[0],
				writeMask = wgpu.ColorWriteMaskFlags_All,
			},
		},
		multisample = wgpu.MultisampleState {
			count = 1,
			mask = max(u32),
			alphaToCoverageEnabled = false,
		},
	})
	
	return true
}


