package renderer

import "base:runtime"

Renderer_Error :: enum {
	Invalid_Window_Provided,
	Could_Not_Create_Instance,
	Could_Not_Create_Surface,
	Could_Not_Create_Adapter,
	Could_Not_Create_Device,
	Could_Not_Create_Texture,
	Could_Not_Query_Adapter_Info,
	Could_Not_Query_Device_Info,
	Could_Not_Configure_Surface,
	Required_Adapter_Feature_Not_Present,
}

Renderer_Result :: union #shared_nil {
	runtime.Allocator_Error,
	Renderer_Error,
}

Renderer :: struct {
	core: Renderer_Core,
}

