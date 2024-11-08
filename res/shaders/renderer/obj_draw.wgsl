#include <stdlib/render_common.wgsli>

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
    let model = gfx::current_model();
    let camera = gfx::current_camera();
    let object = gfx::current_object(instance_index);

    let position_index = gfx::model_index_of(model, vertex_index, 0u);
    let uv_index = gfx::model_index_of(model, vertex_index, 1u);
    let normal_index = gfx::model_index_of(model, vertex_index, 2u);

    let position = gfx::vertices_read_vec3f(position_index);
    let uv = gfx::vertices_read_vec2f(uv_index);
    let normal = gfx::vertices_read_vec3f(uv_index);

    let projection_matrix = gfx::camera_projection_matrix(camera);
    let view_matrix = gfx::camera_view_matrix(camera);
    let object_matrix = gfx::object_matrix(object);

    return Vertex_Out(
        math::OPENGL_TO_WGPU_MATRIX * projection_matrix * view_matrix * object_matrix * vec4f(position, 1.0f),
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

