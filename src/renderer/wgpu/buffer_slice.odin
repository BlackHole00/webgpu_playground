package renderer_wgpu

import "core:log"
import "vendor:wgpu"

Buffer_Slice :: struct {
	buffer: Generic_Buffer,
	offset: u64, // inclusive
	length: u64, // exclusive
}

bufferslice_create :: proc(
	slice: ^Buffer_Slice,
	source: Generic_Buffer,
	offset: u64,
	length: u64,
	location := #caller_location,
) {
	offset := offset
	length := length

	size := genericbuffer_get_size(source)
	if (u64)(offset) >= size || (u64)(offset + length) > size {
		log.warnf(
			"The provided bounds [%d:%d] is not valid: the buffer can only be indexed with values [0:%d]. The bounds " +
			"will be adjusted accordingly",
			offset,
			length,
			size,
			location = location,
		)

		offset = min(offset, size - 1)
		length = min(length, size)
	}

	slice.buffer = source
	slice.offset = offset
	slice.length = length
}

bufferslice_get_size :: proc(slice: Buffer_Slice) -> u64 {
	return slice.length
}

bufferslice_queue_write :: proc(
	slice: Buffer_Slice,
	queue: wgpu.Queue,
	offset: u64,
	data: rawptr,
	size: uint,
	location := #caller_location,
) {
	size := size

	if offset >= slice.length {
		log.errorf(
			"The provided slice write offset %d is not contained in the slice bounds ([%d:%d]). This write request " +
			"will be ignored",
			offset,
			size,
			slice.offset,
			slice.length,
			location = location,
		)
		return
	}
	if offset + (u64)(size) > slice.length {
		log.warnf(
			"The slice write with offset %d and size %d would end up overflowing the slice bounds ([%d:%d]). The " +
			"size will be adjusted accordingly",
			offset,
			size,
			slice.offset,
			slice.length,
			location = location,
		)

		size = (uint)(bufferslice_get_size(slice))
	}

	actual_offset := slice.offset + offset

	switch v in slice.buffer {
	case Static_Buffer: 
		wgpu.QueueWriteBuffer(
			queue,
			v,
			actual_offset,
			data,
			size,
		)

	case ^Dynamic_Buffer:
		dynamicbuffer_queue_write(v, actual_offset, data, size)

	case ^Mirrored_Buffer:
		mirroredbuffer_queue_write(v, actual_offset, data, size)
	}
}

