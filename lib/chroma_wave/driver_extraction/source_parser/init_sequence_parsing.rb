# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class SourceParser
      # Methods for extracting init sequences from C source files.
      #
      # Handles parsing of Init, Init_Fast, and Init_Partial function
      # bodies into encoded byte sequences. Uses {InitParseState} to
      # track command/data accumulation during line-by-line traversal.
      module InitSequenceParsing
        include Opcodes
        include Patterns

        private

        # Extracts all init sequences for the model.
        #
        # @param header_data [Hash] header data
        # @return [Hash] init, fast, and partial sequences
        def extract_all_inits(header_data)
          escaped = Regexp.escape(@prefix)
          {
            init_seq: find_init_sequence(init_patterns, header_data),
            init_fast_seq: extract_init_sequence(/#{escaped}_?Init_Fast/, header_data),
            init_partial_seq: find_init_sequence(partial_init_patterns, header_data)
          }
        end

        # Builds the list of init function patterns for the model.
        #
        # @return [Array<Regexp>]
        def init_patterns
          escaped = Regexp.escape(@prefix)
          patterns = [
            /#{escaped}_Init\b(?!_Fast|_Part|_Partial|_4Gray|_4GRAY|_GUI)/,
            /#{escaped}_?Init\b(?!_Fast|_Part|_Partial|_4Gray|_4GRAY|_GUI)/
          ]
          patterns.unshift(/EPD_3IN7_1Gray_Init/) if @model_name == 'EPD_3in7'
          patterns
        end

        # Builds the list of partial init function patterns.
        #
        # @return [Array<Regexp>]
        def partial_init_patterns
          escaped = Regexp.escape(@prefix)
          [/#{escaped}_?Init_Partial/, /#{escaped}_?Part_Init/, /#{escaped}_?Init_Part/]
        end

        # Finds the first matching init sequence from a list of patterns.
        #
        # @param patterns [Array<Regexp>] patterns to try
        # @param header_data [Hash] header data
        # @return [Array<Integer>, nil]
        def find_init_sequence(patterns, header_data)
          patterns.each do |pat|
            (seq = extract_init_sequence(pat, header_data)) && (return seq)
          end
          nil
        end

        # Parses an Init function body into an encoded init sequence.
        #
        # @param func_pattern [Regexp] function name pattern
        # @param _header_data [Hash] unused, kept for API consistency
        # @return [Array<Integer>, nil] encoded init sequence or nil
        def extract_init_sequence(func_pattern, _header_data)
          init_fn = extract_function_body(@c_content, func_pattern)
          return nil unless init_fn

          state = InitParseState.new
          init_fn.lines.each_with_index do |line, idx|
            stripped = line.strip
            dispatch_init_line(stripped, init_fn.lines[(idx + 1)..], state) unless skip_init_line?(stripped)
          end
          state.finalize
        end

        # Determines whether a line should be skipped during init parsing.
        #
        # @param stripped [String] stripped line content
        # @return [Boolean]
        def skip_init_line?(stripped)
          stripped.empty? || stripped.start_with?('//') ||
            stripped.match?(/^\s*(UWORD|UBYTE|unsigned|static|UDOUBLE|int)\b/) ||
            stripped.match?(/^\s*Debug\b/)
        end

        # Attempts each init-line handler in priority order.
        #
        # @param stripped [String] stripped line text
        # @param remaining [Array<String>] remaining lines
        # @param state [InitParseState] parse state
        # @return [void]
        def dispatch_init_line(stripped, remaining, state)
          emit_sentinel_match(stripped, state) || emit_busy_match(stripped, state) ||
            emit_command_match(stripped, remaining, state) ||
            emit_data_match(stripped, state) || emit_misc_match(stripped, state)
        end

        # Emits a sentinel if the line matches a sentinel pattern.
        #
        # @param stripped [String] stripped line text
        # @param state [InitParseState] parse state
        # @return [Boolean, nil]
        def emit_sentinel_match(stripped, state)
          INIT_SENTINEL_PATTERNS.each do |pattern, sentinel|
            next unless stripped.match?(pattern)

            state.emit_sentinel(sentinel)
            return true
          end
          nil
        end

        # Emits a busy-wait sentinel if the line matches.
        #
        # @param stripped [String] stripped line text
        # @param state [InitParseState] parse state
        # @return [Boolean, nil]
        def emit_busy_match(stripped, state)
          return nil unless stripped.match?(READ_BUSY_RE) && !stripped.match?(SEND_COMMAND_RE)

          state.emit_sentinel(SEQ_WAIT_BUSY)
          true
        end

        # Processes a SendCommand match.
        #
        # @param stripped [String] stripped line text
        # @param remaining [Array<String>] remaining lines
        # @param state [InitParseState] parse state
        # @return [Boolean, nil]
        def emit_command_match(stripped, remaining, state)
          match = stripped.match(SEND_COMMAND_RE)
          return nil unless match

          cmd_byte = Integer(match[1])
          if cmd_byte == 0x12 && sw_reset_context?(remaining)
            state.emit_sentinel(SEQ_SW_RESET)
          else
            state.start_command(cmd_byte)
          end
          true
        end

        # Processes SendData or Delay matches.
        #
        # @param stripped [String] stripped line text
        # @param state [InitParseState] parse state
        # @return [Boolean, nil]
        def emit_data_match(stripped, state)
          if (m = stripped.match(SEND_DATA_RE)) then state.add_data(Integer(m[1]))
          elsif (m = stripped.match(DELAY_RE)) then state.encode_delay(m[1].to_i)
          end
          m ? true : nil
        end

        # Processes LUT calls and SetWindow matches.
        #
        # @param stripped [String] stripped line text
        # @param state [InitParseState] parse state
        # @return [Boolean, nil]
        def emit_misc_match(stripped, state)
          if stripped.match?(LUT_CALL_RE) then state.flush_and_reset
          elsif stripped.match?(/SetWindows|SetWindow/) then state.emit_sentinel(SEQ_SET_WINDOW)
          end
        end

        # Classifies a line as decisive for SW reset context.
        #
        # @param stripped [String] stripped line
        # @return [true, false, nil] true=SWRESET, false=REFRESH, nil=keep looking
        def classify_sw_reset_line(stripped)
          return nil if stripped.empty? || stripped.start_with?('//')
          return true if stripped.match?(/ReadBusy|WaitUntilIdle|BusyHigh/)
          return false if stripped.match?(/SendData|for\s*\(/)

          stripped.match?(/SendCommand/) || nil
        end

        # Determines whether a 0x12 command is a software reset.
        #
        # @param remaining_lines [Array<String>] lines after the current one
        # @return [Boolean]
        def sw_reset_context?(remaining_lines)
          return true if remaining_lines.nil? || remaining_lines.empty?

          remaining_lines.each do |line|
            result = classify_sw_reset_line(line.strip)
            return result unless result.nil?
          end
          true
        end
      end
    end
  end
end
