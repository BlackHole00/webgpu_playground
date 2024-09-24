package utils_intrusive

import "base:intrinsics"
import "base:runtime"

Rc :: struct {
	allocation: rawptr,
	allocator: runtime.Allocator,
	reference_count: uint,
}

create :: proc($T: typeid, allocator := context.allocator) -> ^T
	where intrinsics.type_has_field(T, "rc"),
		intrinsics.type_field_type(T, "rc") == typeid_of(Rc) {
	data := new(T, allocator)
	data.rc = Rc {
		allocation = data,
		allocator = allocator,
		reference_count = 1,
	}

	return data
}

force_free :: proc(rc: Rc) {
	free(rc.allocation, rc.allocator)
}

release :: proc(rc: ^Rc) {
	if intrinsics.atomic_sub(&rc.reference_count, 1) == 0 {
		free(rc.allocation, rc.allocator)
	}
}

reference :: proc(rc: ^Rc) {
	intrinsics.atomic_add(&rc.reference_count, 1)
}
