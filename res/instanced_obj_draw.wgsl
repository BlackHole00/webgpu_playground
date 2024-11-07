// This shader draws a single model stored using the standard obj layout
#include <stdlib/types.wgsli>
#include <stdlib/constants.wgsli>

// Memory related data
@group(0) @binding(0) var<storage, read> layout_infos: array<Layout_Info, layout_count>;
@group(0) @binding(1) var<storage, read> model_infos: array<Model_Info>;
@group(0) @binding(2) var<storage, read> texture_infos: array<Texture_Info>;
@group(0) @binding(3) var<storage, read> vertices: array<u32>;
@group(0) @binding(4) var<storage, read> indices: array<u32>;
@group(0) @binding(5) var atlas: texture_2d<f32>;

// Current scene related data
@group(1) @binding(0) var<uniform> draw_batch: Draw_Batch_Info;
@group(1) @binding(1) var<uniform> draw_call: Draw_Call_Info;
@group(1) @binding(1) var<storage, read> objects: array<Object_Info>;
// ... ambiental data, lights data...

// Generic utilities
@group(2) @binding(0) var generic_sampler: sampler;
@group(2) @binging(1) var pixelperfect_sampler: sampler;

struct Vertex_Out {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
    @location(1) normal: vec3f,
}

struct Fragment_In {
    @location(0) uv: vec2f,
    @location(0) normal: vec3f,
}

@vertex
fn vertex_main(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(istance_index) instance_index: i32,
) -> Vertex_Out {
    let model_id = objects[draw_call.object].model;
    let layout_id = model_infos[model_id].layout;

    let uberindex_size = layout_infos[layout_id].indices_count;
    let first_uberindex_offset = model_infos[model_id].first_uberindex_offset;
    let current_uberindex_offset = first_uberindex_offset + uberindex_size * vertex_index;

    let position_index = indices[current_uberindex_offset];
    let uv_index = indices[current_uberindex_offset + 1];
    let normal_index = indices[current_uberindex_offset + 2];

    let position = vec3f(
        f32(vertices[position_index]),
        f32(vertices[position_index + 1]),
        f32(vertices[position_index + 2]),
    );
    let uv = vec2f(
        f32(vertices[uv_index]),
        f32(vertices[uv_index + 1]),
    );
    let normal = vec3f(
        f32(vertices[normal_index]),
        f32(vertices[normal_index + 1]),
        f32(vertices[normal_index + 2]),
    );

    return Vertex_Out {
        position = vec4f(position, 1.0);
        uv = uv;
        normal = normal;
    };
}

@fragment
fn fragment_main(vertex_in: Vertex_In) -> @layout(0) vec4f {
    return vec4f(vertex_in.normal, 1.0);
}


