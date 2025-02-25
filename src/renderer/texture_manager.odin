package renderer

import "shared:wgpu"

Texture_Manager :: struct {
	textures: [Texture_Manager_Texture_Type]wgpu.Texture,
}

texturemanager_create :: proc(manager: ^Texture_Manager, core: Renderer_Core) -> (res: Renderer_Result) {
	return nil
}

Texture_Manager_Texture_Type :: enum {
	R8,
	RG8,
	RGBA8,
}


