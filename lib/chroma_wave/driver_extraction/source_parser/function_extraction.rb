# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class SourceParser
      # Helpers for extracting C function bodies from vendor source code.
      #
      # Provides brace-delimited block extraction and function signature
      # matching, shared by {InitSequenceParsing} and {SignalExtraction}.
      module FunctionExtraction
        private

        # Builds a regex to match a C function signature.
        #
        # @param name_pattern [Regexp] function name pattern
        # @return [Regexp]
        def function_signature_pattern(name_pattern)
          /(?:static\s+)?(?:void|UBYTE|int)\s+(#{name_pattern.source})\s*\([^)]*\)\s*\{/m
        end

        # Extracts a brace-delimited block starting at the given index.
        #
        # @param content [String] source text
        # @param start_idx [Integer] index just past the opening brace
        # @return [String] block contents
        def extract_brace_block(content, start_idx)
          depth = 1
          idx = start_idx

          while idx < content.length && depth.positive?
            case content[idx]
            when '{' then depth += 1
            when '}' then depth -= 1
            end
            idx += 1
          end

          content[start_idx...(idx - 1)]
        end

        # Extracts the body of a C function matching the given pattern.
        #
        # @param content [String] full C source
        # @param name_pattern [Regexp] function name pattern to match
        # @return [String, nil] function body text or nil
        def extract_function_body(content, name_pattern)
          match = content.match(function_signature_pattern(name_pattern))
          return nil unless match

          extract_brace_block(content, match.end(0))
        end
      end
    end
  end
end
