package renderer

import wgpuutils "wgpu"
import "base:runtime"
import "core:log"
import vmem "core:mem/virtual"
import "vendor:glfw"
import "vendor:wgpu"
import ui "vendor:microui"

Descriptor :: struct {
	window: glfw.WindowHandle,
	ui_context: ^ui.Context,
	clear_color: wgpu.Color,
}

Renderer :: struct {
	logger: runtime.Logger,
	arena: vmem.Arena,

	external: struct {
		window: glfw.WindowHandle,
		ui_context: ^ui.Context,
	},

	properties: struct {
		clear_color: wgpu.Color,
	},

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
	
	resources: struct {
		buffers: [Buffer_Type]wgpu.Buffer,

		textures: [Texture_Type]wgpu.Texture,
		samplers: [Sampler_Type]wgpu.Sampler,

		vertex_layouts: [Vertex_Layout_Type]wgpu.VertexBufferLayout,
		bindgroup_layouts: [Bindgroup_Type]wgpu.BindGroupLayout,
		bindgroups: [Bindgroup_Type]wgpu.BindGroup,
		pipelines: [Render_Pipeline_Type]wgpu.RenderPipeline,
	},

	frame: struct {
		surface_texture: wgpu.SurfaceTexture,
		command_encoder: wgpu.CommandEncoder,
		render_pass: wgpu.RenderPassEncoder,
	},
}

create :: proc(renderer: ^Renderer, descriptor: Descriptor) -> (err: Error) {
	renderer.logger = context.logger
	renderer.properties.clear_color = descriptor.clear_color
	renderer.external.window = descriptor.window
	renderer.external.ui_context = descriptor.ui_context
	
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

	if err = resources_init(renderer); err != nil {
		log.errorf("Could not initialize the renderer resources: Got error %v", err)
		return err
	}
	
	resize_surface(renderer)
	
	return nil
}

destroy :: proc(renderer: ^Renderer) {
	resources_deinit(renderer)
	core_deinit(renderer^)

	vmem.arena_destroy(&renderer.arena)
}

resize_surface_auto :: proc(renderer: ^Renderer) -> bool {
	width, height := glfw.GetFramebufferSize(renderer.external.window)
	return resize_surface_manual(renderer, [2]uint { (uint)(width), (uint)(height) })
}

resize_surface_manual :: proc(renderer: ^Renderer, size: [2]uint) -> bool {
	if renderer.core.surface == nil || renderer.core.device == nil {
		return false
	}
	
	if new_depth_texture, ok := wgpuutils.texture_resize(
		renderer.resources.textures[.Surface_Depth],
		renderer.core.device,
		renderer.core.queue,
		wgpu.Extent3D { (u32)(size.x), (u32)(size.y), 1 },
		"Surface Depth Buffer",
		false,
	); ok {
		renderer.resources.textures[.Surface_Depth] = new_depth_texture
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
