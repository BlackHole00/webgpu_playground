# Drawing

The renderer does utilize the following rendering procedures (listed in order of preference):
- MultiDrawIndexedIndirectCount(): Allows to draw the entire scene without the need to flush the pipeline once. Supported on Windows and Linux with DX12 and Vulkan
- MultiDrawIndexedIndirect(): Allows to reduce the amount of draw calls, but will require the pipeline to be fushed after the render commands have been built. Supported on Windows, Linux and MacOs. Requires the following buffer to be shared with the CPU before drawing:
  - countBuffer
- DrawIndexedIndirect(): Requires a big number of draw calls 

# Stages

- Models, Textures and generic scene data upload
- Generation of a draw list
