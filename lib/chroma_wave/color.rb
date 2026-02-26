# frozen_string_literal: true

module ChromaWave
  # Immutable RGBA color value type.
  #
  # Built on +Data.define+ for structural equality, freezing, and pattern matching.
  # All channels are integers in the range 0..255.
  #
  # @example
  #   Color.new(r: 255, g: 0, b: 0)          # => opaque red
  #   Color.hex('#FF0000')                     # => same
  #   Color.from_name(:red)                    # => same
  #   Color::RED.over(Color::WHITE)            # => compositing
  Color = Data.define(:r, :g, :b, :a) do
    # @!attribute [r] r
    #   @return [Integer] red channel (0..255)
    # @!attribute [r] g
    #   @return [Integer] green channel (0..255)
    # @!attribute [r] b
    #   @return [Integer] blue channel (0..255)
    # @!attribute [r] a
    #   @return [Integer] alpha channel (0..255), defaults to 255 (fully opaque)

    # Initializes a Color with RGBA channels.
    #
    # @param r [Integer] red channel (0..255)
    # @param g [Integer] green channel (0..255)
    # @param b [Integer] blue channel (0..255)
    # @param a [Integer] alpha channel (0..255), defaults to 255
    # @raise [ArgumentError] if any channel is outside 0..255
    # @raise [TypeError] if any channel is not an Integer
    def initialize(r:, g:, b:, a: 255)
      validate_channel!(:r, r)
      validate_channel!(:g, g)
      validate_channel!(:b, b)
      validate_channel!(:a, a)
      super
    end

    # Returns true if the color is fully opaque (alpha == 255).
    #
    # @return [Boolean]
    def opaque?
      a == 255
    end

    # Returns true if the color is fully transparent (alpha == 0).
    #
    # @return [Boolean]
    def transparent?
      a.zero?
    end

    # Packs the color into a 4-byte RGBA string.
    #
    # @return [String] 4-byte ASCII-8BIT string
    def to_rgba_bytes
      [r, g, b, a].pack('C4')
    end

    # Composites this color over a background using source-over alpha blending.
    #
    # The result is always fully opaque (alpha 255), suitable for final rendering.
    #
    # @param background [Color] the background color to composite over
    # @return [Color] the blended result with alpha 255
    def over(background)
      return self if opaque?
      return background if transparent?

      alpha = a / 255.0
      inv_alpha = 1.0 - alpha

      self.class.new(
        r: ((r * alpha) + (background.r * inv_alpha)).round,
        g: ((g * alpha) + (background.g * inv_alpha)).round,
        b: ((b * alpha) + (background.b * inv_alpha)).round
      )
    end

    # Returns the color as a 6-digit hex string.
    #
    # Alpha is not included — use {#a} directly when needed.
    #
    # @return [String] hex color string in +#RRGGBB+ format
    def to_hex
      format('#%<r>02X%<g>02X%<b>02X', r: r, g: g, b: b)
    end

    private

    # Validates that a channel value is an Integer in 0..255.
    #
    # @param name [Symbol] channel name for error messages
    # @param value [Object] the value to validate
    # @raise [TypeError] if not an Integer
    # @raise [ArgumentError] if outside 0..255
    def validate_channel!(name, value)
      raise TypeError, "#{name} must be an Integer, got #{value.class}" unless value.is_a?(Integer)
      raise ArgumentError, "#{name} must be 0..255, got #{value}" unless self.class::CHANNEL_RANGE.cover?(value)
    end
  end

  # Constants are defined outside the Data.define block because
  # Data.define blocks do not support const_set on the class being defined.
  #
  # Valid channel range for RGBA values.
  Color.const_set(:CHANNEL_RANGE, 0..255)

  # Regex for 6-digit hex color strings (#RRGGBB).
  Color.const_set(:HEX6_PATTERN, /\A#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})\z/i)

  # Regex for 3-digit shorthand hex color strings (#RGB).
  Color.const_set(:HEX3_PATTERN, /\A#([0-9a-f])([0-9a-f])([0-9a-f])\z/i)

  class << Color
    # Unpacks a 4-byte RGBA string into a Color.
    #
    # @param bytes [String] 4-byte string
    # @return [Color]
    # @raise [ArgumentError] if bytes is not exactly 4 bytes
    def from_rgba_bytes(bytes)
      raise ArgumentError, "expected 4 bytes, got #{bytes.bytesize}" unless bytes.bytesize == 4

      channels = bytes.unpack('C4')
      new(r: channels[0], g: channels[1], b: channels[2], a: channels[3])
    end

    # Parses a hex color string into a Color.
    #
    # Supports +#RRGGBB+ and +#RGB+ shorthand formats.
    #
    # @param str [String] hex color string
    # @return [Color] opaque color (alpha 255)
    # @raise [ArgumentError] if the string is not a valid hex color
    def hex(str)
      case str
      when self::HEX6_PATTERN
        new(r: ::Regexp.last_match(1).to_i(16),
            g: ::Regexp.last_match(2).to_i(16),
            b: ::Regexp.last_match(3).to_i(16))
      when self::HEX3_PATTERN
        new(r: ::Regexp.last_match(1).to_i(16) * 17,
            g: ::Regexp.last_match(2).to_i(16) * 17,
            b: ::Regexp.last_match(3).to_i(16) * 17)
      else
        raise ArgumentError, "invalid hex color: #{str.inspect} (expected #RGB or #RRGGBB)"
      end
    end

    # Looks up a color by its registered name.
    #
    # @param name [Symbol] the color name (e.g. +:black+)
    # @return [Color]
    # @raise [KeyError] if the name is not registered
    def from_name(name)
      self::NAME_MAP.fetch(name)
    end
  end

  # ── Named color constants ───────────────────────────────────────
  Color.const_set(:BLACK,       Color.new(r: 0,   g: 0,   b: 0))
  Color.const_set(:WHITE,       Color.new(r: 255, g: 255, b: 255))
  Color.const_set(:RED,         Color.new(r: 255, g: 0,   b: 0))
  Color.const_set(:YELLOW,      Color.new(r: 255, g: 255, b: 0))
  Color.const_set(:GREEN,       Color.new(r: 0,   g: 255, b: 0))
  Color.const_set(:BLUE,        Color.new(r: 0,   g: 0,   b: 255))
  Color.const_set(:ORANGE,      Color.new(r: 255, g: 128, b: 0))
  Color.const_set(:DARK_GRAY,   Color.new(r: 85,  g: 85,  b: 85))
  Color.const_set(:LIGHT_GRAY,  Color.new(r: 170, g: 170, b: 170))
  Color.const_set(:TRANSPARENT, Color.new(r: 0,   g: 0,   b: 0, a: 0))

  # Frozen map of all named colors for lookup by symbol.
  Color.const_set(:NAME_MAP, {
    black: Color::BLACK,
    white: Color::WHITE,
    red: Color::RED,
    yellow: Color::YELLOW,
    green: Color::GREEN,
    blue: Color::BLUE,
    orange: Color::ORANGE,
    dark_gray: Color::DARK_GRAY,
    light_gray: Color::LIGHT_GRAY,
    transparent: Color::TRANSPARENT
  }.freeze)
end
