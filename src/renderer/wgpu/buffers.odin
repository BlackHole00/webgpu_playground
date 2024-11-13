package renderer_wgpu

import "vendor:wgpu"

Static_Buffer :: wgpu.Buffer

Generic_Buffer :: union #no_nil {
	Static_Buffer,
	^Dynamic_Buffer,
	^Mirrored_Buffer,
}

genericbuffer_get_handle :: proc(buffer: Generic_Buffer) -> wgpu.Buffer {
	switch v in buffer {
	case Static_Buffer   : return v
	case ^Dynamic_Buffer  : return v.handle
	case ^Mirrored_Buffer : return v.handle
	}
	unreachable()
}

genericbuffer_get_size :: proc(buffer: Generic_Buffer) -> u64 {
	handle := genericbuffer_get_handle(buffer)
	return wgpu.BufferGetSize(handle)
}
