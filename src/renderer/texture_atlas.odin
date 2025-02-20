package renderer

import "base:runtime"
import "core:fmt"
import "core:slice"
import vmem "core:mem/virtual"
import rp "vendor:stb/rect_pack"
import wgpu "shared:wgpu/wrapper"

Texture_Atlas_Descriptor :: struct {
	internal_format: wgpu.Texture_Format,
	default_pixel_value: []byte,
	atlas_size: [2]u32,
	pixel_stride: u8,
	pixel_size: u8,
	border_size: u8,
}

Texture_Atlas_Texture_Id :: distinct u32
INVALID_TEXTURE_ATLAS_TEXTURE_ID :: max(Texture_Atlas_Texture_Id)

Texture_Atlas_Texture_Status :: enum {
	Unknown,
	Uploaded,
	Upload_Pending,
	Upload_Failed,
}

Texture_Atlas_Texture_Info :: struct {
	status: Texture_Atlas_Texture_Status,
	position: [2]u32,
	size: [2]u32,
	data_to_upload: []byte,
}

Texture_Atlas :: struct {
	core: ^Renderer_Core,
	using descriptor: Texture_Atlas_Descriptor,

	backing_texture: wgpu.Texture,
	texture_info: [dynamic]Texture_Atlas_Texture_Info,
	last_uploaded_texture_index: uint,
}

textureatlas_create :: proc(
	atlas: ^Texture_Atlas,
	descriptor: Texture_Atlas_Descriptor,
	core: ^Renderer_Core,
) -> (res: Renderer_Result) {
	assert(core != nil)
	defer if res != nil {
		textureatlas_destroy(atlas^)
	}

	texture, texture_ok := wgpu.device_create_texture(
		core.device,
		wgpu.Texture_Descriptor {
			label = fmt.ctprintf(
				"%v Texture Atlas",
				descriptor.internal_format,
			),
			usage = { .Copy_Dst, .Texture_Binding },
			dimension = .D2,
			size = wgpu.Extent_3D {
				width = descriptor.atlas_size.x,
				height = descriptor.atlas_size.y,
				depth_or_array_layers = 1,
			},
			format = descriptor.internal_format,
			sample_count = 1,
			view_formats = []wgpu.Texture_Format{
				descriptor.internal_format,
			},
			mip_level_count = 1,
		},
	)
	if !texture_ok {
		return .Could_Not_Create_Texture
	}
	atlas.backing_texture = texture

	atlas.core = core
	atlas.descriptor = descriptor
	atlas.descriptor.default_pixel_value = slice.clone(
		descriptor.default_pixel_value,
		core.global_allocator,
	) or_return

	atlas.texture_info = make([dynamic]Texture_Atlas_Texture_Info, core.allocator) or_return

	return nil
}

textureatlas_destroy :: proc(atlas: Texture_Atlas) {
	delete(atlas.texture_info)
}

textureatlas_add_texture :: proc(
	atlas: ^Texture_Atlas,
	data: []byte,
	size: [2]u32,
) -> (texture: Texture_Atlas_Texture_Id, res: Renderer_Result) {
	texture = INVALID_TEXTURE_ATLAS_TEXTURE_ID

	owned_data := slice.clone(data, atlas.core.frame_allocator) or_return
	append(
		&atlas.texture_info,
		Texture_Atlas_Texture_Info {
			status = .Upload_Pending,
			size = size,
			data_to_upload = owned_data,
		},
	) or_return

	texture = cast(Texture_Atlas_Texture_Id)(len(atlas.texture_info) - 1)
	return
}

textureatlas_is_texture_valid :: proc(atlas: Texture_Atlas, texture_id: Texture_Atlas_Texture_Id) -> bool {
	return texture_id < cast(Texture_Atlas_Texture_Id)len(atlas.texture_info)
}

textureatlas_is_texture_uploaded :: proc(atlas: Texture_Atlas, texture_id: Texture_Atlas_Texture_Id) -> bool {
	if !textureatlas_is_texture_valid(atlas, texture_id) {
		return false
	}

	return atlas.texture_info[texture_id].status != .Uploaded
}

textureatlas_get_texture_status :: proc(
	atlas: Texture_Atlas,
	texture_id: Texture_Atlas_Texture_Id,
) -> (status: Texture_Atlas_Texture_Status, ok: bool) {
	if !textureatlas_is_texture_valid(atlas, texture_id) {
		return .Unknown, false
	}

	return atlas.texture_info[texture_id].status, true
}

textureatlas_get_texture_absolute_position :: proc(
	atlas: Texture_Atlas,
	texture_id: Texture_Atlas_Texture_Id,
) -> (
	position: [2]u32,
	size: [2]u32,
	ok: bool,
) {
	if !textureatlas_is_texture_uploaded(atlas, texture_id) {
		return {}, {}, false
	}

	position = atlas.texture_info[texture_id].position
	size = atlas.texture_info[texture_id].size
	ok = true
	return
}

textureatlas_get_texture_relative_position :: proc(
	atlas: Texture_Atlas,
	texture_id: Texture_Atlas_Texture_Id,
) -> (
	position: [2]f32,
	size: [2]f32,
	ok: bool,
) {
	absolute_position, absolute_size, absolute_ok := textureatlas_get_texture_absolute_position(atlas, texture_id)
	if !absolute_ok {
		return {}, {}, false
	}

	position = [2]f32{
		cast(f32)absolute_position.x / cast(f32)atlas.atlas_size.x,
		cast(f32)absolute_position.y / cast(f32)atlas.atlas_size.y,
	}
	size = [2]f32{
		cast(f32)absolute_size.x / cast(f32)atlas.atlas_size.x,
		cast(f32)absolute_size.y / cast(f32)atlas.atlas_size.y,
	}
	ok = true
	return
}

textureatlas_upload_pending :: proc(atlas: ^Texture_Atlas) -> Renderer_Result {
	if len(atlas.texture_info) == cast(int)atlas.last_uploaded_texture_index {
		return nil
	}

	arena_temp := vmem.arena_temp_begin(&atlas.core.frame_arena)
	defer vmem.arena_temp_end(arena_temp)

	nodes := make([]rp.Node, atlas.atlas_size.x + 1, atlas.core.frame_allocator) or_return

	rectpacker: rp.Context = ---
	rp.init_target(
		&rectpacker,
		cast(i32)atlas.atlas_size.x,
		cast(i32)atlas.atlas_size.y,
		raw_data(nodes),
		cast(i32)len(nodes),
	)

	// TODO: Preserve the rect list
	rects := make([]rp.Rect, len(atlas.texture_info), atlas.core.frame_allocator) or_return
	used_rects := 0

	for info, id in atlas.texture_info {
		if info.status != .Uploaded && info.status != .Upload_Pending {
			continue
		}

		rects[used_rects].id = cast(i32)id
		rects[used_rects].w = cast(rp.Coord)(info.size.x + cast(u32)atlas.border_size * 2)
		rects[used_rects].h = cast(rp.Coord)(info.size.y + cast(u32)atlas.border_size * 2)

		if info.status == .Uploaded {
			rects[used_rects].was_packed = true
			rects[used_rects].x = cast(rp.Coord)info.position.x
			rects[used_rects].y = cast(rp.Coord)info.position.y
		}

		used_rects += 1
	}

	did_pack_all := cast(bool)rp.pack_rects(&rectpacker, raw_data(rects), cast(i32)used_rects)

	for rect in rects[:used_rects] {
		rect_arena_temp := vmem.arena_temp_begin(&atlas.core.frame_arena)
		defer vmem.arena_temp_end(rect_arena_temp)

		texture_id := cast(Texture_Atlas_Texture_Id)rect.id
		assert(textureatlas_is_texture_valid(atlas^, texture_id))

		texture_info := &atlas.texture_info[texture_id]

		prev_status := texture_info.status
		if rect.was_packed {
			texture_info.position.x = cast(u32)rect.x
			texture_info.position.y = cast(u32)rect.y
			texture_info.status = .Uploaded
		} else {
			texture_info.status = .Upload_Failed
		}

		if !rect.was_packed || prev_status != .Upload_Pending {
			continue
		}

		data_to_upload, data_to_upload_res := make(
			[]byte,
			texture_info.size.x * texture_info.size.y * cast(u32)atlas.pixel_stride,
			atlas.core.frame_allocator,
		)
		if data_to_upload_res != .None {
			did_pack_all = false
			texture_info.status = .Upload_Failed
			continue
		}

		for y in 0..<texture_info.size.y {
			for x in 0..<texture_info.size.x {
				upload_pixel_index := (x + y * texture_info.size.x) * cast(u32)atlas.pixel_stride
				texture_pixel_index := (x + y * texture_info.size.x) * cast(u32)atlas.pixel_size

				if atlas.pixel_stride != atlas.pixel_size && atlas.default_pixel_value != nil {
					runtime.mem_copy_non_overlapping(
						&data_to_upload[upload_pixel_index],
						raw_data(atlas.default_pixel_value),
						cast(int)atlas.pixel_stride,
					)
				}

				runtime.mem_copy_non_overlapping(
					&data_to_upload[upload_pixel_index],
					&texture_info.data_to_upload[texture_pixel_index],
					cast(int)atlas.pixel_size,
				)
			}
		}

		write_ok := wgpu.queue_write_texture(
			atlas.core.queue,
			wgpu.Image_Copy_Texture {
				texture = atlas.backing_texture,
				mip_level = 0,
				origin = wgpu.Origin_3D {
					texture_info.position.x + cast(u32)atlas.border_size,
					texture_info.position.y + cast(u32)atlas.border_size,
					0,
				},
				aspect = .All,
			},
			data_to_upload,
			wgpu.Texture_Data_Layout {
				offset = 0,
				bytes_per_row = texture_info.size.x * cast(u32)atlas.pixel_stride,
				rows_per_image = texture_info.size.y,
			},
			size = wgpu.Extent_3D {
				texture_info.size.x,
				texture_info.size.y,
				1,
			},
		)
		if !write_ok {
			did_pack_all = false
			texture_info.status = .Upload_Failed
			continue
		}
	}

	atlas.last_uploaded_texture_index = len(atlas.texture_info)

	return nil
}

