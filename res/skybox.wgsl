const OPENGL_TO_WGPU_MATRIX = mat4x4f(
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 0.5, 0.5,
	0.0, 0.0, 0.0, 1.0,
);

let VERTICES = array<Vertex, 4>(
	vec2f(-1, -1),
	vec2f( 1, -1),
	vec2f( 1,  1),
	vec2f(-1,  1),
);

struct VertexInput {
	@builtin(vertex_index) vertex_index: u32,
}

struct VertexOutput {
	@builtin(position) position: vec4f,
	@location(0) uv: vec3f,
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
@group(0) @binding(0) var skybox_texture: texture_cube<f32>;
@group(0) @binding(1) var skybox_sampler: sampler;

@vertex
fn vertex_main(input: VertexInput) -> VertexOutput {
	var output: VertexOutput;
	output.position = vec4f(VERTICES[input.vertex_index], 1.0, 1.0);
	output.uv = OPENGL_TO_WGPU_MATRIX * instance.view * output.position;
	
	return output;
}

@fragment
fn fragment_main(input: VertexOutput) -> @location(0) vec4f {
	return texture_sample(skybox_texture, skyblock_sampler, input.uv);
}
