package utils

import "core:strings"
import "core:os"

path_as_fullpath :: proc(path: string, allocator := context.allocator) -> (string, bool) {
	file_info, file_info_ok := os.stat(path, context.temp_allocator)
	if file_info_ok != nil {
		return "", false
	}

	return strings.clone(file_info.fullpath, allocator), true
}
