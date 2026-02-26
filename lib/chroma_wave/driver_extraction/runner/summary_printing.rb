# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    class Runner
      # Methods for printing the extraction summary report.
      #
      # Outputs total counts, tier2 model details, and warning
      # details after all models have been processed.
      module SummaryPrinting
        private

        # Prints the extraction summary.
        #
        # @param configs [Array<DriverConfig>] extracted configs
        # @param skipped [Array<String>] skipped model names
        # @return [void]
        def print_summary(configs, skipped)
          puts
          print_summary_header(configs, skipped)
          puts
          print_tier2_details(configs)
          print_warning_details(configs)
        end

        # Prints summary header lines.
        #
        # @param configs [Array<DriverConfig>] extracted configs
        # @param skipped [Array<String>] skipped model names
        # @return [void]
        def print_summary_header(configs, skipped)
          puts '=' * 70
          puts 'SUMMARY'
          puts '=' * 70
          puts "Total models extracted: #{configs.length}"
          puts "Skipped: #{skipped.length} (#{skipped.join(', ')})" unless skipped.empty?
          puts "Tier 2 models: #{configs.count(&:tier2_reason)}"
        end

        # Prints Tier 2 model details.
        #
        # @param configs [Array<DriverConfig>] extracted configs
        # @return [void]
        def print_tier2_details(configs)
          tier2 = configs.select(&:tier2_reason)
          return if tier2.empty?

          puts 'Tier 2 models requiring manual overrides:'
          tier2.each { |c| puts "  - #{c.model_name}: #{c.tier2_reason}" }
          puts
        end

        # Prints models with warnings.
        #
        # @param configs [Array<DriverConfig>] extracted configs
        # @return [void]
        def print_warning_details(configs)
          with_warnings = configs.reject { |c| c.warnings.empty? }
          return if with_warnings.empty?

          puts 'Models with warnings:'
          with_warnings.each { |c| puts "  - #{c.model_name}: #{c.warnings.join('; ')}" }
          puts
        end
      end
    end
  end
end
