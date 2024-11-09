#+private
package renderer

import "base:runtime"
import "core:log"
import "core:thread"
import "core:slice"
import vmem "core:mem/virtual"
import "vendor:glfw"
import "vendor:wgpu"
import wgpuglfw "vendor:wgpu/glfwglue"

core_init :: proc(renderer: ^Renderer) -> (err: Error) {
	if !core_check_glfw_window(renderer.external.window) {
		log.errorf(
			"The provided window does have a context registered. Please provide a glfw window with the " +
			"GLFW_CLIENT_API=GLFW_NO_API window hint",
		)
		return Common_Error.Invalid_Glfw_Window
	}
	defer if err != nil do core_deinit(renderer^)
	
	if !core_instance_init(renderer) {
		log.errorf("Could not create a wgpu instance")
		return Common_Error.Instance_Creation_Failed
	}
	if !core_surface_init(renderer) {
		log.errorf("Could not create a wgpu surface")
		return Common_Error.Surface_Creation_Failed
	}
	if !core_adapter_init(renderer) {
		log.errorf("Could not create a wgpu adapter")
		return Common_Error.Adapter_Creation_Failed
	}

	log.debugf("Got adapter with properties:\t%#v", renderer.core.adapter_info)
	log.debugf("Got adapter with limits:\t%#v", renderer.core.adapter_limits)
	log.debugf("Got adapter with features:\t%#v", renderer.core.adapter_features)
	
	if !core_check_adapter_capabilities(renderer) {
		log.errorf("The adapter does not support the necessary features")
		return Common_Error.Adapter_Does_Not_Support_Necessary_Features
	}
	if !core_device_init(renderer) {
		log.errorf("Could not create a device")
		return Common_Error.Device_Creation_Failed
	}

	return nil
}

core_deinit :: proc(renderer: Renderer) {
	if renderer.core.queue != nil do wgpu.QueueRelease(renderer.core.queue)
	if renderer.core.device != nil do wgpu.DeviceRelease(renderer.core.device)
	if renderer.core.adapter != nil {
		wgpu.SurfaceCapabilitiesFreeMembers(renderer.core.surface_capabilities)
		wgpu.AdapterInfoFreeMembers(renderer.core.adapter_info)
		wgpu.AdapterRelease(renderer.core.adapter)
	}
	if renderer.core.surface != nil do wgpu.SurfaceRelease(renderer.core.surface)
	if renderer.core.instance != nil do wgpu.InstanceRelease(renderer.core.instance)
}

core_check_glfw_window :: proc(window: glfw.WindowHandle) -> bool {
	glfw.SwapBuffers(window)

	_, error := glfw.GetError()
	return error == glfw.NO_WINDOW_CONTEXT
}

core_instance_init :: proc(renderer: ^Renderer) -> bool {
	when ODIN_OS == .Windows {
		BACKENDS :: wgpu.InstanceBackendFlags { .Vulkan, .DX12, .GL }
	} else when ODIN_OS == .Darwin {
		BACKENDS :: wgpu.InstanceBackendFlags { .Metal, .Vulkan, .GL }
	} else {
		BACKENDS :: wgpu.InstanceBackendFlags { .Vulkan, .GL }
	}

	FLAGS :: wgpu.InstanceFlags { .Debug, .Validation } when ODIN_DEBUG else wgpu.InstanceFlags_Default
	LOG_LEVEL :: wgpu.LogLevel.Info when #config(WGPU_VERBOSE_LOGS, false) else wgpu.LogLevel.Warn
	
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

	renderer.core.instance = wgpu.CreateInstance(&instance_descriptor)
	return renderer.core.instance != nil
}

core_surface_init :: proc(renderer: ^Renderer) -> bool {
	renderer.core.surface = wgpuglfw.GetSurface(renderer.core.instance, renderer.external.window)
	return renderer.core.surface != nil
}

core_adapter_init :: proc(renderer: ^Renderer) -> bool {
	request_data := Adapter_Request_Data { renderer, false }

	adapter_options := wgpu.RequestAdapterOptions {
		compatibleSurface = renderer.core.surface,
		powerPreference = .HighPerformance,
	}
	log.debugf("Creating an adapter with the following options: %#v", adapter_options)
	
	wgpu.InstanceRequestAdapter(
		renderer.core.instance,
		&adapter_options,
		wgpu_request_adapter_callback,
		&request_data,
	)
	for !request_data.is_done {
		thread.yield()
	}

	renderer.core.adapter_info = wgpu.AdapterGetInfo(renderer.core.adapter)
	renderer.core.adapter_features = wgpu.AdapterEnumerateFeatures(renderer.core.adapter, vmem.arena_allocator(&renderer.arena))
	if limits, limits_ok := wgpu.AdapterGetLimits(renderer.core.adapter); !limits_ok {
		log.warnf("Could not get device limits")
	} else {
		renderer.core.adapter_limits = limits
	}

	renderer.core.surface_capabilities = wgpu.SurfaceGetCapabilities(renderer.core.surface, renderer.core.adapter)

	return renderer.core.adapter != nil
}

core_check_adapter_capabilities :: proc(renderer: ^Renderer) -> bool {
	return slice.contains(renderer.core.adapter_features, wgpu.FeatureName.MultiDrawIndirect) &&
		slice.contains(renderer.core.adapter_features, wgpu.FeatureName.TextureBindingArray) &&
		renderer.core.adapter_limits.limits.maxBindGroups >= 1
}

core_device_init :: proc(renderer: ^Renderer) -> bool {
	request_data := Device_Request_Data { renderer, false }
	
	device_descriptor := wgpu.DeviceDescriptor {
		requiredFeatureCount = 2,
		requiredFeatures = raw_data([]wgpu.FeatureName { .MultiDrawIndirect, .TextureBindingArray }),
		deviceLostCallback = wgpu_device_lost_callback,
	}
	log.debugf("Creating a device with the following descriptor: %#v", device_descriptor)
	
	wgpu.AdapterRequestDevice(
		renderer.core.adapter,
		&device_descriptor,
		wgpu_request_device_callback,
		&request_data,
	)
	for !request_data.is_done {
		thread.yield()
	}

	if limits, limits_ok := wgpu.DeviceGetLimits(renderer.core.device); !limits_ok {
		log.warnf("Could not get device limits")
	} else {
		renderer.core.device_limits = limits
	}

	renderer.core.queue = wgpu.DeviceGetQueue(renderer.core.device)

	return renderer.core.device != nil && renderer.core.queue != nil
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
	
	renderer.core.adapter = result
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
	
	renderer.core.device = result
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
