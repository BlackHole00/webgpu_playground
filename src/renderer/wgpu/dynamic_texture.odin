package renderer_wgpu

import "core:log"
import "vendor:wgpu"

Dynamic_Texture :: struct {
	handle: wgpu.Texture,
	size: wgpu.Extent3D,
	memory_size: wgpu.Extent3D,
	device: wgpu.Device,
	queue: wgpu.Queue,
	view_format: Maybe(wgpu.TextureFormat),
}

dynamictexture_create :: proc(
	texture: ^Dynamic_Texture,
	device: wgpu.Device,
	queue: wgpu.Queue,
	descriptor: wgpu.TextureDescriptor,
) -> bool {
	descriptor := descriptor

	if wgpu.TextureUsage.CopySrc not_in descriptor.usage || wgpu.TextureUsage.CopyDst not_in descriptor.usage {
		log.errorf(
			"The provided Dynamic Texture usages are not valid. A Dynamic Texture requires the usages {{ .CopySrc, .CopyDst }}. Found usages %v instead",
			descriptor.usage,
		)
		return false
	}
	if descriptor.viewFormatCount != 1 {
		log.warnf(
			"The provided Dynamic Texture View Formats are not valid. A Dynamic Texture only supports one view format: expected 1 format, found %d",
			descriptor.viewFormatCount,
		)
	}
	if descriptor.label != nil {
		log.warnf("The provided Dynamic Texture descriptor contains a label. Dynamic Textures do not support labels")
	}

	descriptor.label = "Dynamic Texture"
	descriptor.size = wgpu.Extent3D {
		max(32, descriptor.size.width),
		max(32, descriptor.size.height),
		max(1, descriptor.size.depthOrArrayLayers),
	}
	
	texture.handle = wgpu.DeviceCreateTexture(device, &descriptor)
	texture.size = wgpu.Extent3D { 0, 0, 1 }
	texture.memory_size = descriptor.size
	texture.device = device
	texture.queue = queue
	texture.view_format = descriptor.viewFormats[0] if descriptor.viewFormatCount > 0 else nil

	return texture.handle != nil
}

dynamictexture_destroy :: proc(texture: Dynamic_Texture) {
	if texture.handle != nil {
		wgpu.TextureDestroy(texture.handle)
		wgpu.TextureRelease(texture.handle)
	}
}

dynamictexture_as_texture :: proc(texture: Dynamic_Texture) -> wgpu.Texture {
	return texture.handle
}

dynamictexture_get_size :: proc(texture: Dynamic_Texture) -> wgpu.Extent3D {
	return texture_get_size(texture.handle)
}

dynamictexture_resize :: proc(texture: ^Dynamic_Texture, memory_size: wgpu.Extent3D, keep_contents := false) -> bool {
	texture_size := texture_get_size(texture.handle)
	texture_format := wgpu.TextureGetFormat(texture.handle)

	texture_view_format, texture_has_view_format := texture.view_format.?

	view_format_count := 1 if texture_has_view_format else 0
	view_formats := []wgpu.TextureFormat { texture_view_format } if texture_has_view_format else []wgpu.TextureFormat {}

	new_texture := wgpu.DeviceCreateTexture(texture.device, &wgpu.TextureDescriptor {
		usage = wgpu.TextureGetUsage(texture.handle),
		dimension = wgpu.TextureGetDimension(texture.handle),
		label = "Dynamic Texture",
		size = memory_size,
		format = texture_format,
		mipLevelCount = wgpu.TextureGetMipLevelCount(texture.handle),
		sampleCount = wgpu.TextureGetSampleCount(texture.handle),
		viewFormatCount = (uint)(view_format_count),
		viewFormats = raw_data(view_formats),
	})
	if new_texture == nil {
		return false
	}

	if keep_contents {
		command_encoder := wgpu.DeviceCreateCommandEncoder(texture.device, &wgpu.CommandEncoderDescriptor {
			label = "Texture Resize Command Encoder",
		})
		if command_encoder == nil {
			return false
		}
		defer wgpu.CommandEncoderRelease(command_encoder)

		copy_extent := extent3D_biggest_common(texture_size, memory_size)
		wgpu.CommandEncoderCopyTextureToTexture(
			command_encoder, 
			&wgpu.ImageCopyTexture {
				texture = texture.handle,
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
		if command_buffer == nil {
			return false
		}
		defer wgpu.CommandBufferRelease(command_buffer)

		wgpu.QueueSubmit(texture.queue, []wgpu.CommandBuffer{ command_buffer })
		wgpu.QueueOnSubmittedWorkDone(
			texture.queue,
			proc "c" (_: wgpu.QueueWorkDoneStatus, user_data: rawptr) {
				texture := (wgpu.Texture)(user_data)
				wgpu.TextureDestroy(texture)
				wgpu.TextureRelease(texture)
			},
			texture,
		)
	}

	texture.handle = new_texture
	texture.memory_size = extent3D_biggest_common(texture.memory_size, memory_size)
	if !keep_contents {
		texture.size = { 0, 0, 0 }
	}
	return true
}

dynamictexture_write :: proc(
	texture: Dynamic_Texture,
	origin: wgpu.Origin3D,
	aspect: wgpu.TextureAspect,
	size: wgpu.Extent3D,
	data: []byte,
	bytes_per_row: uint = 4,
) {
	size := size

	wgpu.QueueWriteTexture(
		texture.queue,
		&wgpu.ImageCopyTexture {
			texture = texture.handle,
			mipLevel = 0,
			origin = origin,
			aspect = aspect,
		},
		raw_data(data),
		len(data),
		&wgpu.TextureDataLayout {
			offset = 0,
			bytesPerRow = (u32)(bytes_per_row) * size.width,
			rowsPerImage = (u32)(bytes_per_row) * size.height,
		},
		&size,
	)
}
