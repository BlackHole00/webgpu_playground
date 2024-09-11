package main

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:thread"
import "core:time"
import "core:image/png"
import la "core:math/linalg"
import "vendor:glfw"
import "vendor:wgpu"
import "renderer"

r: renderer.Renderer

logger: runtime.Logger
window: glfw.WindowHandle

vertex_buffer: wgpu.Buffer
index_buffer: wgpu.Buffer
general_state_uniform_buffer: wgpu.Buffer
instance_uniform_buffer: wgpu.Buffer
texture: wgpu.Texture
texture_view: wgpu.TextureView
sampler: wgpu.Sampler
bind_group_layout: wgpu.BindGroupLayout
bind_group: wgpu.BindGroup
render_pipeline_layout: wgpu.PipelineLayout
render_pipeline: wgpu.RenderPipeline
indirect_buffer: wgpu.Buffer

general_state_uniforms: General_State_Uniforms
instance_uniforms: Instance_Uniforms

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

	glfw.SetWindowSizeCallback(window, proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		
		general_state_uniforms.aspect_rateo = (f32)(width) / (f32)(height)
		renderer.resize_surface(r)
	})

	assert(renderer.create(&r, renderer.Renderer_Descriptor {
		window = window,
	}) == nil, "Could not initialize the renderer")
	defer renderer.destroy(&r)
	
	shader_module := wgpu.DeviceCreateShaderModule(r.device, &wgpu.ShaderModuleDescriptor {
		nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
			sType = .ShaderModuleWGSLDescriptor,
			code = #load("triangle.wgsl"),
		},
	})
	assert(shader_module != nil, "Could not compile shader")
	defer wgpu.ShaderModuleRelease(shader_module)

	vertex_buffer = wgpu.DeviceCreateBufferWithData(r.device, &wgpu.BufferWithDataDescriptor {
		usage = { .Vertex },
	}, VERTICES[:])
	assert(vertex_buffer != nil, "Could not create a vertex buffer")
	defer wgpu.BufferRelease(vertex_buffer)
	
	index_buffer = wgpu.DeviceCreateBufferWithData(r.device, &wgpu.BufferWithDataDescriptor {
		usage = { .Index },
	}, INDICES[:])
	assert(index_buffer != nil, "Could not create a index buffer")
	defer wgpu.BufferRelease(index_buffer)
	
	general_state_uniform_buffer = wgpu.DeviceCreateBuffer(r.device, &wgpu.BufferDescriptor {
		usage = { .CopyDst, .Uniform },
		size = size_of(General_State_Uniforms),
	})
	assert(general_state_uniform_buffer != nil, "Could not create a uniform buffer")
	defer wgpu.BufferRelease(general_state_uniform_buffer)
	
	instance_uniform_buffer = wgpu.DeviceCreateBuffer(r.device, &wgpu.BufferDescriptor {
		usage = { .CopyDst, .Uniform },
		size = size_of(Instance_Uniforms),
	})
	assert(instance_uniform_buffer != nil, "Could not create a uniform buffer")
	defer wgpu.BufferRelease(instance_uniform_buffer)
	
	indirect_buffer = wgpu.DeviceCreateBufferWithData(r.device, &wgpu.BufferWithDataDescriptor {
		usage = { .Indirect },
	}, []u32{ 6, 1, 0, 0, 0 })
	assert(indirect_buffer != nil, "Could not create a buffer")
	defer wgpu.BufferRelease(indirect_buffer)

	image, image_err := png.load_from_file("res/gradient.png", allocator = context.temp_allocator)
	assert(image_err == nil, "Could not read the image file")
	
	texture = wgpu.DeviceCreateTexture(r.device, &wgpu.TextureDescriptor {
		usage = { .TextureBinding, .CopyDst },
		dimension = ._2D,
		size = { (u32)(image.width), (u32)(image.height), 1 },
		mipLevelCount = 1,
		sampleCount = 1,
		format = .RGBA8Unorm,
	})
	assert(texture != nil, "Could not create a texture")
	defer wgpu.TextureRelease(texture)

	wgpu.QueueWriteTexture(
		r.queue, 
		&wgpu.ImageCopyTexture {
			texture = texture,
			mipLevel = 0,
			origin = { 0, 0, 0 },
			aspect = .All,
		}, 
		raw_data(image.pixels.buf), 
		len(image.pixels.buf), 
		&wgpu.TextureDataLayout {
			offset = 0,
			bytesPerRow = 4 * (u32)(image.width),
			rowsPerImage = (u32)(image.height),
		},
		&wgpu.Extent3D { (u32)(image.width), (u32)(image.height), 1 },
	)

	texture_view = wgpu.TextureCreateView(texture, &wgpu.TextureViewDescriptor {
		format = .RGBA8Unorm,
		dimension = ._2D,
		arrayLayerCount = 1,
		baseArrayLayer = 0,
		mipLevelCount = 1,
		baseMipLevel = 0,
	})
	assert(texture_view != nil, "Could not create a texture view")
	defer wgpu.TextureViewRelease(texture_view)

	sampler = wgpu.DeviceCreateSampler(r.device, &wgpu.SamplerDescriptor {
		addressModeU = .ClampToEdge,
		addressModeV = .ClampToEdge,
		addressModeW = .ClampToEdge,
		magFilter = .Linear,
		minFilter = .Linear,
		mipmapFilter = .Linear,
		lodMinClamp = 0.0,
		lodMaxClamp = 1.0,
		compare = .Undefined,
		maxAnisotropy = 1,
	})
	assert(sampler != nil, "Could not create a sampler")
	defer wgpu.SamplerRelease(sampler)
	
	bind_group_layout = wgpu.DeviceCreateBindGroupLayout(r.device, &wgpu.BindGroupLayoutDescriptor {
		entryCount = 4,
		entries = raw_data([]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(General_State_Uniforms),
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = { .Vertex, .Fragment },
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(Instance_Uniforms),
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 2,
				visibility = { .Fragment },
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 3,
				visibility = { .Fragment },
				sampler = wgpu.SamplerBindingLayout {
					type = .Filtering,
				},
			},
		}),
	})
	assert(bind_group_layout != nil, "Could not create a pipeline layout")
	defer wgpu.BindGroupLayoutRelease(bind_group_layout)
	
	render_pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &wgpu.PipelineLayoutDescriptor {
		bindGroupLayoutCount = 1,
		bindGroupLayouts = &bind_group_layout,
	})
	assert(render_pipeline_layout != nil, "Could not create a pipeline layout")
	defer wgpu.PipelineLayoutRelease(render_pipeline_layout)
	
	render_pipeline = wgpu.DeviceCreateRenderPipeline(r.device, &wgpu.RenderPipelineDescriptor {
		primitive = wgpu.PrimitiveState {
			topology = .TriangleList,
			frontFace = .CCW,
			cullMode = .None,
		},
		layout = render_pipeline_layout,
		vertex = wgpu.VertexState {
			module = shader_module,
			entryPoint = "vertex_main",
			bufferCount = 1,
			buffers = &wgpu.VertexBufferLayout {
				arrayStride = size_of(RVertex),
				stepMode = .Vertex,
				attributeCount = 3,
				attributes = raw_data([]wgpu.VertexAttribute {
					{ format = .Float32x3, offset = 0, shaderLocation = 0 },
					{ format = .Float32x3, offset = size_of([3]f32), shaderLocation = 1 },
					{ format = .Float32x2, offset = size_of([2]f32) + size_of([3]f32), shaderLocation = 2 },
				}),
			},
		},
		fragment = &wgpu.FragmentState {
			module = shader_module,
			entryPoint = "fragment_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = r.surface_capabilities.formats[0],
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
			count = 1,
			mask = max(u32),
			alphaToCoverageEnabled = false,
		},
	})
	assert(render_pipeline != nil, "Could not create a render pipeline")
	defer wgpu.RenderPipelineRelease(render_pipeline)

	bind_group = wgpu.DeviceCreateBindGroup(r.device, &wgpu.BindGroupDescriptor {
		layout = bind_group_layout,
		entryCount = 4,
		entries = raw_data([]wgpu.BindGroupEntry {
			wgpu.BindGroupEntry {
				binding = 0,
				buffer = general_state_uniform_buffer,
				offset = 0,
				size = max(8, size_of(General_State_Uniforms)),
			},
			wgpu.BindGroupEntry {
				binding = 1,
				buffer = instance_uniform_buffer,
				offset = 0,
				size = max(8, size_of(Instance_Uniforms)),
			},
			wgpu.BindGroupEntry {
				binding = 2,
				textureView = texture_view,
			},
			wgpu.BindGroupEntry {
				binding = 3,
				sampler = sampler,
			},
		}),
	})
	assert(bind_group != nil, "Could not create a bind group")
	defer wgpu.BindGroupRelease(bind_group)
	
	instance_uniforms.model = la.matrix4_translate([3]f32 { 0.5, 0.5, 0.0 })
	instance_uniforms.model = la.identity(la.Matrix4x4f32)
	instance_uniforms.view = la.matrix4_look_at(
		[3]f32{ 1.0, 1.0, 1.0 },
		[3]f32{ 0.0, 0.0, 0.0 },
		[3]f32{ 0.0, 1.0, 0.0 },
	)
	
	width, height := glfw.GetWindowSize(window)
	instance_uniforms.proj = la.matrix4_perspective(la.PI / 4.0, (f32)(width) / (f32)(height), 0.01, 100.0)
	wgpu.QueueWriteBuffer(r.queue, instance_uniform_buffer, 0, &instance_uniforms, size_of(Instance_Uniforms))
	
	for !wgpu.DevicePoll(r.device, false, nil) {
		thread.yield()
	}
	
	now := time.tick_now()
	
	format := r.surface_capabilities.formats[0]
	for !glfw.WindowShouldClose(window) {
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}
		defer wgpu.DevicePoll(r.device, false, nil)
		defer glfw.PollEvents()
		defer free_all(context.temp_allocator)
		
		surface_texture := wgpu.SurfaceGetCurrentTexture(r.surface)
		defer wgpu.TextureRelease(surface_texture.texture)
		if surface_texture.status != .Success {
			continue
		}
		
		surface_view := wgpu.TextureCreateView(surface_texture.texture, &wgpu.TextureViewDescriptor {
			format = format,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = .All,
		})
		assert(surface_view != nil, "Could not obtain a surface texture view")
		defer wgpu.TextureViewRelease(surface_view)

		general_state_uniforms.time = (f32)(glfw.GetTime())
		wgpu.QueueWriteBuffer(r.queue, general_state_uniform_buffer, 0, &general_state_uniforms, size_of(General_State_Uniforms))

		command_encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
		assert(command_encoder != nil, "Could not create a command encoder")
		defer wgpu.CommandEncoderRelease(command_encoder)
		
		renderpass_encoder := wgpu.CommandEncoderBeginRenderPass(command_encoder, &wgpu.RenderPassDescriptor {
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = surface_view,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = { 0.1, 0.2, 0.3, 1.0 },
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
		})
		assert(renderpass_encoder != nil, "Could not create a renderpass encoder")
		
		wgpu.RenderPassEncoderSetPipeline(renderpass_encoder, render_pipeline)
		wgpu.RenderPassEncoderSetVertexBuffer(renderpass_encoder, 0, vertex_buffer, 0, size_of(VERTICES))
		wgpu.RenderPassEncoderSetIndexBuffer(renderpass_encoder, index_buffer, .Uint16, 0, size_of(INDICES))
		wgpu.RenderPassEncoderSetBindGroup(renderpass_encoder, 0, bind_group)
		// wgpu.RenderPassEncoderDrawIndexed(renderpass_encoder, 6, 1, 0, 0, 0)
		// wgpu.RenderPassEncoderDrawIndexedIndirect(renderpass_encoder, indirect_buffer, 0)
		wgpu.RenderPassEncoderMultiDrawIndexedIndirect(renderpass_encoder, indirect_buffer, 0, 1)
		
		wgpu.RenderPassEncoderEnd(renderpass_encoder)
		wgpu.RenderPassEncoderRelease(renderpass_encoder)

		command_buffer := wgpu.CommandEncoderFinish(command_encoder)
		assert(command_buffer != nil, "Could not create a command buffer")
		defer wgpu.CommandBufferRelease(command_buffer)
		
		wgpu.QueueSubmit(r.queue, { command_buffer })
		wgpu.SurfacePresent(r.surface)

		duration := time.tick_since(now)
		now = time.tick_now()
		
		fps := 1000.0 / time.duration_milliseconds(duration)
		new_window_title := fmt.ctprintf("Window - Frame: %v - Fps: %f", duration, fps)

		glfw.SetWindowTitle(window, new_window_title)
	}

	for !wgpu.DevicePoll(r.device, false, nil) {
		thread.yield()
	}
}
