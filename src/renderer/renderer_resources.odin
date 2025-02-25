package renderer

import "shared:wgpu"

Renderer_Resources :: struct {
	vertex_buffer: wgpu.Buffer,
	index_buffer: wgpu.Buffer,
}

rendererresources_create :: proc(resources: ^Renderer_Resources) -> (res: Renderer_Result) {
	return nil
}

rendererresources_destroy :: proc(resources: Renderer_Resources) {
}



