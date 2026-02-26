# frozen_string_literal: true

require 'pathname'
require_relative 'source_parser'
require_relative 'header_generator'
require_relative 'runner/status_formatting'
require_relative 'runner/summary_printing'

module ChromaWave
  module DriverExtraction
    # Orchestrates driver config extraction from vendor sources.
    #
    # Discovers vendor .h/.c pairs, parses each into a {DriverConfig},
    # generates the C header, writes it to disk, and prints a summary.
    #
    # @example Default invocation
    #   Runner.new.call
    #
    # @example Custom paths (useful for testing)
    #   Runner.new(vendor_dir: Pathname('fixtures/vendor'), output_path: tmp_path).call
    class Runner
      include StatusFormatting
      include SummaryPrinting

      # Default vendor source directory.
      DEFAULT_VENDOR_DIR = Pathname.new(__dir__).join(
        '..', '..', '..', 'vendor', 'waveshare_epd', 'lib', 'e-Paper'
      ).expand_path

      # Default output path for the generated header.
      DEFAULT_OUTPUT_PATH = Pathname.new(__dir__).join(
        '..', '..', '..', 'ext', 'chroma_wave', 'driver_configs_generated.h'
      ).expand_path

      # @param vendor_dir [Pathname, String] path to vendor source directory
      # @param output_path [Pathname, String] path for generated C header
      def initialize(vendor_dir: DEFAULT_VENDOR_DIR, output_path: DEFAULT_OUTPUT_PATH)
        @vendor_dir = Pathname(vendor_dir)
        @output_path = Pathname(output_path)
      end

      # Runs the full extraction pipeline.
      #
      # @return [void]
      def call
        print_header
        headers = discover_headers
        skipped = []
        configs = headers.filter_map { |h| process_model(h, skipped) }
        print_summary(configs, skipped)
        write_output(configs)
      end

      private

      # Prints the extraction header banner.
      #
      # @return [void]
      def print_header
        puts "Extracting driver configs from #{@vendor_dir}"
        puts "Output: #{@output_path}"
        puts
      end

      # Discovers and sorts vendor header files.
      #
      # @return [Array<Pathname>] sorted header paths
      def discover_headers
        headers = @vendor_dir.glob('EPD_*.h').sort_by(&:basename)
        puts "Found #{headers.length} header files"
        puts
        headers
      end

      # Processes a single header file and returns the config or nil.
      #
      # @param h_path [Pathname] header file path
      # @param skipped [Array<String>] accumulator for skipped model names
      # @return [DriverConfig, nil]
      def process_model(h_path, skipped)
        model_name = h_path.basename('.h').to_s
        c_path = h_path.sub_ext('.c')

        return skip_model(model_name, 'no matching .c file', skipped) unless c_path.exist?

        print "  #{model_name}... "
        config = SourceParser.new(h_path, c_path).parse

        return skip_model(nil, 'SKIP (no dimensions)', skipped, model_name) if config.width.zero? || config.height.zero?

        puts format_config_status(config)
        config
      end

      # Records a skipped model and prints a message.
      #
      # @param label [String, nil] label for the skip message
      # @param reason [String] skip reason
      # @param skipped [Array<String>] accumulator
      # @param name [String] model name to add to skipped list
      # @return [nil]
      def skip_model(label, reason, skipped, name = label)
        if label
          puts "  [SKIP] #{label}: #{reason}"
        else
          puts reason
        end
        skipped << name
        nil
      end

      # Writes the generated header and prints a confirmation.
      #
      # @param configs [Array<DriverConfig>] extracted configs
      # @return [void]
      def write_output(configs)
        header_content = HeaderGenerator.new(configs).generate
        @output_path.dirname.mkpath
        @output_path.write(header_content)
        puts "Generated #{@output_path} (#{header_content.length} bytes, #{configs.length} models)"
      end
    end
  end
end
