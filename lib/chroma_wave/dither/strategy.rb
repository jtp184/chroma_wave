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
    end
  end
end
