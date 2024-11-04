#!private
package renderer_shader_preprocessor

import "core:log"
import "core:text/scanner"

token_to_macro_type :: proc(token: string) -> (Macro_Type, bool) {
	switch token {
	case "include": return .Include, true
	case "pragma": return .Pragma, true
	case "define": return .Define, true
	case "undef": return .Undef, true
	case: return {}, false
	}
}

token_to_pragma_type :: proc(token: string) -> (Macro_Pragma_Type, bool) {
	switch token {
	case "once": return .Once, true
	case: return {}, false
	}
}

shaderpreprocessor_is_token_a_macro :: proc(preprocessor: Shader_Preprocessor, token: string) -> bool {
	return token == "#" || shaderpreprocessor_is_token_a_symbol(preprocessor, token)
}

shaderpreprocessor_is_token_a_symbol :: proc(preprocessor: Shader_Preprocessor, token: string) -> bool {
	_, is_symbol := preprocessor.literal_symbols[token]
	return is_symbol
}


shaderpreprocessor_parse_macro :: proc(preprocessor: ^Shader_Preprocessor, scn: ^scanner.Scanner) -> (Macro, Error) {
	current_token := scanner.token_text(scn)
	starting_position := scanner.position(scn)
	filename := starting_position.filename

	switch {
	case shaderpreprocessor_is_token_a_symbol(preprocessor^, current_token):
		macro := Macro {
			file_path = filename,
			file_source = scn.src,
			start_offset = scn.tok_pos,
			end_offset = scn.tok_end,
			type = .User_Defined_Literal,
			data = Macro_Symbol {
				symbol = current_token,
			},
		}
		return macro, nil

	case current_token == "#":
		if scanner.scan(scn) == scanner.EOF {
			handle_eof(starting_position, scn)
			return {}, .Incomplete_Macro
		}

		current_token = scanner.token_text(scn)
		current_position := scanner.position(scn)

		macro_type, is_valid_macro_type := token_to_macro_type(current_token)
		if !is_valid_macro_type {
			log.errorf(
				"Could not preprocess the file `%s`: Unknown macro directive `#%s` found at %d:%d",
				filename,
				current_token,
				current_position.line,
				current_position.column,
			)
			return {}, .Unknown_Macro
		}

		switch macro_type {
		case .Include:
			if scanner.scan(scn) == scanner.EOF {
				handle_eof(starting_position, scn)
				return {}, .Incomplete_Macro
			}

			current_token = scanner.token_text(scn)
			current_position = scanner.position(scn)

			is_relative_include := false

			switch current_token {
			case "<": is_relative_include = false
			case "\"": is_relative_include = true
			case: 
				log.errorf(
					"Could not preprocess the file `%s`: Invalid include token at %d:%d. Expected `<` or `\"`, found " +
					"`%s`",
					filename,
					current_position.line,
					current_position.column,
					current_token,
				)
				return {}, .Malformed_Inclusion
			}

			inclusion_start_offset := current_position.offset
			inclusion_end_offset := 0

			include_path_parsing: for {
				if scanner.scan(scn) == scanner.EOF {
					handle_eof(starting_position, scn)
					return {}, .Incomplete_Macro
				}

				current_token = scanner.token_text(scn)
				current_position = scanner.position(scn)

				switch current_token {
				case ">":
					if is_relative_include {
						log.errorf(
							"Could not preprocess the file `%s`: Invalid closing include token. Expected `\"`, found " +
							"`>`",
							filename,
						)
						return {}, .Malformed_Inclusion
					}
					break include_path_parsing
				case "\"":
					if !is_relative_include {
						log.errorf(
							"Could not preprocess the file `%s`: Invalid closing include token. Expected `>`, found " +
							"`\"`",
							filename,
						)
						return {}, .Malformed_Inclusion
					}
					break include_path_parsing
				}

				inclusion_end_offset = current_position.offset
			}

			include_path := scn.src[inclusion_start_offset:inclusion_end_offset]

			macro := Macro {
				file_path = filename,
				file_source = scn.src,
				start_offset = starting_position.offset - 1,
				end_offset = scn.tok_end,
				type = .Include,
				data = Macro_Include {
					path = include_path,
					relative = is_relative_include,
				},
			}
			return macro, nil

		case .Define:
			if scanner.scan(scn) == scanner.EOF {
				handle_eof(starting_position, scn)
				return {}, .Incomplete_Macro
			}
			current_position = scanner.position(scn)

			symbol_literal := scanner.token_text(scn)
			symbol_value_begin_offset := current_position.offset + 1
			symbol_value_end_offset := 0

			if scanner.scan(scn) == scanner.EOF {
				handle_eof(starting_position, scn)
				return {}, .Incomplete_Macro
			}
			current_token = scanner.token_text(scn)

			if current_token == "(" {
				log.errorf(
					"Could not preprocess the file `%s`: Invalid symbol definition at %d:%d. Function like macros " +
					"are not yet supported",
					filename,
					current_position.line,
					current_position.column,
				)
				return {}, .Malformed_Define
			}

			for {
				if scanner.scan(scn) == scanner.EOF {
					handle_eof(starting_position, scn)
					return {}, .Incomplete_Macro
				}
				current_position = scanner.position(scn)
				current_token = scanner.token_text(scn)

				if current_token == "\n" {
					symbol_value_end_offset = current_position.offset - 1
					break
				}
			}

			symbol_value := scn.src[symbol_value_begin_offset:symbol_value_end_offset]

			macro := Macro {
				file_path = filename,
				file_source = scn.src,
				start_offset = starting_position.offset - 1,
				end_offset = scn.tok_end - 1,
				type = .Define,
				data = Macro_Define {
					symbol = symbol_literal,
					value = symbol_value,
				},
			}
			return macro, nil

		case .Undef:
			if scanner.scan(scn) == scanner.EOF {
				handle_eof(starting_position, scn)
				return {}, .Incomplete_Macro
			}
			symbol_literal := scanner.token_text(scn)

			macro := Macro {
				file_path = filename,
				file_source = scn.src,
				start_offset = starting_position.offset - 1,
				end_offset = scn.tok_end - 1,
				type = .Undef,
				data = Macro_Undef {
					symbol = symbol_literal,
				},
			}
			return macro, nil

		case .Pragma:
			if scanner.scan(scn) == scanner.EOF {
				handle_eof(starting_position, scn)
				return {}, .Incomplete_Macro
			}

			current_token = scanner.token_text(scn)
			current_position = scanner.position(scn)

			pragma_type, is_valid_pragma_type := token_to_pragma_type(current_token)
			if !is_valid_pragma_type {
				log.errorf(
					"Could not preprocess the file `%s`: Unknown pragma directive (found `#pragma %s`) at %d:%d",
					filename,
					current_token,
					current_position.line,
					current_position.column,
				)
				return {}, .Unknown_Pragma
			}

			switch pragma_type {
			case .Once:
				macro := Macro {
					file_path = filename,
					file_source = scn.src,
					start_offset = starting_position.offset - 1,
					end_offset = scn.tok_end,
					type = .User_Defined_Literal,
					data = Macro_Pragma {
						type = .Once,
					},
				}
				return macro, nil
			}

		case .If_Def, .If_NDef:
			log.errorf(
				"Could not preprocess the file `%s`: The macro `%v` at %d:%d is not yet supported",
				current_position.filename,
				current_token,
				current_position.line,
				current_position.column,
			)
			return {}, .Unimplemented_Macro

		case .User_Defined_Literal: fallthrough
		case: unreachable()
		}

		return {}, nil

	case:
		panic(
			"The macro we are currently parsing is neither the macro starter (#) nor a user defined symbol. This is " +
			"a bug in the preprocessor.",
		)
	}
}

handle_eof :: proc (macro_initial_position: scanner.Position, scn: ^scanner.Scanner) {
	log.errorf(
		"Could not preprocess source %s: The macro invocation at %d:%d is not complete. Reached EOF",
		macro_initial_position.filename,
		macro_initial_position.line,
		macro_initial_position.column,
	)
	log.debugf(
		"Macro failed with source: %s",
		scn.src[macro_initial_position.offset:],
	)
}
