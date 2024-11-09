package tinyobjloader

import "base:runtime"
import "core:c"
import "core:os"
import "core:strings"
import "core:mem"

TINYOBJ_LIBRARY_FILE_EXTENSION :: ".lib" when ODIN_OS == .Windows else ".a"
TINYOBJ_LIBRARY_FILE :: "lib/" + ODIN_OS_STRING + "_" + ODIN_ARCH_STRING + "_tinyobjloader" + TINYOBJ_LIBRARY_FILE_EXTENSION

when !#exists(TINYOBJ_LIBRARY_FILE) {
	#panic("Could not find the compiled Tiny Obj Loader Native library at '" + #directory + TINYOBJ_LIBRARY_FILE)
}

foreign import tinyobjloader {
	TINYOBJ_LIBRARY_FILE,
}

@(default_calling_convention="c", link_prefix="tinyobj_")
foreign tinyobjloader {
	set_memory_callbacks :: proc(malloc, realloc, calloc, free: rawptr) ---
}

Error :: enum c.int {
	Success = 0,
	Empty = -1,
	Invalid_Parameter = -2,
	Invalid_File_Operation = -3,
}

Flag :: enum {
	Triangulate,
}
Flags :: bit_set[Flag; c.uint]

Vertex_Index :: struct {
	v_idx: c.int,
	vt_idx: c.int,
	vn_idx: c.int,
}

Attrib :: struct {
	vertices: [][3]f32,
	normals: [][3]f32,
	texcoords: [][2]f32,
	faces: []Vertex_Index,
	face_num_verts: []c.int,
	material_ids: [^]c.int,
}

Shape :: struct {
	name: cstring,
	face_offset: c.uint,
	length: c.uint,
}

Material :: struct {
	name: cstring,

	ambient: [3]f32,
	diffuse: [3]f32,
	specular: [3]f32,
	transmittance: [3]f32,
	emission: [3]f32,
	shininess: f32,
	ior: f32,
	dissolve: f32,
	illum: c.int,

	pad0: c.int,

	ambient_texname: cstring,
	diffuse_texname: cstring,
	specular_texname: cstring,
	specular_highlight_texname: cstring,
	bump_texname: cstring,
	displacement_texname: cstring,
	alpha_texname: cstring,
}

File_Reader_Callback :: #type proc "c" (
	ctx: rawptr,
	filename: cstring,
	is_mtl: b32,
	obj_filename: cstring,
	buf: ^cstring,
	len: ^c.size_t,
)

parse_obj :: proc(
	file_name: string,
	flags := Flags{},
	temp_allocator := context.temp_allocator
) -> (attrib: Attrib, shapes: []Shape, materials: []Material, error: Error) {
	temp_allocator := temp_allocator

	raw_attrib: Raw_Attrib
	raw_shapes: [^]Shape
	num_shapes: c.size_t
	raw_materials: [^]Material
	num_materials: c.size_t
 
	error = parse_obj_raw(
		&raw_attrib,
		&raw_shapes,
		&num_shapes,
		&raw_materials,
		&num_materials,
		strings.clone_to_cstring(file_name, temp_allocator),
		file_reader,
		&temp_allocator,
		flags,
	)
	if error != .Success {
		return
	}

	attrib_from_raw(&attrib, raw_attrib)
	shapes = mem.slice_ptr(raw_shapes, (int)(num_shapes))
	materials = mem.slice_ptr(raw_materials, (int)(num_materials))
	return
}

parse_mtl :: proc(
	file_name: string,
	obj_file_name: Maybe(string) = nil,
	temp_allocator := context.temp_allocator,
) -> (materials: []Material, error: Error) {
	temp_allocator := temp_allocator

	raw_materials: [^]Material
	num_materials: c.size_t

	obj_file_name_cstr: cstring = nil
	if str, ok := obj_file_name.?; ok {
		obj_file_name_cstr = strings.clone_to_cstring(str, temp_allocator)
	}
	error = parse_mtl_file_raw(
		&raw_materials,
		&num_materials,
		strings.clone_to_cstring(file_name, temp_allocator),
		obj_file_name_cstr,
		file_reader,
		&temp_allocator,
	)
	if error != .Success {
		return
	}

	materials = mem.slice_ptr(raw_materials, (int)(num_materials))
	return
}

attrib_free :: proc(attrib: Attrib) {
	raw_attrib: Raw_Attrib
	attrib_to_raw(attrib, &raw_attrib)
	attrib_free_raw(&raw_attrib)
}

shapes_free :: proc(shapes: []Shape) {
	shapes_free_raw(raw_data(shapes), len(shapes))
}

materials_free :: proc(materials: []Material) {
	materials_free_raw(raw_data(materials), len(materials))
}

free :: proc(attrib: Attrib, shapes: []Shape, materials: []Material) {
	attrib_free(attrib)
	shapes_free(shapes)
	materials_free(materials)
}

@(private)
Raw_Attrib :: struct {
	num_vertices: c.uint,
	num_normals: c.uint,
	num_texcoords: c.uint,
	num_faces: c.uint,
	num_face_num_verts: c.uint,

	pad0: c.int,

	vertices: [^]f32,
	normals: [^]f32,
	texcoords: [^]f32,
	faces: [^]Vertex_Index,
	face_num_verts: [^]c.int,
	material_ids: [^]c.int,
}

@(private)
attrib_from_raw :: proc(attrib: ^Attrib, raw: Raw_Attrib) {
	attrib.vertices = mem.slice_ptr(([^][3]f32)(raw.vertices), (int)(raw.num_vertices))
	attrib.normals = mem.slice_ptr(([^][3]f32)(raw.normals), (int)(raw.num_normals))
	attrib.texcoords = mem.slice_ptr(([^][2]f32)(raw.texcoords), (int)(raw.num_texcoords))
	attrib.faces = mem.slice_ptr(raw.faces, (int)(raw.num_faces))
	attrib.face_num_verts = mem.slice_ptr(raw.face_num_verts, (int)(raw.num_face_num_verts))
	attrib.material_ids = raw.material_ids
}

@(private)
attrib_to_raw :: proc(attrib: Attrib, raw: ^Raw_Attrib) {
	raw.num_vertices = (c.uint)(len(attrib.vertices))
	raw.num_normals = (c.uint)(len(attrib.normals))
	raw.num_texcoords = (c.uint)(len(attrib.texcoords))
	raw.num_faces = (c.uint)(len(attrib.faces))
	raw.num_face_num_verts = (c.uint)(len(attrib.face_num_verts))
	raw.vertices = ([^]f32)(raw_data(attrib.vertices))
	raw.normals = ([^]f32)(raw_data(attrib.normals))
	raw.texcoords = ([^]f32)(raw_data(attrib.texcoords))
	raw.faces = raw_data(attrib.faces)
	raw.face_num_verts = raw_data(attrib.face_num_verts)
	raw.material_ids = attrib.material_ids
}

@(private)
file_reader :: proc "c" (
	ctx: rawptr,
	filename: cstring,
	is_mtl: b32,
	obj_filename: cstring,
	buf: ^cstring,
	length: ^c.size_t,
) {
	context = runtime.default_context()
	context.temp_allocator = (^runtime.Allocator)(ctx)^

	if filename == nil {
		return
	}

	contents, ok := os.read_entire_file(
		strings.clone_from_cstring(filename, context.temp_allocator),
		context.temp_allocator,
	)
	if !ok {
		return
	}

	buf^ = (cstring)(raw_data(contents))
	length^ = len(contents)
}

@(default_calling_convention="c", link_prefix="tinyobj_")
foreign tinyobjloader {
	@(link_name="tinyobj_parse_obj", private)
	parse_obj_raw :: proc(
		attrib: ^Raw_Attrib,
		shapes: ^[^]Shape,
		num_shapes: ^c.size_t,
		materials: ^[^]Material,
		num_materials: ^c.size_t,
		file_name: cstring,
		file_reader: File_Reader_Callback,
		ctx: rawptr,
		flags: Flags,
	) -> Error ---
	@(link_name="tinyobj_parse_mtl_file", private)
	parse_mtl_file_raw :: proc(
		materials: ^[^]Material,
		num_materials: ^c.size_t,
		filename: cstring,
		obj_filename: cstring,
		file_reader: File_Reader_Callback,
		ctx: rawptr,
	) -> Error ---
	@(link_name="tinyobj_attrib_free", private)
	attrib_free_raw :: proc(attrib: ^Raw_Attrib) ---
	@(link_name="tinyobj_shapes_free", private)
	shapes_free_raw :: proc(shapes: [^]Shape, num_shapes: c.size_t) ---
	@(link_name="tinyobj_materials_free", private)
	materials_free_raw :: proc(materials: [^]Material, num_materials: c.size_t) ---
}

