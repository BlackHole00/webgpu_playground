package utils

import "base:runtime"
import "core:strings"
import "core:os"

Path_Result :: union #shared_nil {
	runtime.Allocator_Error,
	os.Error,
}

path_as_fullpath :: proc(path: string, allocator := context.allocator) -> (fullpath: string, result: Path_Result) {
	file_info, file_info_res := os.stat(path, context.temp_allocator)
	if file_info_res != nil {
		return "", file_info_res
	}

	fullpath = strings.clone(file_info.fullpath, allocator) or_return
	return fullpath, nil
}
