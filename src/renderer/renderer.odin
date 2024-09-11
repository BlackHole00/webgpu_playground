package renderer

import "base:runtime"
import "core:log"
import vmem "core:mem/virtual"
import la "core:math/linalg"
import "vendor:glfw"
import "vendor:wgpu"

Basic_Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

Basic_Instance_Data :: struct {
	model: [4]f32,
}

General_State_Uniform :: struct {
	time: f32,
	viewport_size: [2]u32,
}

Instance_State_Uniform :: struct {
	view: la.Matrix4x4f32,
	projection: la.Matrix4x4f32,
}

Common_Error :: enum {
	Invalid_Glfw_Window,
	Instance_Creation_Failed,
	Surface_Creation_Failed,
	Adapter_Creation_Failed,
	Device_Creation_Failed,
	Bind_Group_Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Adapter_Does_Not_Support_Necessary_Features,
}

Error :: union #shared_nil {
	runtime.Allocator_Error,
	Common_Error,
}

Renderer_Descriptor :: struct {
	window: glfw.WindowHandle,
}

Renderer :: struct {
	logger: runtime.Logger,
	arena: vmem.Arena,

	window: glfw.WindowHandle,
	
	instance: wgpu.Instance,
	surface: wgpu.Surface,
	surface_capabilities: wgpu.SurfaceCapabilities,
	adapter: wgpu.Adapter,
	adapter_info: wgpu.AdapterInfo,
	adapter_limits: wgpu.SupportedLimits,
	adapter_features: []wgpu.FeatureName,
	device: wgpu.Device,
	device_limits: wgpu.SupportedLimits,
	device_features: []wgpu.FeatureName,
	queue: wgpu.Queue,
	
	bind_groups: struct {
		general: wgpu.BindGroup,
		general_layout: wgpu.BindGroupLayout,
		textures: wgpu.BindGroup,
		textures_layout: wgpu.BindGroupLayout,
		skybox: wgpu.BindGroup,
		skybox_layout: wgpu.BindGroupLayout,
	},
}

create :: proc(renderer: ^Renderer, descriptor: Renderer_Descriptor) -> (err: Error) {
	renderer.logger = context.logger
	renderer.window = descriptor.window
	
	if err := vmem.arena_init_growing(&renderer.arena); err != nil {
		log.errorf("Could not create a memory arena")
		return err
	}
	
	if descriptor.window == nil {
		log.errorf("The renderer does not support headless rendering. Please provide a valid glfw window")
		return Common_Error.Invalid_Glfw_Window
	}
	if !renderer_check_glfw_window(renderer.window) {
		log.errorf("The provided window does have a context registered. Please provide a glfw window with the GLFW_CLIENT_API=GLFW_NO_API window hint")
		return Common_Error.Invalid_Glfw_Window
	}
	
	if !renderer_init_instance(renderer) {
		log.errorf("Could not create a wgpu instance")
		return Common_Error.Instance_Creation_Failed
	}
	defer if err != nil do wgpu.InstanceRelease(renderer.instance)
	
	if !renderer_init_surface(renderer) {
		log.errorf("Could not create a wgpu surface")
		return Common_Error.Surface_Creation_Failed
	}
	defer if err != nil do wgpu.SurfaceRelease(renderer.surface)

	if !renderer_init_adapter(renderer) {
		log.errorf("Could not create a wgpu adapter")
		return Common_Error.Adapter_Creation_Failed
	}
	defer if err != nil do wgpu.AdapterRelease(renderer.adapter)

	log.debugf("Got adapter with properties:\t%#v", renderer.adapter_info)
	log.debugf("Got adapter with limits:\t%#v", renderer.adapter_limits)
	log.debugf("Got adapter with features:\t%#v", renderer.adapter_features)
	
	if !renderer_check_adapter_capabilities(renderer) {
		log.errorf("The adapter does not support the necessary features")
		return Common_Error.Adapter_Does_Not_Support_Necessary_Features
	}

	if !renderer_init_device(renderer) {
		log.errorf("Could not create a device")
		return Common_Error.Device_Creation_Failed
	}
	defer if err != nil {
		wgpu.QueueRelease(renderer.queue)
		wgpu.DeviceRelease(renderer.device)	
	}
	
	if !renderer_init_bind_group_layouts(renderer) {
		log.errorf("Could not create bind group layouts")
		return Common_Error.Bind_Group_Layout_Creation_Failed
	}
	defer if err != nil {
		wgpu.BindGroupLayoutRelease(renderer.bind_groups.general_layout)
		wgpu.BindGroupLayoutRelease(renderer.bind_groups.textures_layout)
	}

	if !renderer_init_pipelines(renderer) {
		log.errorf("Could not create the pipelines")
		return Common_Error.Pipeline_Creation_Failed
	}
	defer if err != nil {
		// wgpu.RenderPipelineRelease(renderer.)
	}
		
	resize_surface(renderer^)
	
	return nil
}

destroy :: proc(renderer: ^Renderer) {
	wgpu.BindGroupLayoutRelease(renderer.bind_groups.general_layout)
	wgpu.BindGroupLayoutRelease(renderer.bind_groups.textures_layout)
	wgpu.QueueRelease(renderer.queue)
	wgpu.DeviceRelease(renderer.device)
	wgpu.SurfaceCapabilitiesFreeMembers(renderer.surface_capabilities)
	wgpu.AdapterInfoFreeMembers(renderer.adapter_info)
	wgpu.AdapterRelease(renderer.adapter)
	wgpu.SurfaceRelease(renderer.surface)
	wgpu.InstanceRelease(renderer.instance)

	vmem.arena_destroy(&renderer.arena)
}

resize_surface_auto :: proc(renderer: Renderer) -> bool {
	width, height := glfw.GetFramebufferSize(renderer.window)
	return resize_surface_manual(renderer, [2]uint { (uint)(width), (uint)(height) })
}

resize_surface_manual :: proc(renderer: Renderer, size: [2]uint) -> bool {
	if renderer.surface == nil || renderer.device == nil {
		return false
	}
	
	// TODO: Support for NO VSYNC and support for FifoRelaxed, if present
	wgpu.SurfaceConfigure(renderer.surface, &wgpu.SurfaceConfiguration {
		device = renderer.device,
		width = (u32)(size.x),
		height = (u32)(size.y),
		format = renderer.surface_capabilities.formats[0],
		usage = { .RenderAttachment },
		presentMode = .Fifo,
		alphaMode = .Auto,
	})

	return true
}

resize_surface :: proc {
	resize_surface_manual,
	resize_surface_auto,
}
