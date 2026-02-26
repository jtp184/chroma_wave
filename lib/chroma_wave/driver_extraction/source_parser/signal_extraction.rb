# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class SourceParser
      # Methods for extracting hardware signal data from C source files.
      #
      # Handles extraction of reset timing, busy polarity, sleep commands,
      # and display commands from vendor C function bodies.
      module SignalExtraction
        include Opcodes
        include Patterns

        private

        # Extracts all C-level signal data from source content.
        #
        # @return [Hash] reset_ms, busy_pol, display_cmds, sleep_cmd, sleep_data
        def extract_signals
          sleep_cmd, sleep_data = extract_sleep_command
          { reset_ms: extract_reset_timing, busy_pol: extract_busy_polarity,
            display_cmds: extract_display_commands, sleep_cmd:, sleep_data: }
        end

        # Extracts reset timing from the Reset() function.
        #
        # @return [Array<Integer>, nil] [pre_high_ms, low_ms, post_high_ms] or nil
        def extract_reset_timing
          reset_fn = extract_function_body(@c_content, /#{Regexp.escape(@prefix)}_?Reset|EPD_Reset/)
          return nil unless reset_fn

          delays = reset_fn.scan(RESET_DELAY_RE).flatten.map(&:to_i)
          if delays.length >= 3
            timings = collect_reset_delays(reset_fn)
            return timings[0..2] if timings.length >= 3

            delays[0..2]
          elsif delays.length == 2
            [0, delays[0], delays[1]]
          end
        end

        # Extracts delay timings from reset function lines.
        #
        # @param reset_fn [String] reset function body
        # @return [Array<Integer>] all delay values found
        def collect_reset_delays(reset_fn)
          reset_fn.lines.filter_map { |l| l.match(RESET_DELAY_RE)&.[](1)&.to_i }
        end

        # Extracts busy polarity from the ReadBusy/WaitUntilIdle function.
        #
        # @return [Symbol] :active_high, :active_low, :dual, or :unknown
        def extract_busy_polarity
          escaped = Regexp.escape(@prefix)
          has_high = @c_content.match?(/#{escaped}_?BusyHigh|BusyHigh/)
          has_low  = @c_content.match?(/#{escaped}_?BusyLow|BusyLow/)
          return :dual if has_high && has_low

          busy_fn = extract_function_body(@c_content, busy_function_pattern)
          return :unknown unless busy_fn

          classify_busy_polarity(busy_fn)
        end

        # Builds a busy-function pattern from prefix.
        #
        # @return [Regexp]
        def busy_function_pattern
          escaped = Regexp.escape(@prefix)
          parts = ["#{escaped}_?ReadBusy", "#{escaped}_?WaitUntilIdle",
                   'EPD_WaitUntilIdle', "#{escaped}_?ReadBusy_HIGH"]
          Regexp.new(parts.join('|'))
        end

        # Determines busy polarity from the ReadBusy function body.
        #
        # @param busy_fn [String] function body text
        # @return [Symbol] :active_high, :active_low, or :unknown
        def classify_busy_polarity(busy_fn)
          return :active_high if any_pattern_matches?(busy_fn, BUSY_HIGH_PATTERNS)
          return :active_low if any_pattern_matches?(busy_fn, BUSY_LOW_PATTERNS)

          any_pattern_matches?(busy_fn, BUSY_HIGH_LOOP_PATTERNS) ? :active_high : :unknown
        end

        # Checks whether any pattern in the list matches the function body.
        #
        # @param fn_body [String] function body text
        # @param patterns [Array<Regexp>] patterns to check
        # @return [Boolean]
        def any_pattern_matches?(fn_body, patterns)
          patterns.any? { |pat| fn_body.match?(pat) }
        end

        # Extracts sleep command and data from the Sleep() function.
        #
        # @return [Array(Integer, Integer)] [cmd, data]
        def extract_sleep_command
          sleep_fn = extract_function_body(@c_content, /#{Regexp.escape(@prefix)}_?Sleep/)
          return [0x10, 0x01] unless sleep_fn

          cmds = sleep_fn.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
          datas = sleep_fn.scan(SEND_DATA_RE).flatten.map { |v| Integer(v) }
          sleep_uc8179(cmds, datas) || sleep_ssd1680(cmds, datas) || fallback_sleep(cmds, datas)
        end

        # Identifies sleep command pair for UC8179 family (0x07 + 0xA5).
        #
        # @param commands [Array<Integer>] command bytes
        # @param datas [Array<Integer>] data bytes
        # @return [Array(Integer, Integer), nil]
        def sleep_uc8179(commands, datas)
          [0x07, 0xA5] if commands.include?(0x07) && datas.include?(0xA5)
        end

        # Identifies sleep command pair for SSD1680 family (0x10 + data).
        #
        # @param commands [Array<Integer>] command bytes
        # @param datas [Array<Integer>] data bytes
        # @return [Array(Integer, Integer), nil]
        def sleep_ssd1680(commands, datas)
          return nil unless commands.include?(0x10)

          idx = commands.index(0x10)
          [0x10, idx && idx < datas.length ? datas[idx] : 0x01]
        end

        # Fallback sleep detection: last command+data pair or default.
        #
        # @param commands [Array<Integer>] command bytes
        # @param datas [Array<Integer>] data bytes
        # @return [Array(Integer, Integer)]
        def fallback_sleep(commands, datas)
          commands.empty? || datas.empty? ? [0x10, 0x01] : [commands.last, datas.last]
        end

        # Extracts the primary and secondary display command bytes.
        #
        # @return [Array(Integer, Integer)] [primary_cmd, secondary_cmd]
        def extract_display_commands
          pair = first_display_pair
          [pair&.first || 0x24, pair&.last || 0x00]
        end

        # Finds the first matching display command pair from candidate functions.
        #
        # @return [Array(Integer, Integer), nil]
        def first_display_pair
          display_patterns.each do |pattern|
            (pair = try_extract_display_pair(pattern)) && (return pair)
          end
          nil
        end

        # Builds display function patterns in priority order.
        #
        # @return [Array<Regexp>]
        def display_patterns
          escaped = Regexp.escape(@prefix)
          [/#{escaped}_?Display_Base\b/,
           /#{escaped}_?Display[^_P]|#{escaped}_?Display\b/,
           /#{escaped}_?Clear\b/]
        end

        # Attempts to extract primary/secondary display commands from a function.
        #
        # @param pattern [Regexp] function name pattern
        # @return [Array(Integer, Integer), nil]
        def try_extract_display_pair(pattern)
          fn_body = extract_function_body(@c_content, pattern)
          return nil unless fn_body

          cmds = scan_display_data_cmds(fn_body)
          cmds.empty? ? nil : [cmds[0], cmds[1]]
        end

        # Scans a function body for display data command bytes.
        #
        # @param fn_body [String] function body text
        # @return [Array<Integer>] filtered data command bytes
        def scan_display_data_cmds(fn_body)
          fn_body.scan(SEND_COMMAND_RE).flatten
                 .map { |v| Integer(v) }
                 .select { |c| DISPLAY_DATA_CMDS.include?(c) }
        end
      end
    end
  end
end
