package renderer_shader_preprocessor

Macro_Type :: enum {
	Include,
	Pragma,
	Define,
	Undef,
	If_Def,
	If_NDef,
	User_Defined_Literal,
}

Macro_Pragma_Type :: enum {
	Once,
}

Macro_Symbol :: struct {
	symbol: string,
}

Macro_Define :: struct {
	symbol: string,
	value: string,
}

Macro_Undef :: struct {
	symbol: string,
}

Macro_If_Def :: struct {
	symbol: string,
}

Macro_If_NDef :: struct {
	symbol: string,
}

Macro_Include :: struct {
	path: string,
	relative: bool,
}

Macro_Pragma :: struct {
	type: Macro_Pragma_Type,
}

Macro_Data :: union #no_nil {
	Macro_Include,
	Macro_Pragma,
	Macro_Symbol,
	Macro_Define,
	Macro_Undef,
	Macro_If_Def,
	Macro_If_NDef,
}

Macro :: struct {
	file_path: string,
	file_source: string,
	start_offset: int,
	end_offset: int,
	type: Macro_Type,
	data: Macro_Data,
}

