# frozen_string_literal: true

module ChromaWave
  class Framebuffer
    # Translates between the Ruby PixelFormat/Palette symbol domain and the
    # C extension's integer domain.
    #
    # Prepended onto the C-defined +Framebuffer+ class so +super+ dispatches
    # to the C methods. No C code modifications needed.
    module PixelFormatBridge
      # Initializes the framebuffer with a PixelFormat object or symbol.
      #
      # @param width [Integer] framebuffer width in pixels
      # @param height [Integer] framebuffer height in pixels
      # @param format [PixelFormat, Symbol] pixel format descriptor or name
      # @raise [ArgumentError] for unknown format symbols
      def initialize(width, height, format)
        @pixel_format_obj = resolve_pixel_format(format)
        super(width, height, @pixel_format_obj.name)
      end

      # Returns the PixelFormat object for this framebuffer.
      #
      # @return [PixelFormat]
      def pixel_format
        @pixel_format_obj
      end

      # Sets a pixel using a color name or integer.
      #
      # @param x [Integer] x coordinate
      # @param y [Integer] y coordinate
      # @param color [Symbol, Integer] palette color name or raw integer
      # @return [self]
      def set_pixel(x, y, color)
        super(x, y, resolve_color(color))
      end

      # Gets the pixel at (x, y) as a palette color name.
      #
      # @param x [Integer] x coordinate
      # @param y [Integer] y coordinate
      # @return [Symbol, nil] palette color name, or nil if out-of-bounds
      def get_pixel(x, y)
        value = super
        return nil if value.nil?

        pixel_format.palette.color_at(value)
      end

      # Clears the framebuffer with a color name or integer.
      #
      # @param color [Symbol, Integer] palette color name or raw integer
      # @return [self]
      def clear(color)
        super(resolve_color(color))
      end

      # Deep-copies the framebuffer, preserving the PixelFormat object.
      #
      # @param other [Framebuffer] the source framebuffer
      # @return [self]
      def initialize_copy(other)
        super
        @pixel_format_obj = other.pixel_format
        self
      end

      private

      # Resolves a format argument into a PixelFormat object.
      #
      # @param format [PixelFormat, Symbol] format descriptor or name
      # @return [PixelFormat]
      def resolve_pixel_format(format)
        case format
        when PixelFormat then format
        when Symbol      then PixelFormat.from_name(format)
        else raise TypeError, "expected PixelFormat or Symbol, got #{format.class}"
        end
      end

      # Resolves a color argument into an integer for the C layer.
      #
      # Integers are range-checked against the palette size so that
      # out-of-range values fail fast at input rather than producing
      # a silent write that later raises +IndexError+ on read.
      #
      # @param color [Symbol, Integer] palette color name or raw integer
      # @return [Integer]
      # @raise [ArgumentError] if an integer is outside the palette range
      def resolve_color(color)
        case color
        when Integer then validate_color_index(color)
        when Symbol  then pixel_format.palette.index_of(color)
        else raise TypeError, "expected Symbol or Integer color, got #{color.class}"
        end
      end

      # Validates that an integer color index is within palette bounds.
      #
      # @param index [Integer] the color index to validate
      # @return [Integer] the index, if valid
      # @raise [ArgumentError] if index is negative or >= palette size
      def validate_color_index(index)
        max = pixel_format.palette.size
        return index if index >= 0 && index < max

        raise ArgumentError,
              "color index #{index} out of range for #{pixel_format.name} palette (0...#{max})"
      end
    end

    prepend PixelFormatBridge
  end
end
