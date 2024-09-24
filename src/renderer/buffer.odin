package renderer

import "vendor:wgpu"

Buffer_Type :: enum {
	// Staging_MicroUI,
	Vertex_MicroUI,
	Index_MicroUI,
	// Index_MicroUI,
	Uniform_Draw_Command_Application,
	Uniform_Draw_Command_Instance,
}

Buffer_Handle :: struct {
	renderer: ^Renderer,
	type: Buffer_Type,
}

handle_as_buffer :: proc(handle: Buffer_Handle) -> wgpu.Buffer {
	return handle.renderer.resources.buffers[handle.type]
}
