# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class Runner
      # Methods for formatting per-model extraction status output.
      #
      # Builds human-readable status lines showing dimensions, pixel
      # format, busy polarity, capabilities, and init sequence sizes.
      module StatusFormatting
        private

        # Formats a status line for a successfully extracted config.
        #
        # @param config [DriverConfig] the model config
        # @return [String]
        def format_config_status(config)
          parts = core_status_parts(config) + init_status_parts(config)
          warns = config.warnings.empty? ? '' : " [WARN: #{config.warnings.join('; ')}]"
          parts.join(' ') + warns
        end

        # Builds the core status parts for a config.
        #
        # @param config [DriverConfig] the model config
        # @return [Array<String>]
        def core_status_parts(config)
          [
            "#{config.width}x#{config.height}",
            config.pixel_format.to_s,
            "busy:#{config.busy_polarity}",
            "caps:[#{config.capabilities.to_a.join(',')}]"
          ]
        end

        # Builds the optional status parts for init sequences.
        #
        # @param config [DriverConfig] the model config
        # @return [Array<String>]
        def init_status_parts(config)
          parts = []
          parts << 'TIER2' if config.tier2_reason
          parts << seq_status('init', config.init_sequence)
          parts << seq_status('fast', config.init_fast_sequence) if config.init_fast_sequence
          parts << seq_status('partial', config.init_partial_sequence) if config.init_partial_sequence
          parts
        end

        # Formats a sequence length status string.
        #
        # @param label [String] label prefix
        # @param sequence [Array, nil] the sequence
        # @return [String]
        def seq_status(label, sequence)
          "#{label}:#{sequence&.length || 0}B"
        end
      end
    end
  end
end
