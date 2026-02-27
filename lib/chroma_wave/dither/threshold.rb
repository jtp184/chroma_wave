# frozen_string_literal: true

module ChromaWave
  module Dither
    # Threshold quantization: simple nearest-color mapping with no error diffusion.
    #
    # Reads raw RGBA bytes from the canvas and maps each pixel to the nearest
    # palette color using the palette's redmean distance calculation. Uses a
    # reusable {RGB} struct to avoid per-pixel Color allocation.
    #
    # @example
    #   strategy = Dither::Threshold.new(pixel_format: PixelFormat::MONO)
    #   strategy.call(canvas, framebuffer)
    class Threshold < Strategy
      # Quantizes a canvas into a framebuffer using nearest-color threshold mapping.
      #
      # @param canvas [Canvas] source RGBA canvas
      # @param framebuffer [Framebuffer] target framebuffer (mutated in place)
      # @return [void]
      def call(canvas, framebuffer)
        pal = palette
        bytes = canvas.rgba_bytes
        width = canvas.width
        pixel = RGB.new(0, 0, 0)

        canvas.height.times do |y|
          width.times do |x|
            offset = ((y * width) + x) * BYTES_PER_PIXEL
            pixel.r = bytes.getbyte(offset)
            pixel.g = bytes.getbyte(offset + 1)
            pixel.b = bytes.getbyte(offset + 2)
            framebuffer.set_pixel(x, y, pal.nearest_color(pixel))
          end
        end
      end
    end
  end
end
