#!private
package renderer_shader_preprocessor

import "core:os"
import "core:log"
import "core:strings"
import "core:unicode/utf8"

shaderpreprocessor_find_filepath :: proc(
	preprocessor: Shader_Preprocessor,
	include_literal: string,
	current_file: string,
	relative: bool,
	allocator := context.allocator,
) -> (string, bool) {
	if relative {
		if path, ok := shaderpreprocessor_find_filepath_relative(preprocessor, include_literal, current_file, allocator); ok {
			return strings.clone(path), true
		}
		if path, ok := shaderpreprocessor_find_filepath_absolute(preprocessor, include_literal, allocator); ok {
			log.warnf("File path %s is not relative, whilst it should be", include_literal)
			return strings.clone(path), true
		}
	} else {
		if path, ok := shaderpreprocessor_find_filepath_absolute(preprocessor, include_literal, allocator); ok {
			return strings.clone(path), true
		}
		if path, ok := shaderpreprocessor_find_filepath_relative(preprocessor, include_literal, current_file, allocator); ok {
			log.warnf("File path %s is relative, whilst it should not be", include_literal)
			return strings.clone(path), true
		}
	}

	if os.exists(include_literal) && os.is_file(include_literal) {
		log.warnf("File path %s is a global path", include_literal)
		return strings.clone(include_literal), true
	}

	return "", false
}

@(private="file")
shaderpreprocessor_find_filepath_absolute :: proc(
	preprocessor: Shader_Preprocessor,
	include_literal: string,
	allocator := context.allocator,
) -> (string, bool) {
	path_name_first_rune, _ := utf8.decode_rune(include_literal)

	for include_path in preprocessor.include_paths {
		full_path := strings.concatenate([]string {
			include_path,
			"/" if path_name_first_rune != '/' else "",
			include_literal,
		}, allocator)

		if os.exists(full_path) && os.is_file(full_path) {
			return full_path, true
		}

		delete(full_path, allocator)
	}

	return "", false
}

@(private="file")
shaderpreprocessor_find_filepath_relative :: proc(
	preprocessor: Shader_Preprocessor,
	include_literal: string,
	current_file: string,
	allocator := context.allocator,
) -> (string, bool) {
	current_file := current_file
	if os.is_file(current_file) {
		current_file = filepath_strip_file(current_file)
	}

	starting_path_last_rune, _ := utf8.decode_last_rune(current_file)
	path_name_first_rune, _ := utf8.decode_rune(include_literal)

	full_path := strings.concatenate([]string {
		current_file,
		"/" if starting_path_last_rune != '/' && path_name_first_rune != '/' else "",
		include_literal,
	}, allocator)

	if !os.exists(full_path) || !os.is_file(full_path) {
		delete(full_path, allocator)
		return "", false
	}

	return full_path, true
}

@(private="file")
filepath_strip_file :: proc(path: string) -> (result: string) {
	result = path

	i := 0
	for {
		rune, byte_count := utf8.decode_last_rune(result)

		if rune == utf8.RUNE_ERROR || (rune == '/' && i != 0) {
			return
		}

		result = result[:len(result) - byte_count]
		i += 1
	}
}
