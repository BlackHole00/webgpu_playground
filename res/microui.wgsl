// This shader expects:
//     - vertices: { position: [3]f32, uv: [2]f32 }, varies per vertex
//     - instance: { model: matrix[4, 4]f32 }, varies per instance
//     - general state uniform, varies per draw call, bind group 0
//     - instance uniform, varies per draw call, bind group 0
//     - atlas texture & sampler, bind group 1

const OPENGL_TO_WGPU_MATRIX = mat4x4f(
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 0.5, 0.5,
	0.0, 0.0, 0.0, 1.0,
);

struct VertexInput {
	@location(0) position: vec3f,
	@location(1) uv: vec3f,
	@location(2) color: vec4f,
}

struct VertexOutput {
	@builtin(position) position: vec4f,
	@location(0) uv: vec3f,
	@location(1) color: vec4f,
}

struct GeneralState {
	time: f32,
	viewport_size: vec2u,
}

struct InstanceState {
	view: mat4x4f,
	projection: mat4x4f,
}

@group(0) @binding(0) var<uniform> state: GeneralState;
@group(0) @binding(1) var<uniform> instance: InstanceState;
@group(1) @binding(0) var generic_atlas: texture_2d<f32>;
@group(1) @binding(1) var microui_atlas: texture_2d<f32>;
@group(1) @binding(2) var generic_sampler: sampler;
@group(1) @binding(3) var pixelperfect_sampler: sampler;

@vertex
fn vertex_main(vertex_input: VertexInput) -> VertexOutput {
	var output: VertexOutput;
	output.uv = vertex_input.uv;
	output.color = vertex_input.color;
	// output.position = OPENGL_TO_WGPU_MATRIX *
	//  instance.projection *
	//  instance.view *
	//  vec4f(vertex_input.position, 1.0);
	output.position = vec4f(
		vertex_input.position.x / f32(state.viewport_size.x) * 2.0 - 1.0f,
		- vertex_input.position.y / f32(state.viewport_size.y) * 2.0 + 1.0f,
		vertex_input.position.z,
		1.0,
	);
	
	return output;
}

@fragment
fn fragment_main(fragment_input: VertexOutput) -> @location(0) vec4f {
	let mix_alpha = fragment_input.uv.z;

	let solid_color = fragment_input.color;
	let texture_color = vec4f(
		fragment_input.color.xyz,
		textureSample(
			microui_atlas,
			pixelperfect_sampler,
			fragment_input.uv.xy,
		).r,
	);
	
	return mix(solid_color, texture_color, mix_alpha);
}
