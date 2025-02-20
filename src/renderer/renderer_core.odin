package renderer

import "base:runtime"
import "core:log"
import vmem "core:mem/virtual"
import "vendor:glfw"
import wgpu "shared:wgpu/wrapper"
import wgpuglfw "shared:wgpu/utils/glfw"

Renderer_Core_Descriptor :: struct {
	debug: bool,
	validation: bool,
	trace: bool,

	features: wgpu.Features,
	limits: Maybe(wgpu.Limits),

	logger: runtime.Logger,

	window_handle: glfw.WindowHandle,
}

Renderer_Core :: struct {
	instance: wgpu.Instance,
	surface: wgpu.Surface,
	adapter: wgpu.Adapter,
	device: wgpu.Device,
	queue: wgpu.Queue,

	adapter_info: wgpu.Adapter_Info,
	adapter_features: wgpu.Adapter_Features,
	adapter_limits: wgpu.Limits,
	device_features: wgpu.Device_Features,
	device_limits: wgpu.Limits,
	
	window_handle: glfw.WindowHandle,

	logger: runtime.Logger,
	allocator: runtime.Allocator,
	global_arena: vmem.Arena,
	global_allocator: runtime.Allocator,
	frame_arena: vmem.Arena,
	frame_allocator: runtime.Allocator,
}

renderercore_create :: proc(
	core: ^Renderer_Core,
	descriptor: Renderer_Core_Descriptor,
	allocator := context.allocator,
) -> (res: Renderer_Result) {
	defer if res != nil {
		renderercore_destroy(core)
	}

	core.allocator = allocator
	vmem.arena_init_growing(&core.global_arena) or_return
	core.global_allocator = vmem.arena_allocator(&core.global_arena)
	vmem.arena_init_growing(&core.frame_arena) or_return
	core.frame_allocator = vmem.arena_allocator(&core.frame_arena)

	core.window_handle = descriptor.window_handle

	renderercore_initialize_logger(core, descriptor)
	renderercore_initialize_instance(core, descriptor) or_return
	renderercore_initialize_surface(core, descriptor) or_return
	renderercore_initialize_adapter(core, descriptor) or_return
	renderercore_initialize_device(core, descriptor) or_return

	return nil
}

renderercore_destroy :: proc(core: ^Renderer_Core) {
	if core.queue != nil {
		wgpu.queue_release(core.queue)
	}
	if core.device != nil {
		wgpu.device_release(core.device)
	}
	if core.adapter != nil {
		wgpu.adapter_release(core.adapter)
	}
	if core.surface != nil {
		wgpu.surface_release(core.surface)
	}
	if core.instance != nil {
		wgpu.instance_release(core.instance)
	}
	if core.global_arena != {} {
		vmem.arena_destroy(&core.global_arena)
	}
	if core.frame_arena != {} {
		vmem.arena_destroy(&core.frame_arena)
	}
}

renderercore_configure_surface :: proc(core: ^Renderer_Core, size: Maybe([2]u32) = nil) -> Renderer_Result {
	actual_size: [2]u32
	if size != nil {
		actual_size = size.?
	} else {
		width, height := glfw.GetWindowSize(core.window_handle)
		actual_size.x = cast(u32)width
		actual_size.y = cast(u32)height
	}

	// TODO: Use a proper config
	configuration, configuration_ok := wgpu.surface_get_default_config(
		core.surface,
		core.adapter,
		actual_size.x,
		actual_size.y,
	)
	if !configuration_ok {
		return .Could_Not_Configure_Surface
	}

	configuration.format = .Bgra8_Unorm
	if !wgpu.surface_configure(core.surface, core.device, configuration) {
		return .Could_Not_Configure_Surface
	}

	return nil
}

@(private)
renderercore_initialize_logger :: proc(
	core: ^Renderer_Core,
	descriptor: Renderer_Core_Descriptor,
) -> Renderer_Result {
	if descriptor.logger == {} {
		return nil
	}

	core.logger = descriptor.logger

	wgpu.set_log_callback(wgpu_log_callback, &core.logger)

	switch {
	case descriptor.trace:
		wgpu.set_log_level(.Trace)
	case descriptor.debug:
		wgpu.set_log_level(.Debug)
	case:
		wgpu.set_log_level(.Info)
	}

	return nil
}

@(private)
renderercore_initialize_instance :: proc(
	core: ^Renderer_Core,
	descriptor: Renderer_Core_Descriptor,
) -> Renderer_Result {
	instance_descriptor: wgpu.Instance_Descriptor

	#partial switch ODIN_OS {
	case .Darwin:
		instance_descriptor.backends = { .Metal }
	case .Windows:
		instance_descriptor.backends = { .DX12, .Vulkan }
	case:
		instance_descriptor.backends = { .Vulkan }
	}

	if descriptor.debug {
		instance_descriptor.flags += { .Debug }
	}
	if descriptor.validation {
		instance_descriptor.flags += { .Validation }
	}

	instance, instance_ok := wgpu.create_instance(instance_descriptor)
	if !instance_ok {
		return .Could_Not_Create_Instance
	}
	core.instance = instance

	return nil
}

@(private)
renderercore_initialize_surface :: proc(
	core: ^Renderer_Core,
	descriptor: Renderer_Core_Descriptor,
) -> Renderer_Result {
	assert(core.instance != nil)

	if descriptor.window_handle == nil {
		return .Invalid_Window_Provided
	}

	surface_descriptor, surface_descriptor_ok := wgpuglfw.get_surface_descriptor(descriptor.window_handle)
	if !surface_descriptor_ok {
		return .Could_Not_Create_Surface
	}

	surface_descriptor.label = "Renderer surface"
	surface, surface_ok := wgpu.instance_create_surface(core.instance, surface_descriptor)
	if !surface_ok {
		return .Could_Not_Create_Surface
	}
	core.surface = surface

	_ = glfw.GetCocoaWindow(descriptor.window_handle)

	return nil
}

@(private)
renderercore_initialize_adapter :: proc(
	core: ^Renderer_Core,
	descriptor: Renderer_Core_Descriptor,
) -> Renderer_Result {
	assert(core.instance != nil)
	assert(core.surface != nil)

	adapter, adapter_ok := wgpu.instance_request_adapter(
		core.instance, 
		wgpu.Request_Adapter_Options {
			compatible_surface = core.surface,
			power_preference = .High_Performance,
		},
	)
	if !adapter_ok {
		return .Could_Not_Create_Adapter
	}
	core.adapter = adapter

	adapter_info, adapter_info_ok := wgpu.adapter_get_info(core.adapter)
	if !adapter_info_ok {
		return .Could_Not_Query_Adapter_Info
	}
	core.adapter_info = adapter_info

	core.adapter_features = wgpu.adapter_get_features(core.adapter)

	adapter_limits, adapter_limits_ok := wgpu.adapter_get_limits(core.adapter)
	if !adapter_limits_ok {
		return .Could_Not_Query_Adapter_Info
	}
	core.adapter_limits = adapter_limits

	core.adapter_features = wgpu.adapter_get_features(core.adapter)

	log.infof("Using adapter %#v", core.adapter_info)
	log.debugf("The adapter supports the following features: %#v", core.adapter_features)
	log.debugf("The adapter supports the following limits: %#v", core.adapter_limits)

	for required_feature in descriptor.features {
		if required_feature not_in core.adapter_features {
			return .Required_Adapter_Feature_Not_Present
		}
	}

	return nil
}

@(private)
renderercore_initialize_device :: proc(
	core: ^Renderer_Core,
	descriptor: Renderer_Core_Descriptor,
) -> Renderer_Result {
	assert(core.instance != nil)
	assert(core.surface != nil)
	assert(core.adapter != nil)

	device_descriptor: wgpu.Device_Descriptor
	device_descriptor.label = "Renderer Device"
	device_descriptor.required_features = descriptor.features
	// TODO: device_descriptor.device_lost_callback = 
	if descriptor.trace {
		// TODO: device_descriptor.trace_path =
	}
	if descriptor.limits != nil {
		device_descriptor.required_limits = descriptor.limits.?
	} else {
		device_descriptor.required_limits = wgpu.DEFAULT_LIMITS
	}

	device, device_ok := wgpu.adapter_request_device(
		core.adapter,
		device_descriptor,
	)
	if !device_ok {
		return .Could_Not_Create_Device
	}
	core.device = device

	core.device_features = wgpu.device_get_features(core.device)
	device_limits, device_limits_ok := wgpu.device_get_limits(core.device)
	if !device_limits_ok {
		return .Could_Not_Query_Device_Info
	}
	core.device_limits = device_limits

	core.queue = wgpu.device_get_queue(core.device)

	return nil
}

@(private = "file")
wgpu_log_callback: wgpu.Log_Callback : proc "c" (level: wgpu.Log_Level, message: cstring, user_data: rawptr) {
	logger := cast(^runtime.Logger)user_data

	context = runtime.default_context()
	context.logger = logger^

	#partial switch level {
	case .Error:
		log.errorf("[WGPU] %s", message)
	case .Warn:
		log.warnf("[WGPU] %s", message)
	case .Info:
		log.infof("[WGPU] %s", message)
	case .Debug:
		log.debugf("[WGPU] %s", message)
	case .Trace:
		log.debugf("[WGPU - TRACE] %s", message)
	}
}

