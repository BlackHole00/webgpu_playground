package renderer

import "core:log"
import "core:strings"
import "core:slice"
import "core:mem"
import obj "shared:tinyobjloader"
import wgputils "wgpu"

Model :: distinct uint
INVALID_MODEL :: max(Model)

MODEL_MAX_TEXTURES :: 8

Model_Info :: struct #packed {
	memory_layout: Memory_Layout,
	first_uberindex_offset: u32,
	uberindex_count: u32,
	textures: [MODEL_MAX_TEXTURES]Texture,
}

Model_Manager_Descriptor :: struct {
	layout_manager: ^Memory_Layout_Manager,
	texture_manager: ^Texture_Manager,
	info_backing_buffer: ^wgputils.Mirrored_Buffer,
	vertices_backing_buffer: ^wgputils.Dynamic_Buffer,
	indices_backing_buffer: ^wgputils.Dynamic_Buffer,
}

Model_Manager :: struct {
	layout_manager: ^Memory_Layout_Manager,
	texture_manager: ^Texture_Manager,
	info_backing: ^wgputils.Mirrored_Buffer,
	vertices_backing: ^wgputils.Dynamic_Buffer,
	indices_backing: ^wgputils.Dynamic_Buffer,
	obj_model_layout: Memory_Layout,
}

modelmanager_create :: proc(
	manager: ^Model_Manager,
	descriptor: Model_Manager_Descriptor,
	allocator := context.allocator,
) {
	manager.info_backing     = descriptor.info_backing_buffer
	manager.vertices_backing = descriptor.vertices_backing_buffer
	manager.indices_backing  = descriptor.indices_backing_buffer
	manager.layout_manager   = descriptor.layout_manager
	manager.texture_manager  = descriptor.texture_manager

	manager.obj_model_layout, _ = memorylayoutmanager_register_layout(manager.layout_manager, Memory_Layout_Descriptor {
		indices_count = 3,
		source_sizes  = []u32 {
			0 = 3, // position: [3]f32
			1 = 2, // uv: [2]f32
			2 = 3, // normal: [3]f32
		},
	})
	_ = texturemanager_add_texture_library(manager.texture_manager, "res/textures")
	_ = texturemanager_add_texture_library(manager.texture_manager, "res/models")
}

modelmanager_destroy :: proc(manager: Model_Manager) {}

modelmanager_register_model_from_data :: proc(
	manager: Model_Manager,
	layout: Memory_Layout,
	uber_indices: []u32,
	vertex_datas: []Vertex_Word,
	textures: []Texture,
	adjust_indices := true,
) -> (Model, bool) {
	layout_info, layout_info_ok := memorylayoutmanager_get_info(manager.layout_manager^, layout)
	if !layout_info_ok {
		log.errorf("Could not register a model: the provided layout is not valid")
		return INVALID_MODEL, false
	}

	if len(textures) > MODEL_MAX_TEXTURES {
		log.errorf(
			"Could not register a model: the provided textures are too much (%d supported, %d found)",
			MODEL_MAX_TEXTURES,
			len(textures),
		)
		return INVALID_MODEL, false
	}
	for texture in textures {
		if !texturemanager_is_texture_valid(manager.texture_manager^, texture) {
			log.errorf(
				"Could not register a model: The provided texture %d is not valid",
				texture,
			)
			return INVALID_MODEL, false
		}
	}

	if len(uber_indices) % (int)(layout_info.indices_count) != 0 {
		log.errorf(
			"Could not register a model: The provided uber-indices do not align with the provided layout. Expected " +
			"%d indices per uber-index",
			layout_info.indices_count,
		)
		return INVALID_MODEL, false
	}

	if adjust_indices {
		base_index := wgputils.dynamicbuffer_len(manager.vertices_backing^)
		for &index in uber_indices {
			index += (u32)(base_index)
		}
	}

	index_offset := wgputils.dynamicbuffer_len(manager.indices_backing^) / size_of(u32)
	model_idx := wgputils.mirroredbuffer_len(manager.info_backing^)

	model_info := Model_Info {
		memory_layout = layout,
		first_uberindex_offset = (u32)(index_offset),
		uberindex_count = (u32)(len(uber_indices)) / layout_info.indices_count,
	}
	copy(model_info.textures[:], textures)

	wgputils.mirroredbuffer_append(manager.info_backing, &model_info)
	wgputils.dynamicbuffer_append(manager.vertices_backing, vertex_datas)
	wgputils.dynamicbuffer_append(manager.indices_backing, uber_indices)

	return (Model)(model_idx), true
}

modelmanager_register_model_from_sources :: proc(
	manager: Model_Manager,
	layout: Memory_Layout,
	// a slice containing the indices of each source (stored via pararrel slices)
	index_sources: [][]u32,
	// a slice containing the different vertex sources. The each index is relative to this vector
	vertex_sources: [][]Vertex_Word,
	textures: []Texture,
) -> (Model, bool) {
	layout_info, layout_info_ok := memorylayoutmanager_get_info(manager.layout_manager^, layout)
	if !layout_info_ok {
		log.errorf("Could not register a model: the provided layout is not valid")
		return INVALID_MODEL, false
	}
	
	if (u32)(len(index_sources)) != layout_info.indices_count {
		log.errorf(
			"Could not register a model: the provided index sources do not match the expected ones from the provided " +
			"layer. Expected %d sources, found %d",
			layout_info.indices_count,
			len(index_sources),
		)
	}

	if (u32)(len(vertex_sources)) != layout_info.indices_count {
		log.errorf(
			"Could not register a model: the provided vertex sources do not match the expected ones from the provided " +
			"layer. Expected %d sources, found %d",
			layout_info.indices_count,
			len(vertex_sources),
		)
	}

	index_count := len(index_sources[0])
	for i in 1..<len(index_sources) {
		if len(index_sources[i]) != index_count {
			log.errorf("Could not register a model: The provided index sources do not have the same number of indeces")
			return INVALID_MODEL, false
		}
	}

	vertex_data_size := 0
	for vertex_source in vertex_sources {
		vertex_data_size += len(vertex_source)
	}

	index_buffer := make([]u32, len(index_sources[0]) * (int)(layout_info.indices_count), context.temp_allocator)
	vertex_buffer := make([]Vertex_Word, vertex_data_size, context.temp_allocator)
	index_offset := 0

	for index_idx in 0..<len(index_sources[0]) {
		vertex_offset := 0
		for index_source_idx, i in 0..<len(index_sources) {
			index_buffer[index_offset] = index_sources[index_source_idx][index_idx]
			index_buffer[index_offset] += (u32)(vertex_offset)

			index_offset += 1
			vertex_offset += len(vertex_sources[i])
		}
	}

	vertex_offset := 0
	for vertex_source in vertex_sources {
		mem.copy_non_overlapping(
			&vertex_buffer[vertex_offset],
			raw_data(vertex_source),
			len(vertex_source) * size_of(Vertex_Word),
		)
		vertex_offset += len(vertex_source)
	}

	return modelmanager_register_model_from_data(manager, layout, index_buffer, vertex_buffer, textures)
}

modelmanager_register_model_from_obj :: proc(
	manager: Model_Manager,
	obj_path: string,
	mtl_path: Maybe(string) = nil,
) -> (Model, bool) {
	attrib, shapes, materials, model_err := obj.parse_obj(obj_path, { .Triangulate })
	if model_err != .Success {
		log.errorf(
			"Could not register the model %s: Could not parse the corrisponding obj file. Got error: %v",
			obj_path,
			model_err,
		)
		return INVALID_MODEL, false
	}
	defer obj.free(attrib, shapes, materials)

	if mtl_path, mtl_ok := mtl_path.?; mtl_ok {
		mtl_materials, mtl_err := obj.parse_mtl(mtl_path, obj_path)
		if mtl_err != .Success {
			log.errorf(
				"Could not register the model %s: Could not parse the corrisponding mtl file. Got error: %v",
				obj_path,
				model_err,
			)
			return INVALID_MODEL, false
		}

		obj.materials_free(materials)
		materials = mtl_materials
	}

	textures: [8]Texture
	texture_count := 0

	log.info(materials)
	for material in materials {
		if material.name == "none" {
			continue
		}

		if material.diffuse_texname != "" {
			texture, texture_ok := texturemanager_register_texture(
				manager.texture_manager,
				strings.clone_from_cstring(material.diffuse_texname, context.temp_allocator),
			)
			if !texture_ok {
				log.errorf(
					"Could not register the model %s: Could not load the texture %s",
					obj_path,
					material.diffuse_texname,
				)
				return INVALID_MODEL, false
			}

			textures[texture_count] = texture
			texture_count += 1
		}
	}

	vertex_sources: [3][]Vertex_Word
	vertex_sources[0] = slice.reinterpret([]Vertex_Word, attrib.vertices)
	vertex_sources[1] = slice.reinterpret([]Vertex_Word, attrib.texcoords)
	vertex_sources[2] = slice.reinterpret([]Vertex_Word, attrib.normals)

	index_sources: [3][]u32
	index_sources[0] = make([]u32, len(attrib.faces), context.temp_allocator)
	index_sources[1] = make([]u32, len(attrib.faces), context.temp_allocator)
	index_sources[2] = make([]u32, len(attrib.faces), context.temp_allocator)

	for face, i in attrib.faces {
		index_sources[0][i] = (u32)(face.v_idx) * 3
		index_sources[1][i] = (u32)(face.vt_idx) * 2
		index_sources[2][i] = (u32)(face.vn_idx) * 3
	}

	return modelmanager_register_model_from_sources(
		manager,
		manager.obj_model_layout,
		index_sources[:],
		vertex_sources[:],
		textures[:texture_count],
	)
}

modelmanager_register_model :: proc {
	modelmanager_register_model_from_data,
	modelmanager_register_model_from_sources,
	modelmanager_register_model_from_obj,
}

