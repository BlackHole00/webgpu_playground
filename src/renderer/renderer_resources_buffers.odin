package renderer

import "base:intrinsics"
import "core:log"
import "vendor:wgpu"
import wgputils "wgpu"

Static_Buffer_Type :: enum {
	Uniform_Application_State,
	Layout_Info,
}

Dynamic_Buffer_Type :: enum {
	Model_Indices,
	Model_Vertices,
	Uniform_Pass_States,
}

Mirrored_Buffer_Type :: enum {
	Model_Info,
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
		.Uniform_Application_State = {
			usage = { .Uniform, .CopyDst },
			size = size_of(Draw_Command_Application_Uniform),
			label = "Uniform Application State",
		},
		.Layout_Info = {
			usage = { .Storage, .CopyDst },
			size = size_of(Layout_Info) * MAX_LAYOUTS,
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
		.Uniform_Pass_States = {
			usage = { .Uniform, .CopySrc, .CopyDst },
			size = size_of(Draw_Command_Application_Uniform) * 8,
			label = "Uniform Pass States",
		},
		.Model_Vertices = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Model Vertices",
		},
		.Model_Indices = {
			usage = { .Storage, .CopySrc, .CopyDst },
			label = "Model Indices",
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
			size = size_of(Draw_Command_Application_Uniform) * 8,
			label = "Uniform Pass States",
		},
	}

	for descriptor, buffer in BUFFER_DESCRIPTORS {
		if !wgputils.dynamicbuffer_create(
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

