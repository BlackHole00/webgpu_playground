package renderer

Basic_Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
	normal: [3]f32,
}

// A basic MicroUI vertex. It can be used to render all the commands emitted by
// MU. Please note that, in order to use a single pipeline, the renderer will
// need to use the following alpha value:
//     - texture color alpha: 1.0 - color.a
// This allows to ignore the texture or the color depending on the draw command
// without using branches in the shader code
MicroUI_Vertex :: struct {
	position: [3]f32,
	uv: [3]f32,
	color: [4]f32,
}
