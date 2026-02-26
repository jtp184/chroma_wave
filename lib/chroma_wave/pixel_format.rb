# frozen_string_literal: true

module ChromaWave
  # Immutable pixel format descriptor binding a name, bit depth, and palette.
  #
  # Each constant (MONO, GRAY4, COLOR4, COLOR7) defines one hardware-supported
  # pixel packing scheme. The palette entry ordering exactly matches the
  # hardware's integer-to-color mapping.
  #
  # @example
  #   fmt = PixelFormat::MONO
  #   fmt.bits_per_pixel      # => 1
  #   fmt.pixels_per_byte     # => 8
  #   fmt.buffer_size(122, 250)  # => 4000 (same as C)
  PixelFormat = Data.define(:name, :bits_per_pixel, :palette) do
    # Number of pixels packed into a single byte.
    #
    # @return [Integer]
    def pixels_per_byte
      8 / bits_per_pixel
    end

    # Calculates the buffer size in bytes for the given dimensions.
    #
    # Uses ceiling division matching the C extension's +calc_width_byte+.
    #
    # @param width [Integer] framebuffer width in pixels
    # @param height [Integer] framebuffer height in pixels
    # @return [Integer] buffer size in bytes
    def buffer_size(width, height)
      width_byte = (width + pixels_per_byte - 1) / pixels_per_byte
      width_byte * height
    end

    # Returns true if the given color name is valid for this format's palette.
    #
    # @param color [Symbol] a color name
    # @return [Boolean]
    def valid_color?(color)
      palette.include?(color)
    end
  end

  # ── Format constants ───────────────────────────────────────────

  # 1-bit monochrome: black/white.
  PixelFormat.const_set(:MONO, PixelFormat.new(
                                 name: :mono,
                                 bits_per_pixel: 1,
                                 palette: Palette[:black, :white]
                               ))

  # 2-bit grayscale: 4 shades.
  PixelFormat.const_set(:GRAY4, PixelFormat.new(
                                  name: :gray4,
                                  bits_per_pixel: 2,
                                  palette: Palette[:black, :dark_gray, :light_gray, :white]
                                ))

  # 4-bit tri-color: black/white/yellow/red.
  PixelFormat.const_set(:COLOR4, PixelFormat.new(
                                   name: :color4,
                                   bits_per_pixel: 4,
                                   palette: Palette[:black, :white, :yellow, :red]
                                 ))

  # 4-bit 7-color ACeP.
  PixelFormat.const_set(:COLOR7, PixelFormat.new(
                                   name: :color7,
                                   bits_per_pixel: 4,
                                   palette: Palette[:black, :white, :green, :blue, :red, :yellow, :orange]
                                 ))

  # Frozen registry mapping format names to their PixelFormat constants.
  PixelFormat.const_set(:REGISTRY, {
    mono: PixelFormat::MONO,
    gray4: PixelFormat::GRAY4,
    color4: PixelFormat::COLOR4,
    color7: PixelFormat::COLOR7
  }.freeze)

  class << PixelFormat
    # Looks up a PixelFormat by its symbolic name.
    #
    # @param sym [Symbol] format name (e.g. +:mono+, +:gray4+)
    # @return [PixelFormat]
    # @raise [ArgumentError] if the name is not recognized
    def from_name(sym)
      self::REGISTRY.fetch(sym) do
        raise ArgumentError,
              "unknown pixel format: #{sym.inspect} (expected one of #{self::REGISTRY.keys.join(', ')})"
      end
    end
  end
end
