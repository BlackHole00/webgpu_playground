package renderer_wgpu

import "base:runtime"
import "core:log"
import "core:math"
import "core:slice"
import "vendor:wgpu"
import "shared:utils"

Dynamic_Buffer :: struct {
	allocator: runtime.Allocator,
	device: wgpu.Device,
	queue: wgpu.Queue,
	handle: wgpu.Buffer,
	label: cstring,
	length: uint,
	capacity: uint,
}

dynamicbuffer_create :: proc(
	buffer: ^Dynamic_Buffer,
	device: wgpu.Device,
	queue: wgpu.Queue,
	descriptor: wgpu.BufferDescriptor,
	allocator := context.allocator,
) -> bool {
	descriptor := descriptor

	if wgpu.BufferUsage.CopySrc not_in descriptor.usage || wgpu.BufferUsage.CopyDst not_in descriptor.usage {
		log.errorf(
			"The provided Dynamic Buffer usages for buffer %s are not valid. A Dynamic Buffer requires the usages " +
			"{{ .CopySrc, .CopyDst }}. Found usages %v instead",
			descriptor.label,
			descriptor.usage,
		)
		return false
	}

	label := utils.cstring_clone(descriptor.label)

	descriptor.label = label
	descriptor.size = max(64, descriptor.size)

	buffer.allocator = allocator
	buffer.handle = wgpu.DeviceCreateBuffer(device, &descriptor)
	buffer.label = label
	buffer.capacity = (uint)(descriptor.size)
	buffer.length = 0
	buffer.device = device
	buffer.queue = queue

	return buffer.handle != nil
}

dynamicbuffer_destroy :: proc(buffer: Dynamic_Buffer) {
	if buffer.handle != nil {
		wgpu.BufferDestroy(buffer.handle)
		wgpu.BufferRelease(buffer.handle)
	}
	delete(buffer.label, buffer.allocator)
}

dynamicbuffer_as_buffer :: proc(buffer: Dynamic_Buffer) -> wgpu.Buffer {
	return buffer.handle
}

dynamicbuffer_len :: proc(buffer: Dynamic_Buffer) -> uint {
	return buffer.length
}

dynamicbuffer_cap :: proc(buffer: Dynamic_Buffer) -> uint {
	return buffer.capacity
}

dynamicbuffer_resize :: proc(buffer: ^Dynamic_Buffer, length: uint) -> bool {
	if !dynamicbuffer_ensure_capacity(buffer, length) {
		return false
	}

	buffer.length = length
	return true
}

dynamicbuffer_append_slice :: proc(buffer: ^Dynamic_Buffer, data: []$T) -> bool {
	return dynamicbuffer_append_bytes(buffer, slice.to_bytes(data))
}

dynamicbuffer_append_bytes :: proc(buffer: ^Dynamic_Buffer, data: []byte) -> bool {
	old_length := buffer.length
	if !dynamicbuffer_resize(buffer, buffer.length + len(data)) {
		return false
	}

	wgpu.QueueWriteBuffer(buffer.queue, buffer.handle, (u64)(old_length), raw_data(data), len(data))

	return true
}

dynamicbuffer_append_value :: proc(buffer: ^Dynamic_Buffer, value: ^$T) -> bool {
	return dynamicbuffer_append_bytes(slice.from_ptr(value, 1))
}

dynamicbuffer_append_buffer :: proc(
	buffer: ^Dynamic_Buffer,
	source: wgpu.Buffer,
	offset: uint,
	length: uint,
) -> bool {
	old_length := buffer.length
	if !dynamicbuffer_resize(buffer, buffer.length + length) {
		return false
	}

	command_encoder := wgpu.DeviceCreateCommandEncoder(buffer.device, &wgpu.CommandEncoderDescriptor {
		label = buffer.label,
	})
	defer wgpu.CommandEncoderRelease(command_encoder)
	if command_encoder == nil {
		return false
	}

	wgpu.CommandEncoderCopyBufferToBuffer(
		command_encoder,
		source,
		(u64)(offset),
		buffer.handle,
		(u64)(old_length),
		(u64)(length),
	)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder)
	defer wgpu.CommandBufferRelease(command_buffer)
	if command_buffer == nil {
		return false
	}

	wgpu.QueueSubmit(buffer.queue, { command_buffer })

	return true
}

dynamicbuffer_append :: proc {
	dynamicbuffer_append_bytes,
	dynamicbuffer_append_slice,
	dynamicbuffer_append_buffer,
}

dynamicbuffer_reserve :: proc(buffer: ^Dynamic_Buffer, capacity: uint) -> bool {
	usages := wgpu.BufferGetUsage(buffer.handle)
	new_buffer := wgpu.DeviceCreateBuffer(buffer.device, &wgpu.BufferDescriptor {
		label = buffer.label,
		usage = usages,
		size = (u64)(capacity),
	})
	if new_buffer == nil {
		log.warnf("A Dynamic Buffer %s failed to resize", buffer.label)
		return false
	}

	command_encoder := wgpu.DeviceCreateCommandEncoder(buffer.device, &wgpu.CommandEncoderDescriptor {
		label = "Dynamic Buffer Resize Copy Buffer",
	})
	defer wgpu.CommandEncoderRelease(command_encoder)
	if command_encoder == nil {
		return false
	}

	wgpu.CommandEncoderCopyBufferToBuffer(
		command_encoder,
		buffer.handle,
		0,
		new_buffer,
		0,
		(u64)(min(buffer.capacity, capacity)),
	)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder)
	defer wgpu.CommandBufferRelease(command_buffer)
	if command_buffer == nil {
		return false
	}

	wgpu.QueueSubmit(buffer.queue, { command_buffer })
	wgpu.QueueOnSubmittedWorkDone(buffer.queue, dynamicbuffer_delete_buffer_after_copy_callback, buffer.handle)

	buffer.handle = new_buffer
	buffer.length = min(buffer.length, capacity)
	buffer.capacity = capacity
	return true
}

@(private="file")
dynamicbuffer_ensure_capacity :: proc(
	buffer: ^Dynamic_Buffer,
	capacity: uint,
) -> bool {
	if buffer.capacity < capacity {
		return dynamicbuffer_reserve(buffer, (uint)(math.next_power_of_two((int)(capacity))))
	}

	return true
}

@(private="file")
dynamicbuffer_delete_buffer_after_copy_callback :: proc "c" (status: wgpu.QueueWorkDoneStatus, userdata: rawptr) {
	old_buffer := (wgpu.Buffer)(userdata)
	wgpu.BufferDestroy(old_buffer)
	wgpu.BufferRelease(old_buffer)
}

