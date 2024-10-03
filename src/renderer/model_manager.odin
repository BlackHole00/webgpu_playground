package renderer

import "core:log"
import "core:slice"
import obj "shared:tinyobjloader"
import wgputils "wgpu"

Model_Info :: struct {
	vertex_offset: uint,
	vertex_length: uint,
	index_offset: uint,
	index_length: uint,
}

Model :: distinct int
INVALID_MODEL :: max(Model)

Model_Manager :: struct {
	models: [dynamic]Model_Info,
	vertices_backing: ^wgputils.Dynamic_Buffer,
	indices_backing: ^wgputils.Dynamic_Buffer,
	max_index_used: u32,
}

modelmanager_create :: proc(
	manager: ^Model_Manager,
	backing_vertices_buffer: ^wgputils.Dynamic_Buffer,
	backing_indices_buffer: ^wgputils.Dynamic_Buffer,
	allocator := context.allocator,
) {
	manager.vertices_backing = backing_vertices_buffer
	manager.indices_backing = backing_indices_buffer

	manager.models = make([dynamic]Model_Info, allocator)
}

modelmanager_destroy :: proc(manager: Model_Manager) {
	delete(manager.models)
}

modelmanager_get_info :: proc(manager: Model_Manager, model: Model) -> ^Model_Info {
	return &manager.models[model]
}

modelmanager_register_model_from_obj :: proc(manager: ^Model_Manager, obj_file: string) -> (Model, bool) {
	attrib, shapes, normals, error := obj.parse_obj(obj_file, { .Triangulate })
	if error != .Success {
		log.errorf("Could not parse the model %s. Got error: %v", obj_file, error)
		return INVALID_MODEL, false
	}
	defer obj.free(attrib, shapes, normals)

	used_index_count: u32
	indices := make([dynamic]u32)
	defer delete(indices)
	vertices := make([dynamic]Basic_Vertex)
	defer delete(vertices)
	vertex_cache := make(map[Basic_Vertex]u32)
	defer delete(vertex_cache)

	for vertices_num in attrib.face_num_verts {
		if vertices_num != 3 {
			log.errorf(
				"Could not load model %s: The model uses non triangular faces. The engine does not support such model types",
				obj_file,
			)
			return INVALID_MODEL, false
		}
	}

	face_idx := 0
	for face_idx < len(attrib.faces) {
		triangle_indices := [?]obj.Vertex_Index{
			attrib.faces[face_idx],
			attrib.faces[face_idx + 1],
			attrib.faces[face_idx + 2],
		}

		triangle_vertices: [3]Basic_Vertex
		for index, i in triangle_indices {
			triangle_vertices[i] = Basic_Vertex {
				position = attrib.vertices[index.v_idx],
				normal = attrib.normals[index.vn_idx],
				// TODO(Vicix): Integrate uv with atlas
				uv = swizzle(attrib.texcoords[index.vt_idx], 0, 1),
			}
		}

		for vertex in triangle_vertices {
			if cached_index, cached := vertex_cache[vertex]; cached {
				append(&indices, cached_index)
				continue
			}

			append(&vertices, vertex)
			append(&indices, used_index_count)
			vertex_cache[vertex] = used_index_count
		
			used_index_count += 1
		}

		face_idx += 3
	}

	model, ok := modelmanager_register_model_raw(manager, vertices[:], indices[:], true)
	if !ok {
		log.errorf("Could not load model %s into gpu memory", obj_file)
	}

	return model, ok
}

modelmanager_register_model_raw :: proc(
	manager: ^Model_Manager,
	vertices: []Basic_Vertex,
	indices: []u32,
	can_override_input := false,
) -> (Model, bool) {
	vertex_offset := manager.vertices_backing.length
	index_offset := manager.indices_backing.length

	if !wgputils.dynamicbuffer_append(manager.vertices_backing, vertices) {
		log.errorf("Could not insert the new model vertices")
		return INVALID_MODEL, false
	}
	if !wgputils.dynamicbuffer_append(manager.indices_backing, indices) {
		log.errorf("Could not insert the new model indices")
		return INVALID_MODEL, false
	}

	indices := indices
	if !can_override_input {
		indices = slice.clone(indices, context.temp_allocator)
	}

	for &i in indices {
		i += manager.max_index_used
	}
	manager.max_index_used += (u32)(len(vertices))

	model := (Model)(len(manager.models))
	append(&manager.models, Model_Info {
		vertex_offset = vertex_offset,
		vertex_length = len(vertices),
		index_offset = index_offset,
		index_length = len(indices),
	})

	return model, true
}

modelmanager_register_model :: proc {
	modelmanager_register_model_raw,
	modelmanager_register_model_from_obj,
}
