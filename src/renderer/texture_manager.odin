package renderer

import "base:runtime"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import wgputils "wgpu"
import "vendor:wgpu"
import "vendor:stb/image"
import "shared:utils"

Atlas_Type :: enum {
	R8,
	RG8,
	RGBA8,
}
ATLAS_TYPE_PIXEL_SIZE := [Atlas_Type]uint {
	.R8 = 1,
	.RG8 = 2,
	.RGBA8 = 4,
}

Texture :: distinct uint
INVALID_TEXTURE :: max(Texture)

ATLAS_BORDER_SIZE :: 4

Texture_Info :: struct {
	size: [2]uint,
	atlas_location: Maybe([2]uint),
	atlas_type: Atlas_Type,
	has_been_uploaded: bool,
}

Texture_Manager_Common_Error :: enum {
	Invalid_File,
	File_Read_Error,
	Invalid_Texture_Source,
}

Texture_Manager_Result :: union #shared_nil {
	runtime.Allocator_Error,
	utils.Path_Result,
	Texture_Manager_Common_Error,
	Atlas_Manager_Result,
}

Texture_Manager_Descriptor :: struct {
	queue: wgpu.Queue,
	backing_textures: [Atlas_Type]^wgputils.Dynamic_Texture,
	backing_texture_info_buffer: ^wgputils.Dynamic_Buffer,
	backing_atlases_info_buffer: wgpu.Buffer,
}

Texture_Manager :: struct {
	allocator: runtime.Allocator,

	queue: wgpu.Queue,
	atlas_managers: [Atlas_Type]Atlas_Manager,
	backing_texture_info_buffer: ^wgputils.Dynamic_Buffer,

	texture_libraries: [dynamic]string,
	textures: [dynamic]Texture_Info,
}

texturemanager_create :: proc(
	manager: ^Texture_Manager,
	descriptor: Texture_Manager_Descriptor,
	allocator := context.allocator,
	location := #caller_location,
) -> (result: Texture_Manager_Result) {
	when ODIN_DEBUG {
		assert(descriptor.queue != nil)
		assert(descriptor.backing_texture_info_buffer != nil)
		assert(descriptor.backing_atlases_info_buffer != nil)
		for backing_texture in descriptor.backing_textures {
			assert(backing_texture != nil)
		}

		backing_atlases_info_size := wgpu.BufferGetSize(descriptor.backing_atlases_info_buffer)
		assert(backing_atlases_info_size >= size_of(Atlas_Gpu_Info) * len(Atlas_Type))
	}
	defer if result != nil {
		texturemanager_destroy(manager)
	}

	manager.allocator = allocator

	manager.queue = descriptor.queue
	manager.backing_texture_info_buffer = descriptor.backing_texture_info_buffer

	manager.textures = make([dynamic]Texture_Info, allocator) or_return
	manager.texture_libraries = make([dynamic]string, allocator) or_return

	for backing_texture, atlas_type in descriptor.backing_textures {
		i := (int)(atlas_type)

		atlas_info_buffer: wgputils.Buffer_Slice
		wgputils.bufferslice_create(
			&atlas_info_buffer,
			descriptor.backing_atlases_info_buffer,
			(u64)(i * size_of(Atlas_Gpu_Info)),
			(u64)(size_of(Atlas_Gpu_Info)),
		)

		if atlas_result := atlasmanager_create(
			&manager.atlas_managers[atlas_type],
			Atlas_Manager_Descriptor {
				queue = descriptor.queue,
				backing_info_buffer = atlas_info_buffer,
				backing_texture = backing_texture,
				texture_pixel_size = ATLAS_TYPE_PIXEL_SIZE[atlas_type],
				texture_border_size = ATLAS_BORDER_SIZE,
			},
			allocator,
		); atlas_result != nil {
			log.errorf(
				"Could not create a texture manager: could not create the texture manager for the atlas %v. Got " +
				"error %v",
				atlas_type,
				atlas_result,
				location = location,
			)
			return atlas_result
		}
	}
	
	texturemanager_add_texture_library(manager, ".") or_return

	return nil
}

texturemanager_destroy :: proc(manager: ^Texture_Manager) {
	for &atlas_manager in manager.atlas_managers {
		atlasmanager_destroy(&atlas_manager)
	}

	for library in manager.texture_libraries {
		delete(library, manager.allocator)
	}

	delete(manager.textures)
	delete(manager.texture_libraries)
}

texturemanager_add_texture_library :: proc(
	manager: ^Texture_Manager,
	path: string,
	location := #caller_location,
) -> Texture_Manager_Result {
	fullpath, fullpath_result := utils.path_as_fullpath(path, manager.allocator)
	if fullpath_result != nil {
		log.errorf(
		"Could not add the texture library %s: could not get the full path. Got error %v",
			path,
			fullpath_result,
			location = location,
		)
		return Texture_Manager_Common_Error.Invalid_File
	}

	append(&manager.texture_libraries, fullpath) or_return
	return nil
}

texturemanager_is_texture_valid :: proc(manager: Texture_Manager, texture: Texture) -> bool {
	return (int)(texture) < len(manager.textures)
}

texturemanager_is_texture_uploaded :: proc(manager: Texture_Manager, texture: Texture) -> bool {
	return texturemanager_is_texture_valid(manager, texture) && manager.textures[texture].has_been_uploaded
}

texturemanager_get_texture_info :: proc(manager: Texture_Manager, texture: Texture) -> (Texture_Info, bool) {
	if !texturemanager_is_texture_valid(manager, texture) {
		return {}, false
	}

	return manager.textures[texture], true
}

texturemanager_register_texture_from_file :: proc(
	manager: ^Texture_Manager,
	file: string,
	location := #caller_location,
) -> (Texture, Texture_Manager_Result) {
	file_handle, could_find_file := texturemanager_find_file_in_texture_libraries(manager^, file)
	if !could_find_file {
		log.errorf(
			"Could not register a new texture: Could not find the file %s in any library",
			file,
			location = location,
		)
		return INVALID_TEXTURE, Texture_Manager_Common_Error.Invalid_File
	}
	defer os.close(file_handle)

	file_data, data_ok := os.read_entire_file(file_handle, manager.allocator)
	if !data_ok {
		log.errorf("Could not register a new texture: Read the entire file %s", file, location = location)
		return INVALID_TEXTURE, Texture_Manager_Common_Error.File_Read_Error
	}

	width, height, channels: i32
	image_data := image.load_from_memory(raw_data(file_data), (i32)(len(file_data)), &width, &height, &channels, 0)
	defer image.image_free(image_data)

	image_data_slice := slice.from_ptr(image_data, (int)(width * height * channels))
	if channels == 3 {
		image_data_slice = make([]byte, width * height * 4, context.temp_allocator)

		j := 0
		for i in 0..<width * height * channels {
			image_data_slice[j] = image_data[i]
			j += 1

			if j % 3 == 0 {
				image_data_slice[j] = 255
				j += 1
			}
		}
	}

	target: Atlas_Type
	switch channels {
	case 1: target = .R8
	case 2: target = .RG8
	case 3, 4: target = .RGBA8
	case: unreachable()
	}

	return texturemanager_register_texture_from_bytes(
		manager,
		image_data_slice,
		{ (uint)(width), (uint)(height) },
		target,
		location,
	)
}

texturemanager_register_texture_from_bytes :: proc(
	manager: ^Texture_Manager,
	data: []byte,
	size: [2]uint,
	target: Atlas_Type,
	location := #caller_location,
) -> (texture: Texture, result: Texture_Manager_Result) {
	if size.x * size.y * ATLAS_TYPE_PIXEL_SIZE[target] != len(data) {
		log.errorf(
			"Could not register a new texture: the length of the provided data does not match the provided texture " +
			"size. %d expected (%v size), %d found.",
			size.x * size.y * ATLAS_TYPE_PIXEL_SIZE[target],
			size,
			len(data),
		)
		return INVALID_TEXTURE, Texture_Manager_Common_Error.Invalid_Texture_Source
	}

	texture_index := len(manager.textures)
	resize(&manager.textures, texture_index + 1) or_return

	manager.textures[texture_index].size = size
	manager.textures[texture_index].atlas_type = target

	owned_data := slice.clone(data, context.temp_allocator) or_return
	atlasmanager_queue_add_texture(&manager.atlas_managers[target], Write_Data {
		texture_data = owned_data,
		texture_id = (Texture)(texture_index),
		size = size,
	}) or_return

	return (Texture)(texture_index), nil
}

texturemanager_register_texture :: proc {
	texturemanager_register_texture_from_bytes,
	texturemanager_register_texture_from_file,
}

texturemanager_upload_textures :: proc(manager: ^Texture_Manager) -> Texture_Manager_Result {
	for &atlas_manager, atlas_type in manager.atlas_managers {
		atlas_type_index := (u32)(atlas_type)
		applied_textures := atlasmanager_apply(&atlas_manager, context.temp_allocator) or_return

		for applied_texture in applied_textures {
			manager.textures[applied_texture.texture_id].atlas_location = applied_texture.position
			manager.textures[applied_texture.texture_id].has_been_uploaded = true

			wgputils.dynamicbuffer_queue_write(
				manager.backing_texture_info_buffer,
				(u64)(applied_texture.texture_id) * size_of(Texture_Gpu_Info),
				&Texture_Gpu_Info {
					atlas_location = { (u32)(applied_texture.position.x), (u32)(applied_texture.position.y) },
					atlas_type = atlas_type_index,
					size = { (u32)(applied_texture.size.x), (u32)(applied_texture.size.y) },
				},
				size_of(Texture_Gpu_Info),
				true,
			)
		}
	}

	return nil
}

@(private="file")
Texture_Gpu_Info :: struct {
	atlas_location: [2]u32,
	size: [2]u32,
	atlas_type: u32,
}

@(private="file")
texturemanager_find_file_in_texture_libraries :: proc(manager: Texture_Manager, file: string) -> (os.Handle, bool) {
	for library in manager.texture_libraries {
		trim_library := strings.trim_right(library, "/\\")
		trim_file := strings.trim_left(file, "/\\")

		file_fullpath := strings.concatenate([]string{
			trim_library,
			"/",
			trim_file,
		}, context.temp_allocator)

		if !os.exists(file_fullpath) || !os.is_file(file_fullpath) {
			continue
		}

		handle, handle_err := os.open(file_fullpath, os.O_RDONLY)
		if handle_err != nil {
			continue
		}

		return handle, true
	}

	return os.INVALID_HANDLE, false
}

