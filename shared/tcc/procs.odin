package tcc

when ODIN_OS == .Darwin {
	when ODIN_ARCH == .arm64 {
		foreign import lib_tcc "lib/libtcc-darwin-arm64.a"
	} else do #panic("Unsupported architecture")
} else do #panic("Unsupported Os")

@(default_calling_convention="c", link_prefix="tcc_")
foreign lib_tcc {
	new :: proc() -> State ---
	delete :: proc(state: State) ---
	set_lib_path :: proc(state: State, path: cstring) ---
	@(link_name="tcc_set_error_func")
	set_error_proc :: proc(state: State, error_opaque: rawptr, error_func: Error_Proc) ---
	@(link_name="tcc_get_error_func")
	get_error_proc :: proc(state: State) -> Error_Proc ---
	get_error_opaque :: proc(state: State) -> rawptr ---
	set_option :: proc(state: State, str: cstring) -> Result ---

	add_include_path :: proc(state: State, pathname: cstring) -> Result ---
	add_sysinclude_path :: proc(state: State, pathname: cstring) -> Result ---
	define_symbol :: proc(state: State, sym: cstring, value: cstring) ---
	undefine_symbol :: proc(state: State, sym: cstring) ---

	add_file :: proc(state: State, filename: cstring) -> Result ---
	compile_string :: proc(state: State, filename: cstring) -> Result ---

	set_output_type :: proc(state: State, output_type: Output_Type) -> Result ---
	add_library_path :: proc(state: State, pathname: cstring) -> Result ---
	add_library :: proc(state: State, libraryname: cstring) -> Result ---
	add_symbol :: proc(state: State, name: cstring, val: cstring) -> Result ---
	output_file :: proc(state: State, filename: cstring) -> Result ---
	@(link_name="tcc_run")
	run_raw :: proc(state: State, argc: i32, argv: [^]cstring) -> i32 ---
	@(link_name="tcc_relocate")
	relocate_raw :: proc(state: State, ptr: rawptr) -> i32 ---
	get_symbol :: proc(state: State, name: cstring) -> rawptr ---
	list_symbols :: proc(state: State, ctx: rawptr, symbol_callback: Symbol_Proc) ---
}

run :: proc(state: State, args: []cstring) -> i32 {
	return run_raw(state, (i32)(len(args)), raw_data(args))
}

relocate :: proc(state: State, relocate: Relocate) -> i32 {
	switch r in relocate {
	case Relocate_Auto:
		return relocate_raw(state, (rawptr)((uintptr)(1)))
	case Relocate_None:
		return relocate_raw(state, nil)
	case Relocate_Address:
		return relocate_raw(state, r)
	}
	unreachable()
}
