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
	@location(1) uv: vec2f,
}

struct InstanceInput {
	@location(2) model_position: vec3f,
}

struct VertexOutput {
	@builtin(position) position: vec4f,
	@location(0) uv: vec2f,
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
@group(1) @binding(0) var atlas: texture_2d<f32>;
@group(1) @binding(1) var atlas_sampler: sampler;

@vertex
fn vertex_main(
	vertex_input: VertexInput,
	instance_input: InstanceInput,
) -> VertexOutput {
	var output: VertexOutput;
	output.uv = vertex_input.uv;
	output.position = 
		OPENGL_TO_WGPU_MATRIX *
		instance.projection *
		instance.view *
		(vec4f(instance_input.model_position, 0.0) + vec4f(vertex_input.position, 1.0));
	
	return output;
}

@fragment
fn fragment_main(fragment_input: VertexOutput) -> @location(0) vec4f {
	let texture_color = textureSample(
		atlas,
		atlas_sampler,
		fragment_input.uv
	).rgb;
	
	return vec4f(texture_color, 1.0);
}
