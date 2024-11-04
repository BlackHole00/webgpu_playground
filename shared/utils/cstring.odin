package utils

import "base:runtime"
import "core:slice"

cstring_clone :: proc(str: cstring, allocator := context.allocator) -> (res: cstring, err: runtime.Allocator_Error) #optional_allocator_error {
	str_len := len(str)
	str_data := (rawptr)(str)

	str_slice := slice.bytes_from_ptr(str_data, str_len)
	clone_slice := slice.clone(str_slice, allocator) or_return

	return (cstring)(raw_data(clone_slice)), .None
}
