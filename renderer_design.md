# Renderer design

Entirely gpu based. This needs:
- layout buffer [128]
- model buffer [dynamic]
- textures buffer [dynamic]
- vertices buffer [dynamic]
- indices buffer [dynamic]
- a single texture atlas [dynamic]

# Buffers
The metadata buffer should follow the definitions:
```go
Layout_Info :: struct {
  indices_count : u32, // in range 0..8
  vertex_sizes  : [8]u32,
}

Model_Info :: struct {
  layout_info_idx: u32,
  texture_info_idxs: [8]u32,
  indices_offset: u32,
  indices_count: u32,
}

Texture_Info :: struct {
  size: [2]uint,
  offset: [2]uint,
}
```

The vertex buffer is just a big soup of words (32 bit values). This might change due to caching advantages putting vertices of the same layout near each other.  
The index buffer is structured as an array of u32. Each index is however an "uber index", since, depending on the layout, there might be more indices than only one, so the buffer presents itself similarly to the following diagram:  
```
Buffer seen as indices:     | ... | position index | uv index | position index | uv index | packed vertex index    | ... |
Buffer seen as uberindices: | ... | uber index of layout 1    | uber index of layout 1    | uber index of layout 2 | ... |
```

Once an _non-uber_ index is found the corrisponding vertex data can be found at the corrisponding vertex buffer index (indicating the first word of the interested vertex data). For example:
```
Buffer_Layout := Buffer_Info {
  indices_count = 2,
  vertex_size: [8]u32 {
    3, // position
    2, // uv
  }
}

Index Buffer: | ... | 3 | 2 | ... |
                      ^- Position index
                          ^- Uv index

Position = Vertex_Buffer[3:3 + buffer_layout.vertex_size[0]]
Uv = vertex_buffer[2:2 + buffer_layout.vertex_size[1]]
```

In a similar manner the model info stores the info to the layout used to encode the vertices and indicates the first uber index of the model. Since a model can have multiple textures, the index of the info of the textures is stored. The system will use the same uv for all the textures, converting them from the adeguate atlas uv.
