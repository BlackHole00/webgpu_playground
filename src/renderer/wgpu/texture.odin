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

// Allocates a new texture with the same properties and copyies the content of
// an older texture to it.
// Please not that if the `keep_old_texture` parameter is set to false, the old
// texture is no longer considered safe after the function returns with a valid
// return value.
// Please note that the texture must support the .CopySrc and .CopyDst usages.
//
// Inputs:
// - texture: The old texture
// - device
// - queue
// - new_size: The new texture size. Must be non zero
// - label: The label for the new texture
// - keep_old_texture: If `false` the old texture will be released after the
//     content copy
// - view_formats: The new texture view formats. If nil the texture format will 
//     be used
//
// Results:
// - new_texture: The new texture
// - ok
//
// TODO(Vicix): Do logging
@(deprecated="Prefer using a Dynamic_Texture instead")
texture_resize :: proc(
	texture: wgpu.Texture,
	device: wgpu.Device,
	queue: wgpu.Queue,
	new_size: wgpu.Extent3D,
	label: cstring = "",
	keep_old_texture := true,
	view_formats := []wgpu.TextureFormat {},
) -> (new_texture: wgpu.Texture, ok: bool) {
	if texture == nil || device == nil || queue == nil || new_size == {} {
		return nil, false
	}

	texture_size := texture_get_size(texture)
	texture_format := wgpu.TextureGetFormat(texture)
	texture_usage := wgpu.TextureGetUsage(texture)

	if wgpu.TextureUsage.CopySrc not_in texture_usage || wgpu.TextureUsage.CopyDst not_in texture_usage {
		return nil, false
	}

	view_format_count := 1 if view_formats == nil else len(view_formats)
	view_formats := []wgpu.TextureFormat { texture_format } if view_formats == nil else view_formats

	new_texture = wgpu.DeviceCreateTexture(device, &wgpu.TextureDescriptor {
		usage = wgpu.TextureGetUsage(texture),
		dimension = wgpu.TextureGetDimension(texture),
		label = label,
		size = new_size,
		format = texture_format,
		mipLevelCount = wgpu.TextureGetMipLevelCount(texture),
		sampleCount = wgpu.TextureGetSampleCount(texture),
		viewFormatCount = (uint)(view_format_count),
		viewFormats = raw_data(view_formats),
	})
	if new_texture == nil {
		return nil, false
	}

	command_encoder := wgpu.DeviceCreateCommandEncoder(device, &wgpu.CommandEncoderDescriptor {
		label = "Texture Resize Command Encoder",
	})
	defer wgpu.CommandEncoderRelease(command_encoder)

	copy_extent := extent3D_biggest_common(texture_size, new_size)
	wgpu.CommandEncoderCopyTextureToTexture(
		command_encoder, 
		&wgpu.ImageCopyTexture {
			texture = texture,
			mipLevel = 0,
			origin = { 0, 0, 0 },
			aspect = .All,
		},
		&wgpu.ImageCopyTexture {
			texture = new_texture,
			mipLevel = 0,
			origin = { 0, 0, 0 },
			aspect = .All,
		},
		&copy_extent,
	)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder)
	defer wgpu.CommandBufferRelease(command_buffer)

	if keep_old_texture {
		wgpu.TextureReference(texture)
	}

	wgpu.QueueSubmit(queue, []wgpu.CommandBuffer{ command_buffer })
	wgpu.QueueOnSubmittedWorkDone(
		queue, 
		proc "c" (_: wgpu.QueueWorkDoneStatus, user_data: rawptr) {
			texture := (wgpu.Texture)(user_data)
			wgpu.TextureRelease(texture)
		},
		texture,
	)

	return new_texture, true
}
