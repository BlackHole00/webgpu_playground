package renderer_wgpu

import "base:runtime"
import "core:slice"
import "core:log"
import "vendor:wgpu"
import "shared:utils"

Mirrored_Buffer :: struct {
	using gpu_buffer: Dynamic_Buffer,
	cpu_buffer: [dynamic]byte,
}

mirroredbuffer_create :: proc(
	buffer: ^Mirrored_Buffer,
	device: wgpu.Device,
	queue: wgpu.Queue,
	descriptor: wgpu.BufferDescriptor,
	allocator := context.allocator,
) -> bool {
	descriptor := descriptor

	if wgpu.BufferUsage.CopySrc not_in descriptor.usage || wgpu.BufferUsage.CopyDst not_in descriptor.usage {
		log.errorf(
			"The provided Mirrored Buffer usages for buffer %s are not valid. A Mirrored Buffer requires the usages " +
			"{{ .CopySrc, .CopyDst }}. Found usages %v instead",
			descriptor.label,
			descriptor.usage,
		)
		return false
	}

	descriptor.size = max(64, descriptor.size)

	if !dynamicbuffer_create(&buffer.gpu_buffer, device, queue, descriptor, allocator) {
		log.errorf(
			"Could not create the Mirrored Buffer %s: Could not create its corrisponding gpu-side buffer",
			descriptor.label,
		)
		return false
	}

	buffer.cpu_buffer = make([dynamic]byte, 0, descriptor.size, allocator)

	return true
}

mirroredbuffer_destroy :: proc(buffer: Mirrored_Buffer) {
	dynamicbuffer_destroy(buffer.gpu_buffer)
	delete(buffer.cpu_buffer)
}

mirroredbuffer_reserve :: proc(buffer: ^Mirrored_Buffer, capacity: uint) -> bool {
	if !dynamicbuffer_reserve(&buffer.gpu_buffer, capacity) {
		log.warnf(
			"Could not resize the Mirrored Buffer %s: Could not resize its corrisponding gpu-side buffer",
			buffer.label,
		)
		return false
	}

	reserve(&buffer.cpu_buffer, capacity)
	return true
}

mirroredbuffer_resize :: proc(buffer: ^Mirrored_Buffer, length: uint) -> bool {
	if !dynamicbuffer_resize(&buffer.gpu_buffer, length) {
		log.warnf(
			"Could not resize the Mirrored Buffer %s: Could not resize its corrisponding gpu-side buffer",
			buffer.label,
		)
		return false
	}

	resize(&buffer.cpu_buffer, length)
	return true
}

mirroredbuffer_append_bytes :: proc(buffer: ^Mirrored_Buffer, data: []byte) -> bool {
	if !dynamicbuffer_append_slice(&buffer.gpu_buffer, data) {
		log.warnf(
			"Could not append to the Mirrored Buffer %s: Could not append to the corrisponding gpu-side buffer",
			buffer.label,
		)
		return false
	}

	for byte in data {
		append(&buffer.cpu_buffer, byte)
	}
	return true
}

mirroredbuffer_append_slice :: proc(buffer: ^Mirrored_Buffer, data: []$T) -> bool {
	return mirroredbuffer_append_bytes(buffer, slice.to_bytes(data))
}

mirroredbuffer_append_value :: proc(buffer: ^Mirrored_Buffer, value: ^$T) -> bool {
	return mirroredbuffer_append_slice(buffer, slice.from_ptr(value, 1))
}

mirroredbuffer_append :: proc {
	mirroredbuffer_append_value,
	mirroredbuffer_append_slice,
	mirroredbuffer_append_bytes,
}

mirroredbuffer_forcesync_gpu_with_cpu :: proc(buffer: Mirrored_Buffer) {
	wgpu.QueueWriteBuffer(
		buffer.queue,
		buffer.handle,
		0,
		raw_data(buffer.cpu_buffer),
		len(buffer.cpu_buffer),
	)
}

mirroredbuffer_sync_cpu_with_gpu :: proc(buffer: ^Mirrored_Buffer) -> ^utils.Promise(bool) {
	Buffer_Map_Data :: struct {
		promise: ^utils.Promise(bool),
		staging_buffer: wgpu.Buffer,
		mirrored_buffer: ^Mirrored_Buffer,
	}
	buffer_map_callback :: proc "c" (status: wgpu.BufferMapAsyncStatus, userdata: rawptr) {
		context = runtime.default_context()
		data := (^Buffer_Map_Data)(userdata)

		if status != .Success {
			log.warnf(
				"Could not update the Mirrored Buffer %s from the GPU to the CPU: Could not map the buffer",
				data.mirrored_buffer.label,
			)
			utils.promise_resolve(data.promise, false)
		}

		// TODO(Vicix): Move outside of callback
		mapped_data := wgpu.BufferGetMappedRange(
			data.staging_buffer,
			0,
			(uint)(wgpu.BufferGetSize(data.staging_buffer)),
		)
		copy(data.mirrored_buffer.cpu_buffer[:], mapped_data)

		utils.promise_resolve(data.promise, true)
		return
	}

	staging_buffer := wgpu.DeviceCreateBuffer(buffer.device, &wgpu.BufferDescriptor {
		label = "Staging Mirrored Buffer GPU to CPU",
		usage = { .MapRead, .CopyDst },
		size = (u64)(len(buffer.cpu_buffer)),
	})
	defer wgpu.BufferRelease(staging_buffer)
	defer wgpu.BufferDestroy(staging_buffer)

	encoder := wgpu.DeviceCreateCommandEncoder(buffer.device, &wgpu.CommandEncoderDescriptor {
		label = "Mirrored Buffer GPU to CPU Command Encoder",
	})
	defer wgpu.CommandEncoderRelease(encoder)

	wgpu.CommandEncoderCopyBufferToBuffer(encoder, buffer.handle, 0, staging_buffer, 0, (u64)(len(buffer.cpu_buffer)))
	command := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor {
		label = "Mirrored Buffer GPU to CPU Command",
	})
	defer wgpu.CommandBufferRelease(command)

	promise := utils.promise_new(bool, buffer.allocator)

	map_data := new(Buffer_Map_Data, buffer.allocator)
	map_data.promise = promise
	map_data.staging_buffer = staging_buffer
	map_data.mirrored_buffer = buffer
	
	wgpu.BufferMapAsync(
		staging_buffer,
		{ .Read },
		0,
		len(buffer.cpu_buffer),
		buffer_map_callback,
		map_data,
	)

	return promise
}

mirroredbuffer_len :: proc(buffer: Mirrored_Buffer) -> uint {
	return len(buffer.cpu_buffer)
}

mirroredbuffer_cap :: proc(buffer: Mirrored_Buffer) -> uint {
	return cap(buffer.cpu_buffer)
}
