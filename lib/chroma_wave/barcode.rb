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
    # Pixel gap between bars and text label.
    TEXT_GAP_PX = 2

    # Multiplier applied to font line_height for text label sizing.
    TEXT_HEIGHT_FACTOR = 1.2

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

    # Computes the pixel dimensions of a barcode without rendering it.
    #
    # @param data [String] the data to encode
    # @param symbology [Symbol] symbology key (e.g. +:code128+, +:ean13+)
    # @param module_width [Integer] pixel width per narrow bar
    # @param height [Integer] bar height in pixels
    # @param include_text [Boolean] whether text will be rendered below bars
    # @param text_font [Font, nil] font for text (required if include_text)
    # @return [Metrics] frozen value object with width, height, and encoding length
    # @raise [ArgumentError] if symbology is unknown, data is invalid, or text_font missing
    # @raise [DependencyError] if barby is not installed
    def self.measure(data, symbology:, module_width: 2, height: 60, include_text: false, text_font: nil)
      if include_text && text_font.nil?
        raise ArgumentError,
              'text_font: is required when include_text: true'
      end

      encoding = encode(symbology, data)

      total_width = encoding.length * module_width
      total_height = if include_text
                       height + TEXT_GAP_PX + (text_font.line_height * TEXT_HEIGHT_FACTOR).round
                     else
                       height
                     end

      Metrics.new(width: total_width, height: total_height, encoding_length: encoding.length)
    end

    # Encodes data for the given symbology and returns the flat binary encoding string.
    #
    # Each character in the returned string is +'1'+ (dark bar) or +'0'+ (space).
    # This is the single source of truth for barcode encoding; both {.measure}
    # and {Drawing::Codes#draw_barcode} delegate here.
    #
    # @param symbology [Symbol] symbology key (e.g. +:code128+, +:ean13+)
    # @param data [String] data to encode
    # @return [String] binary encoding string of '1' and '0' characters
    # @raise [ArgumentError] if symbology is unknown or data is invalid for the symbology
    # @raise [DependencyError] if barby is not installed
    def self.encode(symbology, data)
      barcode = build_barcode(symbology, data)
      encoding = barcode.encoding
      encoding.is_a?(Array) ? encoding.join : encoding
    end

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

    private_class_method :build_barcode, :require_barby!
  end
end
