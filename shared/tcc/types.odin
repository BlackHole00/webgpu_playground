package tcc

State :: distinct rawptr

Error_Proc :: #type proc "c" (opaque: rawptr, msg: cstring)
Symbol_Proc :: #type proc "c" (ctx: rawptr, name: cstring, val: cstring)

Result :: enum i32 {
	Success = 0,
	Error = -1,
}

Output_Type :: enum i32 {
	Memory = 1,
	Exe = 2,
	Dll = 4,
	Obj = 3,
	Preprocess = 5,
}

Relocate_Auto :: struct {}
Relocate_None :: struct {}
Relocate_Address :: rawptr

Relocate :: union #no_nil {
	Relocate_Auto,
	Relocate_None,
	Relocate_Address,
}
