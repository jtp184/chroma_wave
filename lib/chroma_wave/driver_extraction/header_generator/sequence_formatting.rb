# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class HeaderGenerator
      # Methods for formatting init sequences as C array initializers.
      #
      # Handles encoding of sentinel opcodes, command+data entries,
      # and delay values into formatted C source lines.
      module SequenceFormatting
        include Opcodes

        private

        # Generates the C array initializer for an init sequence.
        #
        # @param sequence [Array<Integer>] encoded byte sequence
        # @param indent [String] indentation prefix
        # @return [String] C array content
        def format_init_sequence(sequence, indent = '    ')
          return '' if sequence.nil? || sequence.empty?

          lines = []
          i = 0
          while i < sequence.length
            line, i = format_one_entry(sequence, i, indent)
            lines << line
          end
          lines.join("\n")
        end

        # Formats a single entry (sentinel or command) from a sequence.
        #
        # @param sequence [Array<Integer>] encoded byte sequence
        # @param index [Integer] current index
        # @param indent [String] indentation prefix
        # @return [Array(String, Integer)] [formatted_line, new_index]
        def format_one_entry(sequence, index, indent)
          if SENTINEL_NAMES.key?(sequence[index])
            format_sentinel(sequence, index, indent)
          else
            format_command_entry(sequence, index, indent)
          end
        end

        # Formats a sentinel opcode and its optional delay argument.
        #
        # @param sequence [Array<Integer>] encoded byte sequence
        # @param index [Integer] current index
        # @param indent [String] indentation prefix
        # @return [Array(String, Integer)] [formatted_line, new_index]
        def format_sentinel(sequence, index, indent)
          byte = sequence[index]
          name = SENTINEL_NAMES[byte]

          if byte == SEQ_DELAY_MS && index + 1 < sequence.length
            ["#{indent}#{name}, #{sequence[index + 1]},", index + 2]
          else
            ["#{indent}#{name},", index + 1]
          end
        end

        # Formats a command with no data or an invalid count.
        #
        # @param cmd [Integer] command byte
        # @param index [Integer] current index
        # @param indent [String] indentation prefix
        # @return [Array(String, Integer)] [formatted_line, new_index]
        def format_bare_command(cmd, index, indent)
          ["#{indent}#{hex_byte(cmd)}, 0,", index + 1]
        end

        # Formats a command byte with its count and data payload.
        #
        # @param sequence [Array<Integer>] encoded byte sequence
        # @param index [Integer] current index
        # @param indent [String] indentation prefix
        # @return [Array(String, Integer)] [formatted_line, new_index]
        def format_command_entry(sequence, index, indent)
          cmd = sequence[index]
          return format_bare_command(cmd, index, indent) unless index + 1 < sequence.length

          count = sequence[index + 1]
          return format_bare_command(cmd, index, indent) unless count >= 0 && count < 0xF0

          data_bytes = sequence[index + 2, count] || []
          [format_data_line(cmd, count, data_bytes, indent), index + 2 + count]
        end

        # Builds the formatted line for a command with data.
        #
        # @param cmd [Integer] command byte
        # @param count [Integer] data count
        # @param data_bytes [Array<Integer>] data payload
        # @param indent [String] indentation prefix
        # @return [String]
        def format_data_line(cmd, count, data_bytes, indent)
          return "#{indent}#{hex_byte(cmd)}, 0," if data_bytes.empty?

          data_str = data_bytes.map { |b| hex_byte(b) }.join(', ')
          "#{indent}#{hex_byte(cmd)}, #{count}, #{data_str},"
        end

        # Formats a hex byte for C output.
        #
        # @param value [Integer] byte value
        # @return [String]
        def hex_byte(value)
          format('0x%02X', value)
        end
      end
    end
  end
end
