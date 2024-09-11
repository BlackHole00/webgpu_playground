struct GeneralStateUniforms {
	time: f32,
	aspect_rateo: f32,
}

struct InstanceUniforms {
	model: mat4x4f,
	view: mat4x4f,
	projection: mat4x4f,
}

struct VertexInput {
	@location(0) position: vec3f,
	@location(1) color: vec3f,
	@location(2) uv: vec2f,
}

struct VertexOutput {
	@builtin(position) position: vec4f,
	@location(0) color: vec3f,
	@location(1) uv: vec2f,
}

@group(0) @binding(0) var<uniform> state: GeneralStateUniforms;
@group(0) @binding(1) var<uniform> instance: InstanceUniforms;
@group(0) @binding(2) var texture: texture_2d<f32>;
@group(0) @binding(3) var texture_sampler: sampler;

const OPENGL_TO_WGPU_MATRIX = mat4x4f(
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 0.5, 0.5,
	0.0, 0.0, 0.0, 1.0,
);

@vertex
fn vertex_main(input: VertexInput) -> VertexOutput {
	var position = input.position;
	position.x += sin(state.time) * 0.5;
	position.y += cos(state.time) * 0.5;
	position.y *= state.aspect_rateo;
	
	var output: VertexOutput;
	output.position = OPENGL_TO_WGPU_MATRIX * instance.projection * instance.view * instance.model * vec4f(position, 1.0);
	output.color = input.color;
	output.uv = input.uv;
	
	return output;
}

@fragment
fn fragment_main(input: VertexOutput) -> @location(0) vec4f {
	let texture_color = textureSample(texture, texture_sampler, input.uv).rgb;
	let out_color = (texture_color + input.color) / 2.0;
	
    return vec4f(out_color, 1.0);
}
