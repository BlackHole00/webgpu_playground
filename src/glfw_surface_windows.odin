package main

import win "core:sys/windows"
import "vendor:glfw"
import "vendor:wgpu"

_windowhandle_get_surfacedescriptor :: proc(window: glfw.WindowHandle, descriptor: ^wgpu.SurfaceDescriptor) {
	@(static)
	windows_descriptor: wgpu.SurfaceDescriptorFromWindowsHWND
	windows_descriptor = wgpu.SurfaceDescriptorFromWindowsHWND {
		sType = .SurfaceDescriptorFromWindowsHWND,
		hwnd = glfw.GetWin32Window(window),
		hinstance = win.GetModuleHandleW(nil),
	}
	
	descriptor.nextInChain = &windows_descriptor
}

