package renderer

import "core:log"
import "vendor:wgpu"

// A Layout is a structure specifing how data for each vertex should be fetched. Beware that it does not contain the vertex layout itself, but only where to fetch the data.
// Let's consider a basic vertex defined as:
//   Basic_Vertex :: struct {
//       position: [3]f32,
//       uv: [2]f32,
//   }
// The its layout is simply:
//   Layout_Info {
//       indices_count = 1,
//       vertex_sizes = [8]u32 { 0 = size_of(Basic_Vertex) },
//   }
// Because the vertex data is read from only one source (index).
// If the user desires to read the position and uv from two different indices it can be done with the following layout:
//   Layout_Info {
//       indices_count = 2,
//       vertex_sizes = [8]u32 { 0 = size_of([3]f32), 1 = size_of([2]f32)}
//   }
// Please note that a single layout can only support 8 different sources and one must be provided at every moment
Memory_Layout :: distinct u32
INVALID_LAYOUT :: max(Memory_Layout)

Vertex_Word :: u32

Memory_Layout_Info :: struct {
	indices_count : u32, // in range 0..8
	source_sizes  : [MAX_LAYOUT_INDICES]u32,
}

Memory_Layout_Descriptor :: struct {
	indices_count: u32,
	source_sizes: []u32,
}

// TODO(Vicix): Migrate to Mirrored_Buffer
Memory_Layout_Manager :: struct {
	infos: [dynamic]Memory_Layout_Info, // capacity: 128
	queue: wgpu.Queue,
	backing_buffer: wgpu.Buffer, // required_size: 128 * size_of(Layout_Info)
}

memorylayoutmanager_create :: proc(
	manager: ^Memory_Layout_Manager,
	queue: wgpu.Queue,
	backing_buffer: wgpu.Buffer,
	allocator := context.allocator,
) -> bool {
	if wgpu.BufferGetSize(backing_buffer) < MAX_LAYOUTS * size_of(Memory_Layout_Info) {
		log.errorf("Could not create a layout manager: The provided backing buffer is non big enough")
		return false
	}
	if wgpu.BufferUsage.Storage not_in wgpu.BufferGetUsage(backing_buffer) {
		log.warnf("The provided backing buffer does not have the .Storage usage")
	}

	manager.infos = make([dynamic]Memory_Layout_Info, 0, MAX_LAYOUTS, allocator)
	manager.queue = queue
	manager.backing_buffer = backing_buffer

	return true
}

memorylayoutmanager_destroy :: proc(manager: Memory_Layout_Manager) {
	delete(manager.infos)
}

memorylayoutmanager_register_layout :: proc(
	manager: ^Memory_Layout_Manager,
	descriptor: Memory_Layout_Descriptor,
) -> (Memory_Layout, bool) {
	descriptor := descriptor

	if len(manager.infos) >= MAX_LAYOUTS {
		log.errorf("Could not register a new layout. The max number of layout has already been reached")
		return INVALID_LAYOUT, false
	}
	if descriptor.indices_count == 0 || descriptor.indices_count > MAX_LAYOUT_INDICES {
		log.errorf("Could not register a new layout. The provided descriptor has an invalid number of indices")
		return INVALID_LAYOUT, false
	}

	layout_idx := len(manager.infos)

	info: Memory_Layout_Info
	info.indices_count = descriptor.indices_count
	copy(info.source_sizes[:], descriptor.source_sizes)

	append(&manager.infos, info)
	wgpu.QueueWriteBuffer(
		manager.queue,
		manager.backing_buffer,
		data = &info,
		bufferOffset = (u64)(layout_idx) * size_of(Memory_Layout_Info),
		size = size_of(Memory_Layout_Info),
	)

	return (Memory_Layout)(layout_idx), true
}

memorylayoutmanager_get_info :: proc(manager: Memory_Layout_Manager, layout: Memory_Layout) -> (^Memory_Layout_Info, bool) {
	if (uint)(layout) >= len(manager.infos) {
		return nil, false
	}
	return &manager.infos[layout], true
}

@(private)
MAX_LAYOUTS :: 128
@(private)
MAX_LAYOUT_INDICES :: 8
