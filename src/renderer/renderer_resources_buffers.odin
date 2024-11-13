package renderer

import "base:intrinsics"
import "core:log"
import "vendor:wgpu"
import wgputils "wgpu"

Static_Buffer_Type :: enum {
	// Holds the information specific to the current generic state of the 
	// application. It does not include any of the information related to the
	// current scenes or things to draw. Examples of values included in this
	// buffer are the current time, the viewport size, whether the application
	// is minimized...
	Application_State,
	// Holds the informations of the various vertex layouts. It is static 
	// because the renderer only supports up to 128 layouts.
	Memory_Layout_Info,
	// Holds the information of the texture atlas.
	Atlas_Info,
}

Dynamic_Buffer_Type :: enum {
	// Holds the various uber-indices of the models. The buffer is contiguous.
	// in order to find the right indices of a model it is necessary to have the
	// model info and the layout info relative to the thing it is being drawn
	Model_Indices,
	// Holds the various vertices of the models, aligned to a word (32 bit)
	Model_Vertices,
	// Holds the information relative to each draw call (including the camera 
	// index and the model index). Each draw call uses a differect section of
	// this buffer, via a dynamic offset
	Draw_Call_Info,
	// Holds the information related to each texture, most importanly its 
	// format, size and position inside the atlas
	Texture_Info,
	// Holds the view and projection matrices for every camera present in the
	// scenes
	Cameras,
	Object_Instances,
}

Mirrored_Buffer_Type :: enum {
	// Holds the information related to each model, most importantly the layout
	// used, the number of indices and the offset of the first one.
	Model_Info,
	// Holds information about each object. Most importantly its model and its
	// position
	Objects,
}

resources_init_buffers :: proc(renderer: ^Renderer) -> (ok: bool) {
	defer if !ok {
		resources_deinit_buffers(renderer)
	}

	if !resources_init_static_buffers(renderer) {
		log.errorf("Could not init the static buffers")
		return false
	}
	if !resources_init_dynamic_buffers(renderer) {
		log.errorf("Could not init the dynamic buffers")
		return false
	}
	if !resources_init_mirrored_buffers(renderer) {
		log.errorf("Could not init the mirrored buffers")
		return false
	}

	return true
}

resources_init_static_buffers :: proc(renderer: ^Renderer) -> bool {
	BUFFER_DESCRIPTORS := [Static_Buffer_Type]wgpu.BufferDescriptor {
		.Application_State = {
			usage = { .Uniform, .CopyDst },
			// TODO: Specify size better
			size = 64,
			label = "Uniform Application State",
		},
		.Memory_Layout_Info = {
			usage = { .Storage, .CopyDst },
			size = size_of(Memory_Layout_Info) * MAX_LAYOUTS,
			label = "Layout Info",
		},
		.Atlas_Info = {
			usage = { .Storage, .CopyDst },
			size = size_of(Atlas_Gpu_Info) * len(Atlas_Type),
			label = "Layout Info",
		},
	}

	for &descriptor, buffer in BUFFER_DESCRIPTORS {
		renderer.resources.static_buffers[buffer] = wgpu.DeviceCreateBuffer(
			renderer.core.device,
			&descriptor,
		)
		if renderer.resources.static_buffers[buffer] == nil {
			log.errorf("Could not initialize the required renderer static buffer: %v", buffer)
			return false
		}
	}

	return true
}

resources_init_dynamic_buffers :: proc(renderer: ^Renderer) -> bool {
	BUFFER_DESCRIPTORS := [Dynamic_Buffer_Type]wgpu.BufferDescriptor {
		.Draw_Call_Info = {
			usage = { .Uniform, .CopySrc, .CopyDst },
			label = "Draw Call Info",
		},
		.Model_Vertices = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Model Vertices",
		},
		.Model_Indices = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Model Indices",
		},
		.Texture_Info = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Texture Info",
		},
		.Cameras = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Cameras Info",
			size = 256,
		},
		.Object_Instances = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Object Instances",
		},
	}

	for descriptor, buffer in BUFFER_DESCRIPTORS {
		if !wgputils.dynamicbuffer_create(
			&renderer.resources.dynamic_buffers[buffer],
			renderer.core.device,
			renderer.core.queue,
			descriptor,
		) {
			log.errorf("Could not initialize the required dynamic renderer buffer: %v", buffer)
			return false
		}
	}

	return true
}

resources_init_mirrored_buffers :: proc(renderer: ^Renderer) -> bool {
	BUFFER_DESCRIPTORS := [Mirrored_Buffer_Type]wgpu.BufferDescriptor {
		.Model_Info = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Model Info",
		},
		.Objects = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Objects Info",
			size = 256,
		},
	}

	for descriptor, buffer in BUFFER_DESCRIPTORS {
		if !wgputils.mirroredbuffer_create(
			&renderer.resources.mirrored_buffers[buffer],
			renderer.core.device,
			renderer.core.queue,
			descriptor,
		) {
			log.errorf("Could not initialize the required dynamic mirrored buffer: %v", buffer)
			return false
		}
	}

	return true
}

resources_deinit_buffers :: proc(renderer: ^Renderer) {
	for type in Static_Buffer_Type {
		if buffer := renderer_get_static_buffer(renderer^, type); buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	for type in Dynamic_Buffer_Type {
		buffer := renderer_get_dynamic_buffer(renderer, type)
		wgputils.dynamicbuffer_destroy(buffer^)
	}
	for type in Mirrored_Buffer_Type {
		buffer := renderer_get_mirrored_buffer(renderer, type)
		wgputils.mirroredbuffer_destroy(buffer^)
	}
}

