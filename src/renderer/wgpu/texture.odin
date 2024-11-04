package renderer_wgpu

import "vendor:wgpu"

texture_get_size :: proc(texture: wgpu.Texture) -> wgpu.Extent3D {
	if texture == nil {
		return {}
	}

	return wgpu.Extent3D {
		width = wgpu.TextureGetWidth(texture),
		height = wgpu.TextureGetHeight(texture),
		depthOrArrayLayers = wgpu.TextureGetDepthOrArrayLayers(texture),
	}
}

