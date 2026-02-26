# frozen_string_literal: true

require_relative 'opcodes'

module ChromaWave
  module DriverExtraction
    # Represents a single extracted driver model configuration.
    #
    # Holds all parsed data for one Waveshare E-Paper model and provides
    # helper methods for generating C-safe identifiers and enum names.
    DriverConfig = Struct.new(
      :model_name,
      :width,
      :height,
      :pixel_format,
      :busy_polarity,
      :reset_ms,
      :display_cmd,
      :display_cmd_two,
      :sleep_cmd,
      :sleep_data,
      :capabilities,
      :init_sequence,
      :init_fast_sequence,
      :init_partial_sequence,
      :tier2_reason,
      :warnings,
      keyword_init: true
    ) do
      # @return [String] C-safe identifier (lowercase, underscored)
      def c_name
        model_name.downcase
      end

      # @return [String] C pixel format enum name
      def c_pixel_format
        Opcodes::PIXEL_FORMAT_NAMES.fetch(pixel_format, 'PIXEL_FORMAT_MONO')
      end

      # @return [String] C busy polarity enum name
      def c_busy_polarity
        Opcodes::BUSY_POLARITY_NAMES.fetch(busy_polarity, 'BUSY_ACTIVE_HIGH')
      end

      # @return [String] C capabilities expression (pipe-separated flags or "0")
      def c_capabilities
        caps = Opcodes::CAPABILITY_NAMES.filter_map { |sym, name| name if capabilities.include?(sym) }
        caps.empty? ? '0' : caps.join(' | ')
      end
    end
  end
end
