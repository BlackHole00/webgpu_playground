package renderer_utils

import "base:runtime"
import "core:slice"

Rect_Packer_Error :: enum {
	Not_Enough_Space,
}
Rect_Packer_Result :: union #shared_nil {
	runtime.Allocator_Error,
	Rect_Packer_Error,
}

Rect_Packer :: struct {
	allocator: runtime.Allocator,
	area: [2]uint,
	empty_nodes: [dynamic]Rect_Packer_Node,
	filled_nodes: [dynamic]Rect_Packer_Node,
}

rectpacker_create :: proc(
	packer: ^Rect_Packer,
	area: [2]uint,
	allocator := context.allocator,
) -> Rect_Packer_Result {
	packer.area = area
	packer.allocator = allocator

	packer.empty_nodes = make([dynamic]Rect_Packer_Node, 1, packer.allocator) or_return
	packer.filled_nodes = make([dynamic]Rect_Packer_Node, packer.allocator) or_return

	packer.empty_nodes[0] = Rect_Packer_Node {
		position = [2]uint{ 0, 0 },
		size = packer.area,
		type = Rect_Packer_Node_Empty {},
	}

	return nil
}

rectpacker_destroy :: proc(packer: Rect_Packer) {
	delete(packer.empty_nodes)
	delete(packer.filled_nodes)
}

rectpacker_insert_rect :: proc(packer: ^Rect_Packer, size: [2]uint, rect_identifier: u64) -> Rect_Packer_Result {
	best_idx := -1
	best_area := max(uint)
	for i in 1..<len(packer.empty_nodes) {
		rect := packer.empty_nodes[i]

		if rect.size.x < size.x || rect.size.y < size.y {
			continue
		}

		area := rect.size.x * rect.size.y
		if area < best_area {
			best_idx = i
			best_area = area
		}
	}

	if best_idx == -1 {
		return .Not_Enough_Space
	}

	rect := &packer.empty_nodes[best_idx]
	x_corner := rect.size.x - size.x
	y_corner := rect.size.y - size.y

	filled_rect := Rect_Packer_Node {
		position = rect.position,
		size = size,
		type = Rect_Packer_Node_Filled {
			user_rect_identifier = rect_identifier,
		},
	}

	if x_corner < y_corner {
		if x_corner != 0 {
			empty_node := Rect_Packer_Node {
				position = [2]int{
					rect.position.x,
					rect.position.y
				},
			}
			append(&packer.empty_nodes) or_return
		}

		rect.position.x += size.x
		rect.size.x -= size.x

	}

	return nil
}

@(private)
RECT_PACKER_INVALID_NODE_IDX :: max(uint)

@(private)
Rect_Packer_Node_Filled :: struct {
	user_rect_identifier: u64,
}

@(private)
Rect_Packer_Node_Empty :: struct {}

@(private)
Rect_Packer_Node_Type :: union #no_nil {
	Rect_Packer_Node_Filled,
	Rect_Packer_Node_Empty,
}

@(private)
Rect_Packer_Node :: struct {
	position: [2]uint,
	size: [2]uint,
	type: Rect_Packer_Node_Type,
}

