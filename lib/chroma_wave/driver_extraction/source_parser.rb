# frozen_string_literal: true

require 'pathname'
require_relative 'opcodes'
require_relative 'patterns'
require_relative 'driver_config'
require_relative 'source_parser/init_parse_state'
require_relative 'source_parser/function_extraction'
require_relative 'source_parser/init_sequence_parsing'
require_relative 'source_parser/signal_extraction'
require_relative 'source_parser/config_assembly'

module ChromaWave
  module DriverExtraction
    # Parses a single Waveshare vendor .h/.c file pair into a {DriverConfig}.
    #
    # Each instance targets one model. Call {#parse} to extract dimensions,
    # capabilities, busy polarity, reset timing, sleep commands, display
    # commands, init sequences, pixel format, and tier2 classification.
    #
    # @example
    #   parser = SourceParser.new(h_path, c_path)
    #   config = parser.parse  #=> DriverConfig
    class SourceParser
      include Opcodes
      include Patterns
      include FunctionExtraction
      include InitSequenceParsing
      include SignalExtraction
      include ConfigAssembly

      # @param h_path [Pathname] path to the vendor .h file
      # @param c_path [Pathname] path to the vendor .c file
      def initialize(h_path, c_path)
        @h_path = Pathname(h_path)
        @c_path = Pathname(c_path)
      end

      # Parses the vendor source files and returns a {DriverConfig}.
      #
      # @return [DriverConfig]
      def parse
        @model_name = @h_path.basename('.h').to_s
        @h_content = read_vendor_file(@h_path)
        @c_content = read_vendor_file(@c_path)

        header_data = parse_header
        @prefix = header_data[:prefix] || @model_name.upcase.gsub(/[^A-Z0-9]/, '_')

        signals = extract_signals
        inits = extract_all_inits(header_data)

        assemble_config(header_data:, signals:, inits:)
      end

      private

      # Reads a file with safe encoding conversion.
      #
      # @param path [Pathname] file path
      # @return [String] UTF-8 encoded content
      def read_vendor_file(path)
        path.read(encoding: 'ASCII-8BIT')
            .encode('UTF-8', invalid: :replace, undef: :replace)
      end

      # Parses the vendor .h file for dimensions and capabilities.
      #
      # @return [Hash] with :width, :height, :prefix, :capabilities keys
      def parse_header
        dims = extract_dimensions
        { capabilities: detect_capabilities, **dims }
      rescue StandardError => e
        warn "  [WARN] Failed to parse header #{@h_path.basename}: #{e.message}"
        { capabilities: Set.new, width: nil, height: nil, prefix: nil }
      end

      # Extracts WIDTH/HEIGHT definitions from header content.
      #
      # @return [Hash] with :width, :height, :prefix keys
      def extract_dimensions
        result = { width: nil, height: nil, prefix: nil }

        @h_content.scan(WIDTH_HEIGHT_RE) do |name, val|
          result[:width] = val.to_i
          result[:prefix] = name
        end
        @h_content.scan(HEIGHT_RE) do |name, val|
          result[:height] = val.to_i
          result[:prefix] ||= name
        end

        result
      end

      # Detects capabilities from function declarations in header content.
      #
      # @return [Set<Symbol>] detected capabilities
      def detect_capabilities
        Set.new.tap do |caps|
          caps << :fast      if @h_content.match?(/Init_Fast\b/)
          caps << :partial   if @h_content.match?(/Display_Partial|PartialDisplay|DisplayPartial|Part_Init/i)
          caps << :grayscale if @h_content.match?(/4Gray|4grey|4GRAY/i)
          caps << :dual_buf  if @h_content.match?(/Display_Base\b/)
        end
      end
    end
  end
end
