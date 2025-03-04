package renderer

import "core:log"
import "core:fmt"
import "core:slice"
import vmem "core:mem/virtual"
import rp "vendor:stb/rect_pack"
import "shared:wgpu"

// Describes the status of a texture. Please note that the term 'packed' means
// that a texture has a position of the atlas assigned, but its data could not
// be yet uploaded. The term 'uploaded' means that the texture has a designated
// position and its data has been uploaded to the gpu memory.
Multi_Texture_Atlas_Texture_Status :: enum {
	// The texture has been both packed and uploaded and be used for
	// rendering.
	Uploaded,
	// The texture has been packed, but it has not been uploaded yet.
	Upload_Pending,
	// The texture has not been packed nor uploaded.
	Packing_Pending,
	// The texture has been packed, but its upload has failed (this is
	// likely a bug.
	Upload_Failed,
	// The packing of the texture failed. This is likely because there is
	// not enough memory to pack it.
	Packing_Failed,
	Unknown,
}

Multi_Texture_Atlas_Texture_Id :: distinct u32
INVALID_TEXTURE_ATLAS_TEXTURE_ID :: max(Multi_Texture_Atlas_Texture_Id)

// The information relative of a specific texture inside the atlas.
Multi_Texture_Atlas_Texture_Info :: struct {
	// The current texture status.
	status: Multi_Texture_Atlas_Texture_Status,

	// The assigned backing texture index. -1 if none.
	// Index of multi_texture_atlas.backing_textures.
	// Index of multi_texture_atlas.rects.
	assigned_texture_idx: int,

	// The assigned rect of the assigned backing texture. -1 if none.
	// Index of multi_texture_atlas.rects[assigned_texture_idx].
	assigned_rect_idx: int,

	// The size of the texture.
	size: [2]u32,

	// The data to upload to the assigned backing texture
	// NOTE: texture_data is allocated with a frame allocator. So the 
	// request of a registration of a texture and its upload **must** be
	// done in the same frame. Keep also in mind that if the texture packing
	// or the texture upload fails, the texture data is set to none.
	texture_data: []byte,
}

// The descriptor of a Multi_Texture_Atlas.
Multi_Texture_Atlas_Descriptor :: struct {
	// The internal backing textures format.
	texture_format: wgpu.Texture_Format,
	// The size of the backing textures.
	textures_size: [2]u32,
	// The maximum number of backing textures. After the multi texture atlas
	// has requested this number of textures it will not allocate others and
	// will return .Resources_Out_Of_Memory if more memory is needed.
	max_texture_count: u32,
	// The size in byte of a single pixel.
	pixel_size: u8,
	// The number of pixels to left blank between textures.
	border_size: u8,
}

// A texture atlas capable of packing single textures in multiple single texture
// atlases. This approach to atlases allows to have a dynamic number of textures
// that we can handle without having to spend time resizing the atlas. This also
// fixes issues with precision loss on big atlases.
// Keep in mind that the term 'texture' is in relation to the user textures and
// 'backing textures' is in relation of a single texture atlas inside the multi
// texture atlas.
Multi_Texture_Atlas :: struct {
	using descriptor: Multi_Texture_Atlas_Descriptor,
	core: ^Renderer_Core,

	// The registered textures
	texture_info: #soa [dynamic]Multi_Texture_Atlas_Texture_Info,
	last_packed_texture_idx: int,
	last_uploaded_texture_idx: int,

	backing_textures: []wgpu.Texture,
	backing_texture_views: []wgpu.Texture_View,
	backing_texture_count: int,

	packers: []rp.Context,
	nodes: [][]rp.Node,
	// For each backing texture, the packed rects of that texture
	packed_rects: [][dynamic]rp.Rect,
}

multitextureatlas_create :: proc(
	atlas: ^Multi_Texture_Atlas,
	descriptor: Multi_Texture_Atlas_Descriptor,
	core: ^Renderer_Core,
) -> (res: Renderer_Result) {
	assert(core != nil)

	defer if res != nil {
		multitexturealtas_destroy(atlas^)
	}

	atlas.core = core
	atlas.descriptor = descriptor

	atlas.texture_info = make_soa(#soa [dynamic]Multi_Texture_Atlas_Texture_Info, core.allocator) or_return
	atlas.backing_textures = make([]wgpu.Texture, descriptor.max_texture_count, core.global_allocator) or_return
	atlas.packed_rects = make([][dynamic]rp.Rect, descriptor.max_texture_count, core.global_allocator) or_return
	atlas.backing_texture_views = make(
		[]wgpu.Texture_View,
		descriptor.max_texture_count,
		core.global_allocator,
	) or_return

	atlas.nodes = make([][]rp.Node, descriptor.max_texture_count, core.global_allocator) or_return
	for &nodes in atlas.nodes {
		nodes = make([]rp.Node, descriptor.textures_size.x + 1, core.global_allocator) or_return
	}
	atlas.packers = make([]rp.Context, descriptor.max_texture_count, core.global_allocator) or_return
	for &packer, i in atlas.packers {
		rp.init_target(
			&packer,
			cast(i32)atlas.textures_size.x,
			cast(i32)atlas.textures_size.y,
			raw_data(atlas.nodes[i]),
			cast(i32)len(atlas.nodes[i]),
		)
	}

	multitextureatlas_allocate_new_backing_texture(atlas) or_return

	return nil
}

multitexturealtas_destroy :: proc(atlas: Multi_Texture_Atlas) {
	for i in 0..<atlas.backing_texture_count {
		wgpu.texture_view_release(atlas.backing_texture_views[i])
	}

	for i in 0..<atlas.backing_texture_count {
		wgpu.texture_destroy(atlas.backing_textures[i])
		wgpu.texture_release(atlas.backing_textures[i])
	}
}

multitextureatlas_add_texture :: proc(
	atlas: ^Multi_Texture_Atlas,
	data: []byte,
	size: [2]u32,
) -> (texture: Multi_Texture_Atlas_Texture_Id, res: Renderer_Result) {
	texture = INVALID_TEXTURE_ATLAS_TEXTURE_ID

	if size.x >= atlas.textures_size.x || size.y >= atlas.textures_size.y {
		return INVALID_TEXTURE_ATLAS_TEXTURE_ID, .Input_Too_Big
	}

	owned_data := slice.clone(data, atlas.core.frame_allocator) or_return
	append(
		&atlas.texture_info,
		Multi_Texture_Atlas_Texture_Info {
			status = .Packing_Pending,
			assigned_texture_idx = -1,
			assigned_rect_idx = -1,
			size = size,
			texture_data = owned_data,
		},
	) or_return

	texture = cast(Multi_Texture_Atlas_Texture_Id)(len(atlas.texture_info) - 1)
	return
}

multitextureatlas_pack_pending :: proc(
	atlas: ^Multi_Texture_Atlas,
) -> (did_pack_all: bool, res: Renderer_Result) {
	assert(atlas != nil)

	if len(atlas.texture_info) <= atlas.last_packed_texture_idx {
		return true, nil
	}

	log.infof(
		"Multi_Texture_Atlas (%s): packing pending textures...",
		atlas.texture_format,
	)

	i := 0
	for {
		if i >= cast(int)atlas.max_texture_count {
			res = .Resources_Out_Of_Memory
			break
		} else if i == atlas.backing_texture_count {
			multitextureatlas_allocate_new_backing_texture(atlas) or_return
		}

		did_pack_all = multitextureatlas_try_pack_to_texture(atlas, i) or_return
		if did_pack_all {
			break
		}
		i += 1
	}

	if !did_pack_all {
		log.warnf(
			"Multi_Texture_Atlas (%s): could not pack all textures. Failed to pack:",
			atlas.texture_format,
		)
	}

	for &texture_info, texture_idx in atlas.texture_info[atlas.last_packed_texture_idx:] {
		if texture_info.status == .Packing_Pending {
			log.warnf("\t- Texture %d", atlas.last_packed_texture_idx + texture_idx)
			texture_info.status = .Packing_Failed
			texture_info.texture_data = nil
		}
	}

	atlas.last_packed_texture_idx = len(atlas.texture_info)
	return
}

multitextureatlas_upload_pending :: proc(
	atlas: ^Multi_Texture_Atlas,
) -> (did_upload_all: bool, res: Renderer_Result) {
	assert(atlas != nil)

	if len(atlas.texture_info) <= atlas.last_uploaded_texture_idx {
		return true, nil
	}

	_ = multitextureatlas_pack_pending(atlas) or_return

	log.infof(
		"Multi_Texture_Atlas (%s): uploading pending textures...",
		atlas.texture_format,
	)

	for &texture_info, i in atlas.texture_info[atlas.last_uploaded_texture_idx:] {
		assert(
			texture_info.status != .Uploaded,
			"Found already uploaded texture after atlas.last_uploaded_texture_idx",
		)
		if texture_info.status != .Upload_Pending {
			continue
		}

		texture_id := cast(Multi_Texture_Atlas_Texture_Id)(atlas.last_uploaded_texture_idx + i)
		multitextureatlas_upload_texture(atlas, texture_id)
	}

	atlas.last_uploaded_texture_idx = len(atlas.texture_info) - 1

	return false, nil
}

multitextureatlas_is_texture_valid :: proc(
	atlas: Multi_Texture_Atlas,
	texture_id: Multi_Texture_Atlas_Texture_Id,
) -> bool {
	return texture_id < cast(Multi_Texture_Atlas_Texture_Id)len(atlas.texture_info)
}

multitextureatlas_is_texture_uploaded :: proc(
	atlas: Multi_Texture_Atlas,
	texture_id: Multi_Texture_Atlas_Texture_Id,
) -> bool {
	if !multitextureatlas_is_texture_valid(atlas, texture_id) {
		return false
	}

	return atlas.texture_info[texture_id].status == .Uploaded
}

multitextureatlas_get_texture_status :: proc(
	atlas: Multi_Texture_Atlas,
	texture_id: Multi_Texture_Atlas_Texture_Id,
) -> (status: Multi_Texture_Atlas_Texture_Status, ok: bool) {
	if !multitextureatlas_is_texture_valid(atlas, texture_id) {
		return .Unknown, false
	}

	return atlas.texture_info[texture_id].status, true
}

multitextureatlas_get_texture_absolute_position :: proc(
	atlas: Multi_Texture_Atlas,
	texture_id: Multi_Texture_Atlas_Texture_Id,
) -> (
	position: [3]u32,
	size: [2]u32,
	ok: bool,
) {
	// TODO: Change this
	if !multitextureatlas_is_texture_uploaded(atlas, texture_id) {
		return {}, {}, false
	}

	assigned_texture_idx := atlas.texture_info[texture_id].assigned_texture_idx
	assigned_rect_idx := atlas.texture_info[texture_id].assigned_rect_idx
	assigned_rect := &atlas.packed_rects[assigned_texture_idx][assigned_rect_idx]

	position = [3]u32{
		cast(u32)assigned_rect.x,
		cast(u32)assigned_rect.y,
		cast(u32)assigned_texture_idx,
	}
	size = atlas.texture_info[texture_id].size
	ok = true
	return
}

multitextureatlas_get_texture_relative_position :: proc(
	atlas: Multi_Texture_Atlas,
	texture_id: Multi_Texture_Atlas_Texture_Id,
) -> (
	position: [2]f32,
	size: [2]f32,
	ok: bool,
) {
	absolute_position, absolute_size, absolute_ok := multitextureatlas_get_texture_absolute_position(
		atlas,
		texture_id,
	)
	if !absolute_ok {
		return {}, {}, false
	}

	position = [2]f32{
		cast(f32)absolute_position.x / cast(f32)atlas.textures_size.x,
		cast(f32)absolute_position.y / cast(f32)atlas.textures_size.y,
	}
	size = [2]f32{
		cast(f32)absolute_size.x / cast(f32)atlas.textures_size.x,
		cast(f32)absolute_size.y / cast(f32)atlas.textures_size.y,
	}
	ok = true
	return
}

multitextureatlas_populate_bindgrouplayoutdescriptor :: proc(
	atlas: Multi_Texture_Atlas,
	descriptor: ^wgpu.Bind_Group_Layout_Descriptor,
	binding_idx: int,
) {
	assert(descriptor != nil)
	assert(binding_idx < len(descriptor.entries))

	descriptor.entries[binding_idx] = wgpu.Bind_Group_Layout_Entry {
		binding = cast(u32)binding_idx,
		visibility = { .Vertex, .Fragment },
		type = wgpu.Texture_Binding_Layout {
			sample_type = .Float,
			view_dimension = .D2,
		},
	}
}

multitextureatlas_populate_bindgroupdescriptor :: proc(
	atlas: Multi_Texture_Atlas,
	descriptor: ^wgpu.Bind_Group_Descriptor,
	binding_idx: int,
) {
	assert(descriptor != nil)
	assert(binding_idx < len(descriptor.entries))

	texture_views := multitextureatlas_get_texture_views(atlas)

	descriptor.entries[binding_idx] = wgpu.Bind_Group_Entry {
		binding = cast(u32)binding_idx,
		resource = texture_views,
	}
}

multitextureatlas_get_texture_views :: proc(
	atlas: Multi_Texture_Atlas,
) -> []wgpu.Texture_View {
	return atlas.backing_texture_views[atlas.backing_texture_count:]
}

@(private="file")
multitextureatlas_try_pack_to_texture :: proc(
	atlas: ^Multi_Texture_Atlas,
	texture_idx: int,
) -> (did_pack_all: bool, res: Renderer_Result) {
	assert(atlas != nil)
	assert(texture_idx >= 0)
	assert(texture_idx < atlas.backing_texture_count)

	log.debugf(
		"Multi_Texture_Atlas (%s): packing rects of texture #%d...",
		atlas.texture_format,
		texture_idx,
	)

	arena_temp := vmem.arena_temp_begin(&atlas.core.frame_arena)
	defer vmem.arena_temp_end(arena_temp)

	new_textures_to_pack := len(atlas.texture_info) - atlas.last_packed_texture_idx

	rects := make([]rp.Rect, new_textures_to_pack, atlas.core.frame_allocator) or_return
	rects_count := 0

	for new_texture_info, i in atlas.texture_info[atlas.last_packed_texture_idx:] {
		assert(
			new_texture_info.status != .Uploaded,
			"Found already uploaded texture after atlas.last_packed_texture_idx",
		)

		if new_texture_info.status != .Packing_Pending {
			continue
		}

		rects[rects_count] = rp.Rect {
			id = cast(i32)(atlas.last_packed_texture_idx + i),
			w = cast(rp.Coord)new_texture_info.size.x + cast(rp.Coord)atlas.border_size,
			h = cast(rp.Coord)new_texture_info.size.y + cast(rp.Coord)atlas.border_size,
		}
		rects_count += 1
	}
	if rects_count == 0 {
		return true, nil
	}

	did_pack_all = cast(bool)rp.pack_rects(&atlas.packers[texture_idx], raw_data(rects), cast(i32)rects_count)

	for rect in rects[:rects_count] {
		if !rect.was_packed {
			continue
		}

		append(&atlas.packed_rects[texture_idx], rect) or_return

		atlas.texture_info[rect.id].status = .Upload_Pending
		atlas.texture_info[rect.id].assigned_texture_idx = texture_idx
		atlas.texture_info[rect.id].assigned_rect_idx = len(atlas.packed_rects[texture_idx]) - 1

		log.debugf(
			"Multi_Texture_Atlas (%s): packed texture %d to backing texture #%d.",
			atlas.texture_format,
			rect.id,
			texture_idx,
		)
	}

	return
}

@(private="file")
multitextureatlas_allocate_new_backing_texture :: proc(
	atlas: ^Multi_Texture_Atlas,
) -> (res: Renderer_Result) {
	assert(atlas != nil)

	if atlas.backing_texture_count == cast(int)atlas.max_texture_count {
		return .Resources_Out_Of_Memory
	}

	context.temp_allocator = atlas.core.frame_allocator

	log.infof(
		"Multi_Texture_Atlas (%s): allocating backing texture #%d...",
		atlas.texture_format,
		atlas.backing_texture_count,
	)

	texture_label := fmt.tprintf(
		"Multi_Texture_Atlas (%s): backing texture #%d",
		atlas.texture_format,
		atlas.backing_texture_count,
	)
	texture_view_label := fmt.tprintf(
		"Multi_Texture_Atlas (%s): backing texture view #%d",
		atlas.texture_format,
		atlas.backing_texture_count,
	)

	backing_texture_descriptor := wgpu.Texture_Descriptor {
		label = texture_label,
		usage = { .Texture_Binding, .Copy_Dst },
		dimension = .D2,
		size = wgpu.Extent_3D {
			width = atlas.descriptor.textures_size.x,
			height = atlas.descriptor.textures_size.y,
			depth_or_array_layers = 1,
		},
		format = atlas.descriptor.texture_format,
		mip_level_count = 1,
		sample_count = 1,
		view_formats = []wgpu.Texture_Format{ atlas.descriptor.texture_format },
	}
	backing_texture, backing_texture_ok := wgpu.device_create_texture(
		atlas.core.device,
		backing_texture_descriptor,
	)
	if !backing_texture_ok {
		return .Could_Not_Create_Texture
	}
	defer if res != nil {
		wgpu.texture_destroy(backing_texture)
		wgpu.texture_release(backing_texture)
	}

	backing_texture_view, backing_texture_view_ok := wgpu.texture_create_view(
		backing_texture,
		wgpu.Texture_View_Descriptor {
			label = texture_view_label,
			format = atlas.texture_format,
			dimension = .D2,
			base_mip_level = 0,
			mip_level_count = 1,
			base_array_layer = 0,
			array_layer_count = 1,
			aspect = .All,
			usage = { .Texture_Binding },
		},
	)
	if !backing_texture_view_ok {
		return .Could_Not_Create_Texture_View
	}
	defer if res != nil {
		wgpu.texture_view_release(backing_texture_view)
	}

	atlas.packed_rects[atlas.backing_texture_count] = make([dynamic]rp.Rect, atlas.core.allocator) or_return
	defer if res != nil {
		delete(atlas.packed_rects[atlas.backing_texture_count])
	}
	atlas.backing_textures[atlas.backing_texture_count] = backing_texture
	atlas.backing_texture_views[atlas.backing_texture_count] = backing_texture_view

	atlas.backing_texture_count += 1
 
	return nil
}

@(private="file")
multitextureatlas_upload_texture :: proc(
	atlas: ^Multi_Texture_Atlas,
	texture: Multi_Texture_Atlas_Texture_Id,
) -> bool {
	texture_info := &atlas.texture_info[texture]

	assert(atlas != nil)
	assert(texture_info.status == .Upload_Pending, "Cannot upload a texture that is not .Upload_Pending")

	log.debugf(
		"Multi_Texture_Atlas (%s): uploading texture %d to backing texture #%d...",
		atlas.texture_format,
		texture,
		texture_info.assigned_texture_idx,
	)

	texture_rect := atlas.packed_rects[texture_info.assigned_texture_idx][texture_info.assigned_rect_idx]

	write_ok := wgpu.queue_write_texture(
		atlas.core.queue,
		wgpu.Texel_Copy_Texture_Info {
			texture = atlas.backing_textures[texture_info.assigned_texture_idx],
			mip_level = 0,
			origin = wgpu.Origin_3D {
				x = cast(u32)texture_rect.x,
				y = cast(u32)texture_rect.y,
				z = 0,
			},
		},
		texture_info.texture_data,
		wgpu.Texel_Copy_Buffer_Layout {
			offset = 0,
			bytes_per_row = cast(u32)atlas.pixel_size * texture_info.size.x,
			rows_per_image = texture_info.size.y,
		},
		size = wgpu.Extent_3D {
			width = texture_info.size.x,
			height = texture_info.size.y,
			depth_or_array_layers = 1,
		},
	)
	if !write_ok {
		log.errorf(
			"Multi_Texture_Atlas (%s): could not upload texture %d...",
			atlas.texture_format,
			texture,
		)

		texture_info.status = .Upload_Failed
	} else {
		texture_info.status = .Uploaded
	}
	texture_info.texture_data = nil

	return write_ok
}

