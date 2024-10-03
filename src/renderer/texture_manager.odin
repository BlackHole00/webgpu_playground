package renderer

import "base:runtime"
import "core:log"
import "core:os"
import "core:slice"
import wgputils "wgpu"
import "vendor:wgpu"
import "vendor:stb/image"
import rp "vendor:stb/rect_pack"

Texture :: distinct uint
INVALID_TEXTURE :: max(Texture)

Texture_Info :: struct {
	using _private: struct {
		data: []byte, // data waiting to be uploaded
	},

	atlas_location: Maybe([2]uint),
	is_available: bool,
	size: [2]uint,
}

Texture_Manager :: struct {
	allocator: runtime.Allocator,
	backing_texture: ^wgputils.Dynamic_Texture,
	textures: [dynamic]Texture_Info,
	last_uploaded_texture_idx: int,
}

texturemanager_create :: proc(
	manager: ^Texture_Manager,
	backing_texture: ^wgputils.Dynamic_Texture,
	allocator := context.allocator,
) {
	manager.allocator = allocator

	manager.backing_texture = backing_texture
	manager.textures = make([dynamic]Texture_Info, allocator)
}

texturemanager_destroy :: proc(manager: Texture_Manager) {
	for texture in manager.textures {
		if texture.data != nil {
			delete(texture.data, manager.allocator)
		}
	}

	delete(manager.textures)
}

texturemanager_register_texture_from_file :: proc(manager: ^Texture_Manager, file: string) -> (Texture, bool) {
	file_data, data_ok := os.read_entire_file(file, manager.allocator)
	if !data_ok {
		log.errorf("Could not register a new texture: Could not open the file %s", file)
		return INVALID_TEXTURE, false
	}

	width, height, channels: i32
	image_data := image.load_from_memory(raw_data(file_data), (i32)(len(file_data)), &width, &height, &channels, 4)
	defer image.image_free(image_data)

	if channels != 4 {
		log.warnf("The texture %s is not using 4 channels. The texture manager only supports rgba8 textures", file)
	}

	image_data_slice := slice.from_ptr(image_data, (int)(width * height * 4))
	return texturemanager_register_texture_from_bytes(manager, image_data_slice, { (uint)(width), (uint)(height) })
}

texturemanager_register_texture_from_bytes :: proc(
	manager: ^Texture_Manager,
	data: []byte,
	size: [2]uint,
) -> (Texture, bool) {
	if size.x * size.y * 4 != len(data) {
		log.errorf(
			"Could not register a new texture: the length of the provided data does not match the provided texture " +
			"size. %d expected (%v size), %d found. Please keep in mind that the atlas does support textures only in " +
			"the RGBA8 format",
			size.x * size.y * 4,
			size,
			len(data),
		)
		return INVALID_TEXTURE, false
	}

	texture_index := len(manager.textures)
	resize_dynamic_array(&manager.textures, texture_index + 1)

	manager.textures[texture_index].size = size
	manager.textures[texture_index].data = slice.clone(data, manager.allocator)

	return (Texture)(texture_index), true
}

texturemanager_register_texture :: proc {
	texturemanager_register_texture_from_bytes,
	texturemanager_register_texture_from_file,
}

texturemanager_upload_textures :: proc(manager: ^Texture_Manager) -> bool {
	if manager.last_uploaded_texture_idx >= len(manager.textures) - 1 {
		return true
	}

	atlas_size := wgputils.dynamictexture_get_size(manager.backing_texture^)
	should_resize_atlas := false

	packer: rp.Context
	rects := texturemanager_create_rp_rect_list(manager^)

	for {
		nodes := make([]rp.Node, atlas_size.width + 1, context.temp_allocator)

		rp.init_target(
			&packer,
			(i32)(atlas_size.width),
			(i32)(atlas_size.height),
			raw_data(nodes),
			(i32)(len(nodes),
		))
		rp.pack_rects(&packer, raw_data(rects), (i32)(len(rects)))
	
		if !rprectlist_has_unpacked_rects(rects) {
			break
		}

		atlas_size.width *= 2
		atlas_size.height *= 2
		should_resize_atlas = true
	}

	if should_resize_atlas {
		if !wgputils.dynamictexture_resize(manager.backing_texture, atlas_size, true) {
			log.errorf("Could not upload the textures to the atlas.")
			return false
		}
	}

	texturemanager_apply_rp_rect_list(manager^, rects)

	// TODO(Vicix): Find a better way to do this (texture mapping)
	for texture_idx in manager.last_uploaded_texture_idx..<len(manager.textures) {
		texture := &manager.textures[texture_idx]

		wgputils.dynamictexture_write(
			manager.backing_texture^,
			wgpu.Origin3D { (u32)(texture.atlas_location.?.x), (u32)(texture.atlas_location.?.y), 0 },
			.All,
			wgpu.Extent3D { (u32)(texture.size.x), (u32)(texture.size.y), 1 },
			texture.data,
			4,
		)

		delete(texture.data)
		texture.data = nil
	}

	manager.last_uploaded_texture_idx = len(manager.textures) - 1
	return true
}

@(private="file")
texturemanager_create_rp_rect_list :: proc(manager: Texture_Manager, allocator := context.temp_allocator) -> []rp.Rect {
	list := make([]rp.Rect, len(manager.textures), allocator)

	for texture, i in manager.textures {
		list[i].w = (rp.Coord)(texture.size.x)
		list[i].h = (rp.Coord)(texture.size.y)

		if texture.is_available {
			list[i].x = (rp.Coord)(texture.atlas_location.?.x)
			list[i].y = (rp.Coord)(texture.atlas_location.?.y)
			list[i].was_packed = true
		}
	}

	return list
}

@(private="file")
texturemanager_apply_rp_rect_list :: proc(manager: Texture_Manager, list: []rp.Rect) {
	for rect, i in list {
		if rect.was_packed {
			manager.textures[i].atlas_location = [2]uint{ (uint)(rect.x), (uint)(rect.y) }
			manager.textures[i].is_available = true
		} else {
			manager.textures[i].atlas_location = nil
			manager.textures[i].is_available = false
		}
	}
}

@(private="file")
rprectlist_has_unpacked_rects :: proc(list: []rp.Rect) -> bool {
	for rect in list {
		if !rect.was_packed {
			return true
		}
	}

	return false
}
