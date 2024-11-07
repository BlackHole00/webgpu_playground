#!private
package renderer_shader_preprocessor

import "core:log"
import "core:strings"
import "core:text/scanner"
import "shared:utils"

shaderpreprocessor_resolve_macro :: proc(
	preprocessor: ^Shader_Preprocessor,
	macro: Macro,
	scn: ^scanner.Scanner,
	preproces_options: Preprocess_Options,
) -> (string, Error) {
	#partial switch data in macro.data {
	case Macro_Symbol:
		symbol_literal, literal_ok := preprocessor.literal_symbols[data.symbol]
		assert(
			literal_ok,
			"The literal found in the macro is not a registered literal. This is a bug in the preprocessor",
		)

		new_source := strings.concatenate([]string {
			macro.file_source[:macro.start_offset],
			symbol_literal,
			macro.file_source[macro.end_offset:],
		}, shaderpreprocessor_temp_allocator(preprocessor))

		scn.src = new_source
		scn.src_pos = macro.start_offset
		scn.tok_pos = macro.start_offset

		return new_source, nil

	case Macro_Define:
		define_literal_symbol(preprocessor, data.symbol, data.value)

		new_source := strings.concatenate([]string {
			macro.file_source[:macro.start_offset],
			macro.file_source[macro.end_offset:],
		}, shaderpreprocessor_temp_allocator(preprocessor))

		scn.src = new_source
		scn.src_pos = macro.start_offset
		scn.tok_pos = macro.start_offset

		return new_source, nil

	case Macro_Include:
		filepath, filepath_ok := shaderpreprocessor_find_filepath(
			preprocessor^,
			data.path,
			macro.file_path,
			data.relative,
			shaderpreprocessor_temp_allocator(preprocessor),
		)
		if !filepath_ok {
			log.errorf("Could not preprocess file %s: Could not find inclusion file %s", macro.file_path, data.path)
			return "", .Include_Not_Found
		}

		fullpath, fullpath_ok := utils.path_as_fullpath(filepath, shaderpreprocessor_temp_allocator(preprocessor))
		if !fullpath_ok {
			log.errorf(
				"Could not preprocess file %s: Could not find the fullpath of file %s",
				macro.file_path,
				filepath,
			)
			return "", .Os_Error
		}

		inclusion_data := preprocessor.inclusions[fullpath]
		if inclusion_data.include_once && inclusion_data.inclusion_count >= 1 {
			new_source := strings.concatenate([]string {
				macro.file_source[:macro.start_offset],
				macro.file_source[macro.end_offset:],
			}, shaderpreprocessor_temp_allocator(preprocessor))

			scn.src = new_source
			scn.src_pos = macro.start_offset
			scn.tok_pos = macro.start_offset

			return new_source, nil
		}

		inclusion_data.inclusion_count += 1
		preprocessor.inclusions[fullpath] = inclusion_data

		preprocessed_source, preprocess_res := shaderpreprocessor_preprocess_as_inclusion(
			preprocessor,
			fullpath,
			preproces_options,
		)
		if preprocess_res != nil {
			log.errorf("Could not preprocess included file %s: Got error %v", fullpath, preprocess_res)
			return "", preprocess_res
		}

		new_source := strings.concatenate([]string {
			macro.file_source[:macro.start_offset],
			preprocessed_source,
			macro.file_source[macro.end_offset:],
		}, shaderpreprocessor_temp_allocator(preprocessor))

		scn.src = new_source
		scn.src_pos = macro.start_offset
		scn.tok_pos = macro.start_offset

		return new_source, nil

	case Macro_Pragma:
		inclusion_data := preprocessor.inclusions[macro.file_path]
		inclusion_data.include_once = true
		preprocessor.inclusions[macro.file_path] = inclusion_data

		new_source := strings.concatenate([]string {
			macro.file_source[:macro.start_offset],
			macro.file_source[macro.end_offset:],
		}, shaderpreprocessor_temp_allocator(preprocessor))

		scn.src = new_source
		scn.src_pos = macro.start_offset
		scn.tok_pos = macro.start_offset

		return new_source, nil

	case Macro_Undef:
		delete_key(&preprocessor.literal_symbols, data.symbol)

	case:
		unimplemented()
	}

	return "", nil
}
