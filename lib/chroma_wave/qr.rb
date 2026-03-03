# frozen_string_literal: true

module ChromaWave
  # Standalone QR code utilities.
  #
  # Provides measurement helpers that don't require a drawing surface,
  # so callers can compute pixel dimensions for centering or layout
  # before committing to a +draw_qr+ call.
  #
  # @example
  #   metrics = ChromaWave::QR.measure("https://example.com", module_size: 4)
  #   metrics.width  # => pixel width of the rendered QR
  #   metrics.height # => pixel height (always equal to width)
  module QR
    # Maps user-facing error correction symbols to rqrcode's internal symbols.
    LEVEL_MAP = {
      low: :l,
      medium: :m,
      quartile: :q,
      high: :h
    }.freeze

    # Pixel dimensions and module count for a QR code.
    #
    # @!attribute [r] width
    #   @return [Integer] total width in pixels
    # @!attribute [r] height
    #   @return [Integer] total height in pixels
    # @!attribute [r] modules
    #   @return [Integer] number of modules along one side
    Metrics = Data.define(:width, :height, :modules)

    # Computes the pixel dimensions of a QR code without rendering it.
    #
    # @param data [String] the data to encode
    # @param module_size [Integer] pixel size of each QR module
    # @param error_correction [Symbol] one of +:low+, +:medium+, +:quartile+, +:high+
    # @param quiet_zone [Integer] number of empty modules around the QR code (default 4)
    # @return [Metrics] frozen value object with width, height, and module count
    # @raise [ArgumentError] if +error_correction+ is unknown
    # @raise [DependencyError] if rqrcode is not installed
    def self.measure(data, module_size:, error_correction: :medium, quiet_zone: 4)
      require_rqrcode!
      level = resolve_level(error_correction)
      qr = ::RQRCode::QRCode.new(data, level: level)
      n = qr.modules.length
      px = (n + (2 * quiet_zone)) * module_size
      Metrics.new(width: px, height: px, modules: n)
    end

    # Resolves a user-facing error correction symbol to rqrcode's internal symbol.
    #
    # @param level [Symbol] one of +:low+, +:medium+, +:quartile+, +:high+
    # @return [Symbol] rqrcode level symbol
    # @raise [ArgumentError] if +level+ is unknown
    def self.resolve_level(level)
      LEVEL_MAP.fetch(level) do
        raise ArgumentError, "unknown error_correction: #{level.inspect} " \
                             "(expected #{LEVEL_MAP.keys.map(&:inspect).join(', ')})"
      end
    end

    # Lazily requires rqrcode, raising DependencyError if not installed.
    #
    # @raise [DependencyError] if rqrcode cannot be loaded
    def self.require_rqrcode!
      return if defined?(::RQRCode)

      require 'rqrcode'
    rescue LoadError
      raise DependencyError,
            'rqrcode is required for QR code support. ' \
            'Install it with: gem install rqrcode'
    end

    private_class_method :require_rqrcode!
  end
end
