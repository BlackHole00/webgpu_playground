package stb_include

import "core:c/libc"
import "core:strings"
import "core:log"

foreign import stb_include "lib/Darwin_stb_include.a"

@(default_calling_convention="c", link_prefix="stb_")
foreign stb_include {
	@(link_name="stb_include_string")
	include_string_raw :: proc(
		str: cstring,
		inject: cstring,
		path_to_includes: cstring,
		path_for_line_directive: cstring,
		error: ^[256]byte,
	) -> cstring ---
	@(link_name="stb_include_strings")
	include_strings_raw :: proc(
		strs: [^]cstring,
		count: i32,
		inject: cstring,
		path_to_includes: cstring,
		path_for_line_directive: cstring,
		error: ^[256]byte,
	) -> cstring ---
	@(link_name="stb_include_file")
	include_file_raw :: proc(
		filename: cstring,
		inject: cstring,
		path_to_includes: cstring,
		error: ^[256]byte,
	) -> cstring ---
}

include_string :: proc(
	str: string,
	path_to_includes: string,
	inject := "",
	allocator := context.allocator,
) -> (string, bool) {
	error: [256]byte

	raw_result := include_string_raw(
		strings.clone_to_cstring(str, context.temp_allocator),
		strings.clone_to_cstring(inject, context.temp_allocator),
		strings.clone_to_cstring(path_to_includes, context.temp_allocator),
		"",
		&error,
	)
	if raw_result == nil {
		log.errorf("Could not include string: %s", (string)(error[:]))
		return "", false
	}
	defer libc.free((rawptr)(raw_result))

	return strings.clone_from_cstring(raw_result, allocator), true
}

append_and_include_strings :: proc(
	strs: []string,
	path_to_includes: string,
	inject := "",
	allocator := context.allocator,
) -> (string, bool) {
	error: [256]byte
	
	strs_cstring := make([]cstring, len(strs), context.temp_allocator)
	for str, i in strs {
		strs_cstring[i] = strings.clone_to_cstring(str, context.temp_allocator)
	}

	raw_result := include_strings_raw(
		raw_data(strs_cstring),
		(i32)(len(strs)),
		strings.clone_to_cstring(inject, context.temp_allocator),
		strings.clone_to_cstring(path_to_includes, context.temp_allocator),
		"",
		&error,
	)
	if raw_result == nil {
		log.errorf("Could not include string: %s", (string)(error[:]))
		return "", false
	}
	defer libc.free((rawptr)(raw_result))

	return strings.clone_from_cstring(raw_result, allocator), true
}

include_file :: proc(
	file: string,
	path_to_includes: string,
	inject := "",
	allocator := context.allocator,
) -> (string, bool) {
	error: [256]byte
	
	raw_result := include_file_raw(
		strings.clone_to_cstring(file, context.temp_allocator),
		strings.clone_to_cstring(inject, context.temp_allocator),
		strings.clone_to_cstring(path_to_includes, context.temp_allocator),
		&error,
	)
	if raw_result == nil {
		log.errorf("Could not include string: %s", (string)(error[:]))
		return "", false
	}
	defer libc.free((rawptr)(raw_result))

	return strings.clone_from_cstring(raw_result, allocator), true
}
