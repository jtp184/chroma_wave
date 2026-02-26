# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class HeaderGenerator
      # Methods for emitting the C config table from extracted model data.
      #
      # Generates the +epd_model_configs[]+ struct array with identity,
      # hardware, and init sequence fields for each model.
      module ConfigTableEmitter
        private

        # Emits the config table entries for all models.
        #
        # @return [Array<String>]
        def emit_config_table
          lines = ['/* Model configuration table */', 'static const epd_model_config_t epd_model_configs[] = {']
          @configs.each_with_index do |config, idx|
            lines.concat(emit_config_entry(config, last: idx == @configs.length - 1))
          end
          lines << '};'
          lines
        end

        # Emits the struct entry for a single model in the config table.
        #
        # @param config [DriverConfig] the model config
        # @param last [Boolean] whether this is the last entry
        # @return [Array<String>]
        def emit_config_entry(config, last:)
          tier2 = config.tier2_reason ? " /* TIER2: #{config.tier2_reason} */" : ''
          emit_config_identity(config, tier2) + emit_config_hardware(config) + emit_config_sequence_fields(config, last)
        end

        # Emits the identity fields of a config entry (name, dimensions, format).
        #
        # @param config [DriverConfig] the model config
        # @param tier2_comment [String] tier2 comment or empty string
        # @return [Array<String>]
        def emit_config_identity(config, tier2_comment)
          [
            "    {#{tier2_comment}",
            "        .name = \"#{config.c_name}\",",
            "        .width = #{config.width},",
            "        .height = #{config.height},",
            "        .pixel_format = #{config.c_pixel_format},"
          ]
        end

        # Emits the hardware fields of a config entry (busy, reset, display).
        #
        # @param config [DriverConfig] the model config
        # @return [Array<String>]
        def emit_config_hardware(config)
          reset = config.reset_ms
          [
            "        .busy_polarity = #{config.c_busy_polarity},",
            "        .reset_ms = {#{reset[0]}, #{reset[1]}, #{reset[2]}},",
            "        .display_cmd = #{hex_byte(config.display_cmd)},",
            "        .display_cmd_2 = #{hex_byte(config.display_cmd_two || 0)},"
          ]
        end

        # Emits the sequence and trailing fields of a config entry.
        #
        # @param config [DriverConfig] the model config
        # @param last [Boolean] whether this is the last entry
        # @return [Array<String>]
        def emit_config_sequence_fields(config, last)
          [
            emit_sequence_field(config, :init_sequence, 'init'),
            "        .capabilities = #{config.c_capabilities},",
            emit_sequence_field(config, :init_fast_sequence, 'init_fast'),
            emit_sequence_field(config, :init_partial_sequence, 'init_partial'),
            "        .sleep_cmd = #{hex_byte(config.sleep_cmd)},",
            "        .sleep_data = #{hex_byte(config.sleep_data)}",
            "    }#{',' unless last}"
          ]
        end

        # Emits the .xxx_sequence and .xxx_sequence_len field pair.
        #
        # @param config [DriverConfig] the model config
        # @param field [Symbol] sequence field
        # @param name [String] C field name prefix
        # @return [String]
        def emit_sequence_field(config, field, name)
          seq = config.send(field)
          if seq
            arr = "#{config.c_name}_#{name}"
            "        .#{name}_sequence = #{arr},\n        .#{name}_sequence_len = sizeof(#{arr}),"
          else
            "        .#{name}_sequence = NULL,\n        .#{name}_sequence_len = 0,"
          end
        end
      end
    end
  end
end
