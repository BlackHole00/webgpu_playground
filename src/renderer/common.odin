package renderer

import "base:runtime"

Render_Pipeline_Type :: enum {
	// Deferred_To_GBuffers,
	// Defferred_To_Rendertarget,
	// Skybox_To_Rendertarget,
	MicroUI_To_Rendertarget,
}

Vertex_Layout_Type :: enum {
	// { }
	None,
	// { position: [3]f32, uv: [2]f32, normal: [3]f32 }
	Basic,
	// { position: [4]f32, uv: [2]f32, color: [4]f32 }
	MicroUI,
}

Texture_Type :: enum {
	Surface_Depth,
	General_Atlas,
	MicroUI_Atlas,
}

Sampler_Type :: enum {
	Generic,
	Pixel_Perfect,
}

Render_Target :: enum {
	Default,
}

Bindgroup_Type :: enum {
	// Holds information specific to the current draw call (like the view and projection matrices) and the current 
	// application state (like time)
	Draw_Command,
	// Holds references to the textures and samplers available
	Textures,
}

Basic_Instance_Data :: struct {
	model: [4]f32,
}

Common_Error :: enum {
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
	Common_Error,
}

