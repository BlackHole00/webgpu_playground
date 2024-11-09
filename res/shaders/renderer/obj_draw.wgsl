#include <stdlib/render_common.wgsli>

struct Vertex_Out {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
    @location(1) normal: vec3f,
}

struct Fragment_In {
    @location(0) uv: vec2f,
    @location(1) normal: vec3f,
}

@vertex
fn vertex_main(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
) -> Vertex_Out {
    let model = gfx::current_model();
    let camera = gfx::current_camera();
    let object = gfx::current_object(instance_index);

    let position_index = gfx::model_index_of(model, vertex_index, 0u);
    let uv_index = gfx::model_index_of(model, vertex_index, 1u);
    let normal_index = gfx::model_index_of(model, vertex_index, 2u);

    let position = gfx::vertices_read_vec3f(position_index);
    var uv = gfx::vertices_read_vec2f(uv_index);
    uv.y = 1.0 - uv.y;
    let normal = gfx::vertices_read_vec3f(uv_index);

    let projection_matrix = gfx::camera_projection_matrix(camera);
    let view_matrix = gfx::camera_view_matrix(camera);
    let object_matrix = gfx::object_matrix(object);

    let texture = bg::data::model_info[model].textures[0];
    let texture_info = bg::data::texture_info[texture];

    // local_uv.y *= -1.0;
    let size = vec2f(f32(texture_info.size.x), f32(texture_info.size.y));
    let atlas_size = vec2f(f32(bg::data::atlas_info[0].size.x), f32(bg::data::atlas_info[0].size.y));
    let atlas_location = vec2f(f32(texture_info.atlas_location.x), f32(texture_info.atlas_location.y));
    let real_uv = (atlas_location + uv * size) / atlas_size;

    return Vertex_Out(
        math::OPENGL_TO_WGPU_MATRIX * projection_matrix * view_matrix * object_matrix * vec4f(position, 1.0f),
        real_uv,
        normal,
    );
}

@fragment
fn fragment_main(fragment_in: Fragment_In) -> @location(0) vec4f {
    // let color = textureSample(bg::data::texture_atlases[0], bg::utils::pixelperfect_sampler, fragment_in.uv).rgb;
    // return vec4f(color, 1.0);
    return textureSample(bg::data::texture_atlases[0], bg::utils::pixelperfect_sampler, fragment_in.uv);
}

