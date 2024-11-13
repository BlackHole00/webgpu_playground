package renderer

import "base:runtime"
import "core:log"
import vmem "core:mem/virtual"
import "vendor:wgpu"
import rp "vendor:stb/rect_pack"
import wgputils "wgpu"

Atlas_Manager_Common_Error :: enum {
	Atlas_Resize_Failed,
}

Atlas_Manager_Result :: union #shared_nil {
	Atlas_Manager_Common_Error,
	runtime.Allocator_Error,
}

Write_Data :: struct {
	// Expected to be allocated with a temp allocator
	texture_data: []byte,
	// It is not used by the atlas, it is used by the used to know where a 
	// certain texture ended up in the atlas
	texture_id: Texture,
	size: [2]uint,
}

Texture_Apply_Info :: struct {
	texture_id: Texture,
	size: [2]uint,
	position: [2]uint,
}

Atlas_Manager_Descriptor :: struct {
	queue: wgpu.Queue,
	backing_info_buffer: wgputils.Buffer_Slice,
	backing_texture: ^wgputils.Dynamic_Texture,
	texture_pixel_size: uint,
	texture_border_size: uint,
}

Atlas_Manager :: struct {
	arena: vmem.Arena,

	queue: wgpu.Queue,
	backing_info_buffer: wgputils.Buffer_Slice,
	backing_texture: ^wgputils.Dynamic_Texture,

	texture_pixel_size: uint,
	texture_border_size: uint,

	queued_writes: [dynamic]Write_Data,
	written_rects: [dynamic]rp.Rect,
}

atlasmanager_create :: proc(
	manager: ^Atlas_Manager,
	descriptor: Atlas_Manager_Descriptor,
	allocator := context.allocator,
	location := #caller_location,
) -> Atlas_Manager_Result {
	when ODIN_DEBUG {
		backing_buffer_size := wgputils.bufferslice_get_size(descriptor.backing_info_buffer)
		assert(backing_buffer_size >= size_of(Atlas_Gpu_Info))

		assert(descriptor.queue != nil)
		assert(descriptor.backing_texture != nil)
		assert(descriptor.texture_pixel_size > 0)
	}

	if arena_err := vmem.arena_init_growing(&manager.arena); arena_err != .None {
		log.errorf(
			"Could not init an Atlas Manager: Could not init an arena, got error %v",
			arena_err,
			location = location,
		)
		return arena_err
	}

	manager.queue               = descriptor.queue
	manager.backing_info_buffer = descriptor.backing_info_buffer
	manager.backing_texture     = descriptor.backing_texture
	manager.texture_border_size = descriptor.texture_border_size
	manager.texture_pixel_size  = descriptor.texture_pixel_size

	manager.queued_writes = make([dynamic]Write_Data, allocator) or_return
	manager.written_rects = make([dynamic]rp.Rect, allocator) or_return

	atlasmanager_refresh_info_buffer(manager^)

	return nil
}

atlasmanager_destroy :: proc(manager: ^Atlas_Manager) {
	vmem.arena_destroy(&manager.arena)
	delete(manager.queued_writes)
	delete(manager.written_rects)
}

// Expects that atlasmanager_apply is called before the temp allocated is "flushed"
atlasmanager_queue_add_texture :: proc(manager: ^Atlas_Manager, texture: Write_Data) -> Atlas_Manager_Result {
	append(&manager.queued_writes, texture) or_return
	return nil
}

atlasmanager_apply :: proc(
	manager: ^Atlas_Manager,
	allocator := context.temp_allocator,
	location := #caller_location,
) -> (applied_textures: []Texture_Apply_Info, result: Atlas_Manager_Result) {
	arena_temp := vmem.arena_temp_begin(&manager.arena)
	defer vmem.arena_temp_end(arena_temp)

	rects_written := len(manager.written_rects)
	atlas_size := wgputils.dynamictexture_get_size(manager.backing_texture^)

	atlas_has_been_resized := false
	defer if atlas_has_been_resized {
		atlasmanager_refresh_info_buffer(manager^)
	}

	for write in manager.queued_writes {
		rect := rp.Rect {
			w = (rp.Coord)(write.size.x + manager.texture_border_size * 2),
			h = (rp.Coord)(write.size.y + manager.texture_border_size * 2),
		}
		append(&manager.written_rects, rect)
	}

	for {
		packer: rp.Context
		nodes := make([]rp.Node, atlas_size.width + 1, vmem.arena_allocator(&manager.arena)) or_return

		rp.init_target(
			&packer,
			(i32)(atlas_size.width),
			(i32)(atlas_size.height),
			raw_data(nodes),
			(i32)(len(nodes),
		))
		did_pack_all := rp.pack_rects(&packer, raw_data(manager.written_rects), (i32)(len(manager.written_rects))) == 1

		if did_pack_all {
			break
		}

		atlas_size = wgpu.Extent3D { atlas_size.width * 2, atlas_size.height * 2, 1 }
		if !wgputils.dynamictexture_resize(manager.backing_texture, atlas_size, true) {
			log.errorf(
				"Could not apply changes to the atlas manager: Could not resize the backing texture",
				location = location,
			)

			atlas_has_been_resized = true
			resize(&manager.written_rects, rects_written)
			return nil, .Atlas_Resize_Failed
		}
	}
	
	applied_textures = make([]Texture_Apply_Info, len(manager.written_rects) - rects_written, allocator)
	for i in rects_written..<len(manager.written_rects) {
		queue_idx := i - rects_written

		written_rect_info  := &manager.written_rects[i]
		write_info         := &manager.queued_writes[queue_idx]

		assert(written_rect_info.was_packed == true)

		wgpu.QueueWriteTexture(
			manager.queue,
			&wgpu.ImageCopyTexture {
				mipLevel = 0,
				texture = manager.backing_texture.handle,
				origin = { 
					(u32)(written_rect_info.x) + (u32)(manager.texture_border_size),
					(u32)(written_rect_info.y) + (u32)(manager.texture_border_size),
					0,
				},
				aspect = .All,
			},
			raw_data(write_info.texture_data),
			len(write_info.texture_data),
			&wgpu.TextureDataLayout {
				offset = 0,
				bytesPerRow = (u32)(manager.texture_pixel_size * write_info.size.x),
				rowsPerImage = (u32)(write_info.size.y),
			},
			&wgpu.Extent3D {
				(u32)(write_info.size.x),
				(u32)(write_info.size.y),
				1,
			},
		)

		applied_textures[i] = Texture_Apply_Info {
			size = write_info.size,
			texture_id = write_info.texture_id,
			position = {
				(uint)(written_rect_info.x) + manager.texture_border_size,
				(uint)(written_rect_info.y) + manager.texture_border_size,
			},
		}
	}

	resize(&manager.queued_writes, 0)
	return
}

atlasmanager_refresh_info_buffer :: proc(manager: Atlas_Manager) {
	atlas_size := wgputils.dynamictexture_get_size(manager.backing_texture^)

	wgputils.bufferslice_queue_write(
		manager.backing_info_buffer,
		manager.queue,
		0,
		&Atlas_Gpu_Info {
			size = { atlas_size.width, atlas_size.height },
		},
		size_of(Atlas_Gpu_Info),
	)
}

@(private)
Atlas_Gpu_Info :: struct {
	size: [2]u32,
}

