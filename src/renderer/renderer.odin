package renderer

import "base:runtime"
import "core:log"
import vmem "core:mem/virtual"
import "vendor:glfw"
import "vendor:wgpu"

Descriptor :: struct {
	window: glfw.WindowHandle,
}

Renderer :: struct {
	logger: runtime.Logger,
	arena: vmem.Arena,

	window: glfw.WindowHandle,
	
	core: struct {
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
	},
	
	bind_groups: struct {
		general: wgpu.BindGroup,
		general_layout: wgpu.BindGroupLayout,
		textures: wgpu.BindGroup,
		textures_layout: wgpu.BindGroupLayout,
		skybox: wgpu.BindGroup,
		skybox_layout: wgpu.BindGroupLayout,
	},
}

create :: proc(renderer: ^Renderer, descriptor: Descriptor) -> (err: Error) {
	renderer.logger = context.logger
	renderer.window = descriptor.window
	
	if err = vmem.arena_init_growing(&renderer.arena); err != nil {
		log.errorf("Could not create a memory arena")
		return err
	}
	if descriptor.window == nil {
		log.errorf("The renderer does not support headless rendering. Please provide a valid glfw window")
		return Common_Error.Invalid_Glfw_Window
	}

	if err = core_init(renderer); err != nil {
		log.errorf("Could not initialize the renderer core: Got error %v", err)
		return err
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

	core_deinit(renderer^)

	vmem.arena_destroy(&renderer.arena)
}

resize_surface_auto :: proc(renderer: Renderer) -> bool {
	width, height := glfw.GetFramebufferSize(renderer.window)
	return resize_surface_manual(renderer, [2]uint { (uint)(width), (uint)(height) })
}

resize_surface_manual :: proc(renderer: Renderer, size: [2]uint) -> bool {
	if renderer.core.surface == nil || renderer.core.device == nil {
		return false
	}
	
	// TODO: Support for NO VSYNC and support for FifoRelaxed, if present
	wgpu.SurfaceConfigure(renderer.core.surface, &wgpu.SurfaceConfiguration {
		device = renderer.core.device,
		width = (u32)(size.x),
		height = (u32)(size.y),
		format = renderer.core.surface_capabilities.formats[0],
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
