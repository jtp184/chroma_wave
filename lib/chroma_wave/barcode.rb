# frozen_string_literal: true

module ChromaWave
  # Standalone barcode utilities.
  #
  # Provides measurement helpers and barcode construction that don't
  # require a drawing surface, so callers can compute pixel dimensions
  # for centering or layout before committing to a +draw_barcode+ call.
  #
  # @example
  #   metrics = ChromaWave::Barcode.measure("ABC123", symbology: :code128)
  #   metrics.width  # => total pixel width of the rendered barcode
  #   metrics.height # => total pixel height (bars only, unless include_text)
  module Barcode
    # Maps user-facing symbology symbols to their Barby class name and require path.
    #
    # @return [Hash{Symbol => Hash}]
    SYMBOLOGIES = {
      code128: { class_name: 'Barby::Code128', require_path: 'barby/barcode/code_128' },
      ean13: { class_name: 'Barby::EAN13', require_path: 'barby/barcode/ean_13' },
      ean8: { class_name: 'Barby::EAN8', require_path: 'barby/barcode/ean_8' },
      code39: { class_name: 'Barby::Code39', require_path: 'barby/barcode/code_39' }
    }.freeze

    # Pixel dimensions and encoding length for a barcode.
    #
    # @!attribute [r] width
    #   @return [Integer] total width in pixels
    # @!attribute [r] height
    #   @return [Integer] total height in pixels
    # @!attribute [r] encoding_length
    #   @return [Integer] number of modules in the binary encoding
    Metrics = Data.define(:width, :height, :encoding_length)

    # Builds a Barby barcode instance for the given symbology and data.
    #
    # @param symbology [Symbol] symbology key (e.g. +:code128+, +:ean13+)
    # @param data [String] data to encode
    # @return [Barby::Barcode] the barcode instance
    # @raise [ArgumentError] if symbology is unknown or data is invalid for the symbology
    # @raise [DependencyError] if barby is not installed
    def self.build_barcode(symbology, data)
      require_barby!
      spec = SYMBOLOGIES.fetch(symbology) do
        raise ArgumentError, "unknown symbology: #{symbology.inspect} " \
                             "(expected #{SYMBOLOGIES.keys.map(&:inspect).join(', ')})"
      end

      require spec[:require_path]
      begin
        Object.const_get(spec[:class_name]).new(data)
      rescue ArgumentError => e
        raise ArgumentError, "invalid data for #{symbology}: #{e.message}"
      end
    end

    # Lazily requires barby, raising DependencyError if not installed.
    #
    # @raise [DependencyError] if barby cannot be loaded
    def self.require_barby!
      return if defined?(::Barby)

      require 'barby'
    rescue LoadError
      raise DependencyError,
            'barby is required for barcode support. ' \
            'Install it with: gem install barby'
    end

    private_class_method :require_barby!
  end
end
