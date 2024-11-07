package renderer_shader_preprocessor

import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import vmem "core:mem/virtual"
import "core:text/scanner"
import "shared:utils"

Common_Error :: enum {
	Path_Error,
	Os_Error,
	Incomplete_Macro,
	Unknown_Macro,
	Unknown_Pragma,
	Malformed_Inclusion,
	Malformed_Define,
	Include_Not_Found,
	Unimplemented_Macro,
}

Error :: union #shared_nil {
	Common_Error,
	runtime.Allocator_Error,
}

Preprocess_Options :: struct {
	allow_namespaces: bool,
}
DEFAULT_PREPROCESS_OPTIONS :: Preprocess_Options {
	allow_namespaces = true,
}

Shader_Preprocessor :: struct {
	allocator: runtime.Allocator,
	arena: vmem.Arena,

	target_file: string,

	include_paths: [dynamic]string,
	literal_symbols: map[string]string,
	function_symbols: map[string]struct {}, // TODO
	inclusions: map[string]Inclusion_Info,
}

create :: proc(preprocessor: ^Shader_Preprocessor, allocator := context.allocator) -> Error {
	preprocessor.allocator = allocator
	if err := vmem.arena_init_growing(&preprocessor.arena); err != .None {
		log.errorf("Could not initialize the preprocessor: Could not create an arena")
		return err
	}

	preprocessor.include_paths = make([dynamic]string, allocator) or_return
	preprocessor.literal_symbols = make(map[string]string, allocator = allocator) or_return
	preprocessor.inclusions = make(map[string]Inclusion_Info, allocator = allocator) or_return

	return nil
}

destroy :: proc(preprocessor: ^Shader_Preprocessor) {
	vmem.arena_destroy(&preprocessor.arena)

	for path in preprocessor.include_paths {
		delete(path, preprocessor.allocator)
	}
	for _, symbol in preprocessor.literal_symbols {
		delete(symbol, preprocessor.allocator)
	}

	delete(preprocessor.include_paths)
	delete(preprocessor.literal_symbols)
	delete(preprocessor.inclusions)
}

add_include_path :: proc(preprocessor: ^Shader_Preprocessor, path: string) -> Error {
	if !os.is_dir(path) {
		log.errorf(
			"Could not add the path `%s` to the preprocessor's include paths: The provided path is not a directory",
			path,
		)
		return .Path_Error
	}

	fullpath, fullpath_ok := utils.path_as_fullpath(path, preprocessor.allocator)
	if !fullpath_ok {
		log.errorf(
			"Could not add the path `%s` to the preprocessor's include paths: Could not obtain the fullpath of the" +
			"provided path",
			path,
		)
		return .Os_Error
	}

	append(&preprocessor.include_paths, fullpath) or_return

	return nil
}

define_literal_symbol :: proc(
	preprocessor: ^Shader_Preprocessor,
	symbol: string,
	value: string,
) -> Error {
	if old_symbol, has_old_symbol := preprocessor.literal_symbols[symbol]; has_old_symbol {
		delete(old_symbol, preprocessor.allocator)
	}

	value_copy := strings.clone(value, preprocessor.allocator) or_return
	preprocessor.literal_symbols[symbol] = value_copy

	return nil
}

preprocess :: proc(
	preprocessor: ^Shader_Preprocessor,
	file: string,
	preprocess_options := DEFAULT_PREPROCESS_OPTIONS,
	allocator := context.allocator,
) -> (result: string, err: Error) {
	if !os.is_file(file) {
		log.errorf("Could not preprocess file `%s`: The provided path does not point to a file", file)
		return "", .Path_Error
	}

	arena_temp := vmem.arena_temp_begin(&preprocessor.arena)
	defer vmem.arena_temp_end(arena_temp)

	fullpath, fullpath_ok := utils.path_as_fullpath(file, shaderpreprocessor_temp_allocator(preprocessor))
	if !fullpath_ok {
		log.errorf("Could not preprocess file `%s`: Could not obtain its fullpath", file)
		return "", .Os_Error
	}
	preprocessor.target_file = fullpath

	preprocess, preprocess_res := shaderpreprocessor_preprocess_as_inclusion(preprocessor, fullpath, preprocess_options)
	if preprocess_res != nil {
		return "", preprocess_res
	}

	result = strings.clone(preprocess, allocator) or_return
	return result, nil
}

@(private)
Inclusion_Info :: struct {
	inclusion_count: uint,
	include_once: bool,
}

// NOTE(Vicix): shaderpreprocessor_preprocess_as_inclusion assumes the fullpath is a valid file path and an actual fullpath
@(private)
shaderpreprocessor_preprocess_as_inclusion :: proc(
	preprocessor: ^Shader_Preprocessor,
	fullpath: string,
	preprocess_options: Preprocess_Options,
) -> (string, Error) {
	file_contents, file_contents_ok := os.read_entire_file(fullpath, shaderpreprocessor_temp_allocator(preprocessor))
	if !file_contents_ok {
		log.errorf("Could not preprocess file `%s`: Could not open the provided filepath", fullpath)
		return "", .Os_Error
	}

	scn: scanner.Scanner
	scanner.init(&scn, (string)(file_contents), fullpath)
	// scn.flags = scanner.C_Like_Tokens
	scn.flags = scanner.Scan_Flags{.Scan_Idents, .Scan_Comments, .Skip_Comments}
	scn.whitespace = scanner.Whitespace{'\t', '\r', '\v', '\f', ' '}

	source := (string)(file_contents)
	for scanner.scan(&scn) != scanner.EOF {
		token := scanner.token_text(&scn)
		if !shaderpreprocessor_is_token_a_macro(preprocessor^, token) {
			continue
		}

		macro, macro_err := shaderpreprocessor_parse_macro(preprocessor, &scn)
		if macro_err != nil {
			log.errorf("Could not preprocess file `%s`: Got error %v", fullpath, macro_err)
			return "", macro_err
		}

		if new_source, resolution_err := shaderpreprocessor_resolve_macro(
			preprocessor, 
			macro,
			&scn,
			preprocess_options,
		); resolution_err != nil {
			log.errorf("Could not preprocess file `%s`: Got error %v", fullpath, resolution_err)
			return source, resolution_err
		} else {
			source = new_source
		}
	}

	if preprocess_options.allow_namespaces {
		source, _ = strings.replace_all(source, "::", "__", shaderpreprocessor_temp_allocator(preprocessor))
	}

	return source, nil
}

@(private)
shaderpreprocessor_temp_allocator :: proc(preprocessor: ^Shader_Preprocessor) -> runtime.Allocator {
	return vmem.arena_allocator(&preprocessor.arena)
}

