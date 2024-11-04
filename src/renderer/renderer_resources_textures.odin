package renderer

import "core:log"
import "vendor:glfw"
import "vendor:wgpu"
import wgputils "wgpu"

Static_Texture_Type :: enum {
}

Dynamic_Texture_Type :: enum {
	Surface_Depth_Buffer,
	Texture_Atlas,
}

resources_init_textures :: proc(renderer: ^Renderer) -> (ok: bool) {
	defer if !ok {
		resources_deinit_textures(renderer^)
	}

	if !resources_init_static_textures(renderer) {
		log.errorf("Could not init the static textures")
		return false
	}
	if !resources_init_dynamic_textures(renderer) {
		log.errorf("Could not init the dynamic textures")
		return false
	}

	return true
}

resources_deinit_textures :: proc(renderer: Renderer) {
	for texture in renderer.resources.static_textures {
		if texture != nil {
			wgpu.TextureDestroy(texture)
			wgpu.TextureRelease(texture)
		}
	}

	for texture in renderer.resources.dynamic_textures {
		wgputils.dynamictexture_destroy(texture)
	}
}

resources_init_static_textures :: proc(renderer: ^Renderer) -> bool {
	TEXTURE_DESCRIPTORS := [Static_Texture_Type]wgpu.TextureDescriptor {}

	for &descriptor, texture in TEXTURE_DESCRIPTORS {
		renderer.resources.static_textures[texture] = wgpu.DeviceCreateTexture(
			renderer.core.device,
			&descriptor,
		)
		if renderer.resources.static_textures[texture] == nil {
			log.errorf("Could not initialize the required static texture: %v", texture)
			return false
		}
	}

	return true
}

resources_init_dynamic_textures :: proc(renderer: ^Renderer) -> bool {
	window_width, window_heigth := glfw.GetWindowSize(renderer.external.window)

	TEXTURE_DESCRIPTORS := [Dynamic_Texture_Type]wgpu.TextureDescriptor {
		.Surface_Depth_Buffer = wgpu.TextureDescriptor {
			usage = { .CopySrc, .CopyDst, .RenderAttachment },
			dimension = ._2D,
			size = { (u32)(window_width), (u32)(window_heigth), 1 },
			format = DEPTH_BUFFER_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
			viewFormatCount = 1,
			viewFormats = raw_data([]wgpu.TextureFormat {
				DEPTH_BUFFER_FORMAT,
			}),
			label = "Surface Depth Buffer",
		},
		.Texture_Atlas = wgpu.TextureDescriptor {
			usage = { .TextureBinding, .CopySrc, .CopyDst },
			dimension = ._2D,
			size = { 2048, 2048, 1 },
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
			viewFormatCount = 1,
			viewFormats = raw_data([]wgpu.TextureFormat {
				.RGBA8Unorm,
			}),
			label = "Texture Atlas",
		},
	}

	for descriptor, texture in TEXTURE_DESCRIPTORS {
		if !wgputils.dynamictexture_create(
			&renderer.resources.dynamic_textures[texture],
			renderer.core.device,
			renderer.core.queue,
			descriptor,
		) {
			log.errorf("Could not initialize the required dynamic texture: %v", texture)
			return false
		}
	}

	return true
}

