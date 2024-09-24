package renderer_wgpu

import "vendor:wgpu"

extent3D_biggest_common :: proc(a, b: wgpu.Extent3D) -> (res: wgpu.Extent3D) {
	res.width = min(a.width, b.width)
	res.height = min(a.height, b.height)
	res.depthOrArrayLayers = min(a.depthOrArrayLayers, b.depthOrArrayLayers)
	return
}
