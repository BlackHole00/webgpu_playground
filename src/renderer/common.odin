package renderer

import "base:runtime"
import "shader_preprocessor"

Render_Pipeline_Type :: enum {
	Obj_Draw,
}

Texture_Type :: enum {
	Surface_Depth,
	General_Atlas,
}

Sampler_Type :: enum {
	Generic,
	Pixel_Perfect,
}

Render_Target :: enum {
	Default,
}

Bindgroup_Type :: enum {
	Data,
	Draw,
	Utilities,
}

Basic_Instance_Data :: struct {
	model: [4]f32,
}

Common_Error :: enum {
	Generic_Error,
	Invalid_Glfw_Window,
	Instance_Creation_Failed,
	Surface_Creation_Failed,
	Adapter_Creation_Failed,
	Device_Creation_Failed,
	Bind_Group_Layout_Creation_Failed,
	Buffer_Creation_Failed,
	Texture_Creation_Failed,
	Sampler_Creation_Failed,
	Bind_Group_Creation_Failed,
	Pipeline_Creation_Failed,
	Adapter_Does_Not_Support_Necessary_Features,
}

Error :: union #shared_nil {
	runtime.Allocator_Error,
	shader_preprocessor.Error,
	Common_Error,
}

