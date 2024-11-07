// This shader draws a single model stored using the standard obj layout
#include <stdlib/types.wgsli>
#include <stdlib/constants.wgsli>

// Memory related data
@group(0) @binding(0) var<uniform> application_state: Application_State;
@group(0) @binding(1) var<storage, read> memory_layout_infos: array<Memory_Layout_Info, layout_count>;
@group(0) @binding(2) var<storage, read> model_infos: array<Model_Info>;
@group(0) @binding(3) var<storage, read> texture_infos: array<Texture_Info>;
@group(0) @binding(4) var<storage, read> vertices: array<u32>;
@group(0) @binding(5) var<storage, read> indices: array<u32>;
@group(0) @binding(6) var<storage, read> object_instances: array<Object_Info>;
@group(0) @binding(7) var atlas: texture_2d<f32>;

// Current scene related data
@group(1) @binding(0) var<uniform> draw_call: Draw_Call_Info;
@group(1) @binding(1) var<storage, read> cameras: array<Camera_Info>;
@group(1) @binding(2) var<storage, read> draw_objects: array<Object>;
// ... ambiental data, lights data...

// Generic utilities
@group(2) @binding(0) var generic_sampler: sampler;
@group(2) @binding(1) var pixelperfect_sampler: sampler;

struct Vertex_Out {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
    @location(1) normal: vec3f,
}
alias Vertex_In = Vertex_Out;

struct Fragment_In {
    @location(0) uv: vec2f,
    @location(0) normal: vec3f,
}

@vertex
fn vertex_main(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
) -> Vertex_Out {
    // Gets the model_id in order to be able to fetch the layout
    let model_id = draw_call.model_id;
    // Gets the layout_id in order to understand how we should fetch the data in
    // the indices and vertices buffers
    let layout_id = model_infos[model_id].memory_layout;
    // Gets the object_id in order to find the model matrix (note: the first
    // instance_index is 1)
    let object_id = draw_objects[draw_call.object_offset + instance_index - 1];
    // let camera_id = draw_call.camera;
    let camera_id = 0;

    // Calculates the current indices in the uberindex buffer
    let uberindex_size = memory_layout_infos[layout_id].indices_count;
    let first_uberindex_offset = model_infos[model_id].first_uberindex_offset;
    let current_uberindex_offset = first_uberindex_offset + uberindex_size * vertex_index;

    // Gets the vertex data
    let position_index = indices[current_uberindex_offset];
    let uv_index = indices[current_uberindex_offset + 1];
    let normal_index = indices[current_uberindex_offset + 2];

    let position = vec4f(
        bitcast<f32>(vertices[position_index]),
        bitcast<f32>(vertices[position_index + 1]),
        bitcast<f32>(vertices[position_index + 2]),
        1.0f,
    );
    let uv = vec2f(
        bitcast<f32>(vertices[uv_index]),
        bitcast<f32>(vertices[uv_index + 1]),
    );
    let normal = vec3f(
        bitcast<f32>(vertices[normal_index]),
        bitcast<f32>(vertices[normal_index + 1]),
        bitcast<f32>(vertices[normal_index + 2]),
    );

    let projection_matrix = cameras[camera_id].projection_matrix;
    let view_matrix = cameras[camera_id].view_matrix;
    let object_matrix = object_instances[object_id].object_matrix;

    return Vertex_Out(
        // object_instances[object_id].object_matrix * position,
        // OPENGL_TO_WGPU_MATRIX * cameras[camera_id].projection_matrix * cameras[camera_id].view_matrix * object_instances[object_id].object_matrix * position,
        OPENGL_TO_WGPU_MATRIX * projection_matrix * view_matrix * object_matrix * position,
        uv,
        normal,
    );
}

@fragment
fn fragment_main(vertex_in: Vertex_In) -> @location(0) vec4f {
    let uv = vertex_in.uv * 0.5;
    let uv_color = vec4f(
        uv.x,
        0.0,
        uv.y,
        1.0,
    );

    return uv_color;
}

