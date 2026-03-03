# frozen_string_literal: true

module ChromaWave
  module Dither
    # Abstract base class for dithering strategies.
    #
    # Provides shared infrastructure for converting RGBA canvas pixels to
    # palette-indexed framebuffer pixels. Subclasses implement {#call} with
    # a specific dithering algorithm.
    #
    # @abstract Subclass and implement {#call}.
    class Strategy
      # Bytes per pixel in the Canvas RGBA buffer.
      BYTES_PER_PIXEL = 4

      # Lightweight RGB triple used in hot loops to avoid full Color allocation.
      # Responds to .r, .g, .b for duck-type compatibility with Palette#nearest_color.
      RGB = Struct.new(:r, :g, :b)

      # Returns the symbolic name of this strategy for registry lookup.
      #
      # Derived from the unqualified class name (e.g. +FloydSteinberg+ -> +:floyd_steinberg+).
      #
      # @return [Symbol]
      def self.strategy_name
        name.split('::').last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
      end

      attr_reader :pixel_format

      # Creates a new strategy for the given pixel format.
      #
      # @param pixel_format [PixelFormat] target pixel format with palette
      def initialize(pixel_format:)
        @pixel_format = pixel_format
      end

      # Quantizes a canvas into a framebuffer using this strategy.
      #
      # @param canvas [Canvas] source RGBA canvas
      # @param framebuffer [Framebuffer] target framebuffer (mutated in place)
      # @return [void]
      # @raise [NotImplementedError] if not overridden by subclass
      def call(canvas, framebuffer)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      private

      # Returns the palette from the pixel format.
      #
      # @return [Palette]
      def palette
        pixel_format.palette
      end

      # Builds a lookup table from palette color names to [r, g, b] arrays.
      #
      # Pre-computed once per render to avoid per-pixel Color.from_name lookups
      # during error distribution.
      #
      # @param pal [Palette] the palette to index
      # @return [Hash{Symbol => Array<Integer>}] name to [r, g, b] mapping
      def build_color_rgb(pal)
        pal.each_with_object({}) do |name, map|
          c = Color.from_name(name)
          map[name] = [c.r, c.g, c.b].freeze
        end
      end

      # Adjusts a pixel in-place with accumulated error.
      #
      # Mutates the given {RGB} struct to avoid per-pixel allocation.
      #
      # @param pixel [RGB] the struct to fill (mutated)
      # @param bytes [String] raw RGBA canvas bytes
      # @param offset [Integer] byte offset into the canvas buffer
      # @param err [Array<Float>] [r, g, b] accumulated error for this pixel
      def adjust_pixel!(pixel, bytes, offset, err)
        pixel.r = (bytes.getbyte(offset) + err[0]).round.clamp(0, 255)
        pixel.g = (bytes.getbyte(offset + 1) + err[1]).round.clamp(0, 255)
        pixel.b = (bytes.getbyte(offset + 2) + err[2]).round.clamp(0, 255)
      end

      # Adds a weighted error to a single pixel in an error buffer row.
      #
      # @param row [Array<Array<Float>>] error buffer row
      # @param x [Integer] target pixel x coordinate
      # @param width [Integer] row width (for bounds check)
      # @param err_r [Numeric] red channel quantization error
      # @param err_g [Numeric] green channel quantization error
      # @param err_b [Numeric] blue channel quantization error
      # @param weight [Float] distribution weight
      def add_error(row, x, width, err_r, err_g, err_b, weight) # rubocop:disable Metrics/ParameterLists
        return unless x >= 0 && x < width

        cell = row[x]
        cell[0] += err_r * weight
        cell[1] += err_g * weight
        cell[2] += err_b * weight
      end
    end
  end
end
