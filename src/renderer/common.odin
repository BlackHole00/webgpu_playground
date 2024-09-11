package renderer

import "base:runtime"
import la "core:math/linalg"

Basic_Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

Basic_Instance_Data :: struct {
	model: [4]f32,
}

General_State_Uniform :: struct {
	time: f32,
	viewport_size: [2]u32,
}

Instance_State_Uniform :: struct {
	view: la.Matrix4x4f32,
	projection: la.Matrix4x4f32,
}

Common_Error :: enum {
	Invalid_Glfw_Window,
	Instance_Creation_Failed,
	Surface_Creation_Failed,
	Adapter_Creation_Failed,
	Device_Creation_Failed,
	Bind_Group_Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Adapter_Does_Not_Support_Necessary_Features,
}

Error :: union #shared_nil {
	runtime.Allocator_Error,
	Common_Error,
}

