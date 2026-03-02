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
    # The result is always fully opaque (alpha 255), suitable for compositing
    # onto an opaque background (the typical e-paper use case). This is a
    # simplified Porter-Duff source-over that discards the background's alpha
    # channel — it does not produce correct results when compositing onto
    # a semi-transparent destination.
    #
    # @param background [Color] the background color to composite over
    # @return [Color] the blended result with alpha 255
    def over(background) # rubocop:disable Metrics/AbcSize
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

    # Returns the CIE L*a*b* representation of this color.
    #
    # Results are cached at the class level by structural equality,
    # so repeated calls for equal Colors return the same Array object.
    #
    # @return [Array(Float, Float, Float)] [L*, a*, b*]
    def to_lab
      Color.lab_cache[self] ||= Color.compute_lab(r, g, b)
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

  # CIE D65 standard illuminant tristimulus values (2° observer).
  Color.const_set(:D65_XN, 0.95047)
  Color.const_set(:D65_YN, 1.00000)
  Color.const_set(:D65_ZN, 1.08883)

  # CIE Lab transfer function threshold: (6/29)^3.
  Color.const_set(:LAB_EPSILON, (6.0 / 29)**3)

  # CIE Lab transfer function scale factor: 1/3 * (29/6)^2.
  Color.const_set(:LAB_KAPPA, (1.0 / 3) * ((29.0 / 6)**2))

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

    # Returns the class-level Lab cache (keyed by Color structural equality).
    #
    # @return [Hash{Color => Array(Float, Float, Float)}]
    def lab_cache
      @lab_cache ||= {}
    end

    # Computes CIE L*a*b* values from sRGB channels.
    #
    # Orchestrates the full pipeline: sRGB → linear RGB → XYZ → Lab.
    #
    # @param r [Integer] red channel (0..255)
    # @param g [Integer] green channel (0..255)
    # @param b [Integer] blue channel (0..255)
    # @return [Array(Float, Float, Float)] [L*, a*, b*]
    def compute_lab(r, g, b)
      tri_x, tri_y, tri_z = srgb_to_xyz(r, g, b)
      xyz_to_lab(tri_x, tri_y, tri_z)
    end

    # Converts sRGB (0..255) to CIE XYZ using IEC 61966-2-1 matrix.
    #
    # @param r [Integer] red channel (0..255)
    # @param g [Integer] green channel (0..255)
    # @param b [Integer] blue channel (0..255)
    # @return [Array(Float, Float, Float)] [X, Y, Z] tristimulus values
    def srgb_to_xyz(r, g, b)
      rl = gamma_decode(r / 255.0)
      gl = gamma_decode(g / 255.0)
      bl = gamma_decode(b / 255.0)

      x = (0.4124564 * rl) + (0.3575761 * gl) + (0.1804375 * bl)
      y = (0.2126729 * rl) + (0.7151522 * gl) + (0.0721750 * bl)
      z = (0.0193339 * rl) + (0.1191920 * gl) + (0.9503041 * bl)

      [x, y, z]
    end

    # Converts CIE XYZ to CIE L*a*b* relative to D65 illuminant.
    #
    # @param tri_x [Float] X tristimulus value
    # @param tri_y [Float] Y tristimulus value
    # @param tri_z [Float] Z tristimulus value
    # @return [Array(Float, Float, Float)] [L*, a*, b*]
    def xyz_to_lab(tri_x, tri_y, tri_z)
      fx = lab_f(tri_x / self::D65_XN)
      fy = lab_f(tri_y / self::D65_YN)
      fz = lab_f(tri_z / self::D65_ZN)

      l = (116.0 * fy) - 16.0
      a = 500.0 * (fx - fy)
      b = 200.0 * (fy - fz)

      [l, a, b]
    end

    private

    # sRGB inverse companding (gamma decode).
    #
    # @param srgb [Float] normalized sRGB channel (0.0..1.0)
    # @return [Float] linear RGB value
    def gamma_decode(srgb)
      srgb <= 0.04045 ? srgb / 12.92 : ((srgb + 0.055) / 1.055)**2.4
    end

    # CIE Lab transfer function.
    #
    # @param ratio [Float] normalized tristimulus ratio
    # @return [Float] compressed value
    def lab_f(ratio)
      ratio > self::LAB_EPSILON ? ratio**(1.0 / 3) : (self::LAB_KAPPA * ratio) + (4.0 / 29)
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
