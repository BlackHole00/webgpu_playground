package renderer

import la "core:math/linalg"

Draw_Command_Application_Uniform :: struct {
	time: f32,
	_padding: [4]u8,
	viewport_size: [2]u32,
}

Draw_Command_Instance_Uniform :: struct {
	view: la.Matrix4x4f32,
	projection: la.Matrix4x4f32,
}


