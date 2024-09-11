package main

import "vendor:glfw"
import "vendor:wgpu"

windowhandle_get_surfacedescriptor :: proc(window: glfw.WindowHandle, descriptor: ^wgpu.SurfaceDescriptor) {
	_windowhandle_get_surfacedescriptor(window, descriptor)
}
