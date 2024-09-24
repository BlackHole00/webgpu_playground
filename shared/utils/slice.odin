package utils

import "base:intrinsics"

typedarray_ensure_all_values_valid :: proc(slice: [$E]$T) -> bool {
	for item in slice {
		if item == nil {
			return false
		}
	}

	return true
}
