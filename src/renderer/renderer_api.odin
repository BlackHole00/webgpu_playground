package renderer

import "core:log"

// LOW LEVEL ACCESS
register_memory_layout :: proc(renderer: ^Renderer, descriptor: Memory_Layout_Descriptor) -> (Memory_Layout, bool) {
	layout, layout_ok := memorylayoutmanager_register_layout(&renderer.layout_manager, descriptor)
	if !layout_ok {
		log.warnf("Could not register the memory layout with descriptor %v", descriptor)
		return INVALID_LAYOUT, false
	}

	return layout, true
}
register_texture :: proc(renderer: ^Renderer, texture_file: string) -> (Texture, bool) {
	texture, texture_result := texturemanager_register_texture(&renderer.texture_manager, texture_file)
	if texture_result != nil {
		log.warnf("Could not load texture %s. Got error %v", texture_file, texture_result)
		return INVALID_TEXTURE, false
	}

	return texture, true
}

// User level
register_model :: proc(renderer: ^Renderer, obj_file: string, mtl_file: Maybe(string) = nil) -> (Model, bool) {
	model, model_ok := modelmanager_register_model(renderer.model_manager, obj_file, mtl_file)
	if !model_ok {
		log.warnf("Could not load model %s", obj_file)
		return INVALID_MODEL, false
	}

	return model, true
}

create_pass :: proc() -> uint { unimplemented() }
create_scene :: proc() -> uint { unimplemented() }

create_static_object :: proc(scene: uint, model: uint, position, rotation: [3]f32) -> uint { unimplemented() }

// present :: proc() {}

// MAYBE
create_immediate_object :: proc(scene: uint, model: uint, position, rotation: [3]f32) { unimplemented() }

// INTERNAL
draw_scene :: proc(camera: rawptr, pass: uint, scene: uint) {}
// resize :: proc() {}

