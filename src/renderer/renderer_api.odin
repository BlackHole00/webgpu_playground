package renderer

import "core:log"

register_texture :: proc(renderer: ^Renderer, texture_file: string) -> (Texture, bool) {
	texture, texture_ok := texturemanager_register_texture(&renderer.texture_manager, texture_file)
	if !texture_ok {
		log.warnf("Could not load texture %s", texture_file)
		return INVALID_TEXTURE, false
	}

	return texture, true
}
register_model :: proc(renderer: ^Renderer, obj_file: string, mtl_file: Maybe(string) = nil) -> (Model, bool) {
	if mtl_file != nil {
		unimplemented("register_model does not yet support mtl files")
	}

	model, model_ok := modelmanager_register_model(renderer.model_manager, obj_file)
	if !model_ok {
		log.warnf("Could not load model %s", obj_file)
		return INVALID_MODEL, false
	}

	return model, true
}

create_pass :: proc() -> uint { unimplemented() }
create_scene :: proc() -> uint { unimplemented() }
draw_scene :: proc(camera: rawptr, pass: uint, scene: uint) {}

// present :: proc() {}
resize :: proc() {}

create_static_object :: proc(scene: uint, model: uint, position, rotation: [3]f32) -> uint { unimplemented() }
create_immediate_object :: proc(scene: uint, model: uint, position, rotation: [3]f32) {}
