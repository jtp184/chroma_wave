# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class SourceParser
      # State container for init sequence parsing.
      #
      # Tracks the current command, accumulated data bytes, and the
      # overall encoded sequence. Used exclusively by {SourceParser}
      # during init function body traversal.
      class InitParseState
        include Opcodes

        # @return [Array<Integer>] the accumulated encoded byte sequence
        attr_reader :sequence

        def initialize
          @sequence = []
          @current_cmd = nil
          @current_data = []
        end

        # Flushes pending command then resets current state.
        # @return [void]
        def flush_and_reset
          flush_command
          @current_cmd = nil
          @current_data = []
        end

        # Appends a sentinel, flushing pending command first.
        # @param sentinel [Integer] sentinel opcode
        # @return [void]
        def emit_sentinel(sentinel)
          flush_and_reset
          @sequence << sentinel
        end

        # Sets the current command byte.
        # @param cmd_byte [Integer] command byte
        # @return [void]
        def start_command(cmd_byte)
          flush_command
          @current_cmd = cmd_byte
          @current_data = []
        end

        # Appends a data byte to the current command.
        # @param byte [Integer] data byte
        # @return [void]
        def add_data(byte)
          @current_data << byte if @current_cmd
        end

        # Encodes a delay value into the sequence.
        # @param delay [Integer] delay in milliseconds
        # @return [void]
        def encode_delay(delay)
          flush_and_reset
          emit_delay_bytes(delay)
        end

        # Finalizes the sequence by flushing and appending SEQ_END.
        # @return [Array<Integer>, nil] the final sequence or nil
        def finalize
          flush_command
          @sequence << SEQ_END
          @sequence == [SEQ_END] ? nil : @sequence
        end

        private

        # @return [void]
        def flush_command
          return unless @current_cmd

          @sequence << @current_cmd
          @sequence << @current_data.length
          @sequence.concat(@current_data)
          @current_cmd = nil
          @current_data = []
        end

        # @param delay [Integer] delay in milliseconds
        # @return [void]
        def emit_delay_bytes(delay)
          return unless delay.positive?

          (delay / 255).times { @sequence.push(SEQ_DELAY_MS, 255) }
          remainder = delay % 255
          @sequence.push(SEQ_DELAY_MS, remainder) if remainder.positive?
        end
      end
    end
  end
end
