# frozen_string_literal: true

module ChromaWave
  module Dither
    # Ordered dithering using a 4x4 Bayer matrix.
    #
    # For each pixel, a threshold from the Bayer matrix is added to each
    # channel before finding the nearest palette color. The threshold is
    # scaled proportionally to the palette size so that pure extremes
    # (black, white) are preserved. Produces a regular halftone-like pattern.
    #
    # @example
    #   strategy = Dither::Ordered.new(pixel_format: PixelFormat::MONO)
    #   strategy.call(canvas, framebuffer)
    class Ordered < Strategy
      # Standard 4x4 Bayer matrix normalized to [0, 1) range.
      BAYER_4X4 = [
        [0.0 / 16, 8.0 / 16, 2.0 / 16, 10.0 / 16],
        [12.0 / 16, 4.0 / 16, 14.0 / 16, 6.0 / 16],
        [3.0 / 16, 11.0 / 16, 1.0 / 16, 9.0 / 16],
        [15.0 / 16, 7.0 / 16, 13.0 / 16, 5.0 / 16]
      ].freeze

      # Quantizes a canvas into a framebuffer using ordered Bayer dithering.
      #
      # @param canvas [Canvas] source RGBA canvas
      # @param framebuffer [Framebuffer] target framebuffer (mutated in place)
      # @return [void]
      def call(canvas, framebuffer)
        pal = palette
        bytes = canvas.rgba_bytes
        width = canvas.width
        spread = 256.0 / pal.size
        pixel = RGB.new(0, 0, 0)

        canvas.height.times do |y|
          width.times do |x|
            offset = ((y * width) + x) * BYTES_PER_PIXEL
            threshold = (BAYER_4X4[y % 4][x % 4] - 0.5) * spread
            bayer_adjust_pixel!(pixel, bytes, offset, threshold)
            framebuffer.set_pixel(x, y, pal.nearest_color(pixel))
          end
        end
      end

      private

      # Fills a reusable {RGB} struct with Bayer-threshold-adjusted values.
      #
      # Mutates +pixel+ in place to avoid per-pixel Color allocation.
      #
      # @param pixel [RGB] the struct to fill (mutated)
      # @param bytes [String] raw RGBA canvas bytes
      # @param offset [Integer] byte offset into the canvas buffer
      # @param threshold [Float] Bayer threshold value scaled by spread
      def bayer_adjust_pixel!(pixel, bytes, offset, threshold)
        pixel.r = (bytes.getbyte(offset) + threshold).round.clamp(0, 255)
        pixel.g = (bytes.getbyte(offset + 1) + threshold).round.clamp(0, 255)
        pixel.b = (bytes.getbyte(offset + 2) + threshold).round.clamp(0, 255)
      end
    end
  end
end
