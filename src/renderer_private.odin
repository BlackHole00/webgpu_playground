//+private
package main

import "base:runtime"
import "core:thread"
import "core:log"
import "core:os"
import vmem "core:mem/virtual"
import "vendor:glfw"
import "vendor:wgpu"

renderer_check_glfw_window :: proc(window: glfw.WindowHandle) -> bool {
	glfw.SwapBuffers(window)

	_, error := glfw.GetError()
	return error == glfw.NO_WINDOW_CONTEXT
}

renderer_init_instance :: proc(renderer: ^Renderer) -> bool {
	when ODIN_OS == .Windows {
		BACKENDS :: wgpu.InstanceBackendFlags { .Vulkan, .DX12, .DX11, .GL }
	} else when ODIN_OS == .Darwin {
		BACKENDS :: wgpu.InstanceBackendFlags { .Metal, .Vulkan, .GL }
	} else {
		BACKENDS :: wgpu.InstanceBackendFlags { .Vulkan, .GL }
	}

	when ODIN_DEBUG {
		LOG_LEVEL :: wgpu.LogLevel.Debug
		FLAGS :: wgpu.InstanceFlags { .Debug, .Validation }
	} else {
		LOG_LEVEL :: wgpu.LogLevel.Info
		FLAGS :: wgpu.InstanceFlags_Default
	}
	
	wgpu.SetLogCallback(wgpu_log_callback, renderer)
	wgpu.SetLogLevel(LOG_LEVEL)
	
	instance_descriptor := wgpu.InstanceDescriptor {
		nextInChain = &wgpu.InstanceExtras {
			sType = .InstanceExtras,
			backends = BACKENDS,
			flags = FLAGS,
		},
	}
	log.debugf("Creating an instance using the following descriptor: %#v", instance_descriptor)
	log.debugf("Note: Using in chain: %#v", (^wgpu.InstanceExtras)(instance_descriptor.nextInChain)^)

	renderer.instance = wgpu.CreateInstance(&instance_descriptor)
	return renderer.instance != nil
}

renderer_init_surface :: proc(renderer: ^Renderer) -> bool {
	surface_descriptor: wgpu.SurfaceDescriptor
	windowhandle_get_surfacedescriptor(window, &surface_descriptor)
	
	log.debugf("Creating a surface with the following descriptor: %#v", surface_descriptor)
	when ODIN_OS == .Windows {
		log.debugf(
			"Note: Using in chain: %#v",
			(^wgpu.SurfaceDescriptorFromWindowsHWND)(surface_descriptor.nextInChain)^,
		)
	} else do #panic("Unsupported")
	
	renderer.surface = wgpu.InstanceCreateSurface(renderer.instance, &surface_descriptor)
	
	return renderer.surface != nil
}

renderer_init_adapter :: proc(renderer: ^Renderer) -> bool {
	request_data := Adapter_Request_Data { renderer, false }

	adapter_options := wgpu.RequestAdapterOptions {
		compatibleSurface = renderer.surface,
		powerPreference = .HighPerformance,
	}
	log.debugf("Creating an adapter with the following options: %#v", adapter_options)
	
	wgpu.InstanceRequestAdapter(
		renderer.instance,
		&adapter_options,
		wgpu_request_adapter_callback,
		&request_data,
	)
	for !request_data.is_done {
		thread.yield()
	}

	renderer.adapter_properties = wgpu.AdapterGetProperties(renderer.adapter)
	renderer.adapter_features = wgpu.AdapterEnumerateFeatures(renderer.adapter, vmem.arena_allocator(&renderer.arena))
	if limits, limits_ok := wgpu.AdapterGetLimits(renderer.adapter); !limits_ok {
		log.warnf("Could not get device limits")
	} else {
		renderer.adapter_limits = limits
	}

	renderer.surface_preferred_format = wgpu.SurfaceGetPreferredFormat(renderer.surface, renderer.adapter)

	return renderer.adapter != nil
}

renderer_check_adapter_capabilities :: proc(renderer: ^Renderer) -> bool {
	// return slice.contains(renderer.adapter_features, wgpu.FeatureName.MultiDrawIndirect) &&
	// 	slice.contains(renderer.adapter_features, wgpu.FeatureName.MultiDrawIndirectCount) &&
	// 	renderer.adapter_limits.limits.maxBindGroups >= 1
	return renderer.adapter_limits.limits.maxBindGroups >= 1
}

renderer_init_device :: proc(renderer: ^Renderer) -> bool {
	request_data := Adapter_Request_Data { renderer, false }
	
	device_descriptor := wgpu.DeviceDescriptor {
		requiredFeatureCount = 1,
		requiredFeatures = raw_data([]wgpu.FeatureName { .MultiDrawIndirect }),
		deviceLostCallback = wgpu_device_lost_callback,
	}
	log.debugf("Creating a device with the following descriptor: %#v", device_descriptor)
	
	wgpu.AdapterRequestDevice(
		renderer.adapter, 
		&device_descriptor,
		wgpu_request_device_callback,
		&request_data,
	)
	for !request_data.is_done {
		thread.yield()
	}

	if limits, limits_ok := wgpu.DeviceGetLimits(renderer.device); !limits_ok {
		log.warnf("Could not get device limits")
	} else {
		renderer.device_limits = limits
	}

	renderer.queue = wgpu.DeviceGetQueue(renderer.device)

	return renderer.device != nil && renderer.queue != nil
}

renderer_init_pipelines :: proc(renderer: ^Renderer) -> bool {
	return renderer_init_basic_pipeline(renderer)
}

renderer_init_bind_group_layouts :: proc(renderer: ^Renderer) -> bool {
	renderer.bind_groups.general_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device, 
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
		renderer.device,
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
		renderer.device, 
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

	basic_pipeline_layout := wgpu.DeviceCreatePipelineLayout(renderer.device, &wgpu.PipelineLayoutDescriptor {
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
	wgpu.DeviceCreateRenderPipeline(renderer.device, &wgpu.RenderPipelineDescriptor {
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
				format = renderer.surface_preferred_format,
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

@(private="file")
Adapter_Request_Data :: struct {
	renderer: ^Renderer,
	is_done: bool,
}

@(private="file")
Device_Request_Data :: Adapter_Request_Data

@(private="file")
wgpu_request_adapter_callback :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	result: wgpu.Adapter,
	message: cstring,
	user_data: rawptr,
) {
	request_data := (^Adapter_Request_Data)(user_data)
	renderer := request_data.renderer
	
	context = runtime.default_context()
	context.logger = renderer.logger
	
	switch status {
	case .Unavailable:
	case .Unknown:
	case .Error:
		log.errorf("Could not request an adapter. Got the following message: %s", message)
	case .Success:
		if message != nil && message != "" {
			log.debugf("Obtained an adapter with the following message: %s", message)
		}
	}
	
	renderer.adapter = result
	request_data.is_done = true
}

@(private="file")
wgpu_request_device_callback :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	result: wgpu.Device,
	message: cstring,
	user_data: rawptr,
) {
	request_data := (^Device_Request_Data)(user_data)
	renderer := request_data.renderer
	
	context = runtime.default_context()
	context.logger = renderer.logger
	
	switch status {
	case .Unknown:
	case .Error:
		log.errorf("Could not request a device. Got the following message: %s", message)
	case .Success:
		if message != nil && message != "" {
			log.debugf("Obtained a device with the following message: %s", message)
		}
	}
	
	renderer.device = result
	request_data.is_done = true
}

@(private="file")
wgpu_device_lost_callback :: proc "c" (reason: wgpu.DeviceLostReason, message: cstring, userdata: rawptr) {
	r := (^Renderer)(userdata)
	
	context = runtime.default_context()
	context.logger = r.logger

	log.panicf("Lost device: %s\n", message)
}

@(private="file")
wgpu_log_callback :: proc "c" (level: wgpu.LogLevel, message: cstring, userdata: rawptr) {
	r := (^Renderer)(userdata)
	
	context = runtime.default_context()
	context.logger = r.logger

	switch level {
	case .Off:
	case .Trace:
	case .Debug:
		log.debugf("[WGPU] %s", message)
	case .Info:
		log.infof("[WGPU] %s", message)
	case .Warn:
		log.warnf("[WGPU] %s", message)
	case .Error:
		log.errorf("[WGPU] %s", message)
	}
}
