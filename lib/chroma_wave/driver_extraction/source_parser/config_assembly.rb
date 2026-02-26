# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class SourceParser
      # Methods for assembling extracted data into a {DriverConfig}.
      #
      # Handles pixel format detection, tier2 classification, warning
      # collection, and final config construction.
      module ConfigAssembly
        include Opcodes
        include Patterns

        private

        # Detects the pixel format for the model.
        #
        # @return [Symbol] :mono, :color4, or :color7
        def detect_pixel_format
          base = @model_name.sub(/^EPD_/, '')

          return :color7 if base.match?(COLOR7_PATTERN)
          return :color4 if base.match?(GATE_COLOR_PATTERN)
          return :color4 if base.match?(COLOR4_PATTERNS)
          return :color7 if @h_content.match?(/BLACK\s+0x0.*GREEN\s+0x2.*RED\s+0x4/m)

          :mono
        end

        # Detects whether embedded LUT tables exceed a threshold.
        #
        # @return [Boolean]
        def large_luts?
          @c_content.scan(LUT_ARRAY_PATTERN).flatten.any? { |s| s.to_i > 50 }
        rescue StandardError
          false
        end

        # Detects a Tier 2 reason for the model.
        #
        # @return [String, nil]
        def detect_tier2_reason
          TIER2_MODELS[@model_name] ||
            (large_luts? && 'Large embedded LUT tables') ||
            detect_nonstandard_turn_on
        end

        # Detects non-standard TurnOnDisplay sequences.
        #
        # @return [String, nil]
        def detect_nonstandard_turn_on
          turn_on = extract_function_body(@c_content, /#{Regexp.escape(@prefix)}_?TurnOnDisplay\b/)
          return nil unless turn_on

          cmds = turn_on.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
          return nil if cmds.empty? || STANDARD_TURN_ON_SEQUENCES.include?(cmds)

          'Non-standard TurnOnDisplay sequence'
        end

        # Collects extraction warnings for missing data.
        #
        # @param header_data [Hash] parsed header data
        # @param reset_ms [Array, nil] reset timing
        # @param busy_pol [Symbol] busy polarity
        # @param init_seq [Array, nil] init sequence
        # @return [Array<String>]
        def collect_warnings(header_data:, reset_ms:, busy_pol:, init_seq:)
          [].tap do |w|
            w << 'Could not extract WIDTH/HEIGHT' unless header_data[:width] && header_data[:height]
            w << 'Could not extract reset timing' unless reset_ms
            w << 'Could not determine busy polarity' if busy_pol == :unknown
            w << 'Could not extract init sequence' unless init_seq
          end
        end

        # Builds the identity and display fields for {DriverConfig.new}.
        #
        # @param header_data [Hash] parsed header data
        # @param signals [Hash] extracted signal data
        # @param busy [Symbol] resolved busy polarity
        # @return [Hash]
        def config_identity_fields(header_data:, signals:, busy:)
          {
            model_name: @model_name, width: header_data[:width] || 0,
            height: header_data[:height] || 0, pixel_format: detect_pixel_format,
            capabilities: header_data[:capabilities], busy_polarity: busy,
            reset_ms: signals[:reset_ms] || [20, 2, 20],
            display_cmd: signals[:display_cmds][0],
            display_cmd_two: signals[:display_cmds][1]
          }
        end

        # Builds the sequence and metadata fields for {DriverConfig.new}.
        #
        # @param header_data [Hash] parsed header data
        # @param signals [Hash] extracted signal data
        # @param inits [Hash] extracted init sequences
        # @return [Hash]
        def config_sequence_fields(header_data:, signals:, inits:)
          {
            sleep_cmd: signals[:sleep_cmd], sleep_data: signals[:sleep_data],
            init_sequence: inits[:init_seq], init_fast_sequence: inits[:init_fast_seq],
            init_partial_sequence: inits[:init_partial_seq], tier2_reason: detect_tier2_reason,
            warnings: collect_warnings(
              header_data:, reset_ms: signals[:reset_ms],
              busy_pol: signals[:busy_pol], init_seq: inits[:init_seq]
            )
          }
        end

        # Assembles the final DriverConfig from extracted components.
        #
        # @param header_data [Hash] parsed header data
        # @param signals [Hash] extracted signal data
        # @param inits [Hash] extracted init sequences
        # @return [DriverConfig]
        def assemble_config(header_data:, signals:, inits:)
          busy = signals[:busy_pol] == :dual ? :active_low : signals[:busy_pol]
          fields = config_identity_fields(header_data:, signals:, busy:)
                   .merge(config_sequence_fields(header_data:, signals:, inits:))

          DriverConfig.new(**fields)
        end
      end
    end
  end
end
