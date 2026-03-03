# frozen_string_literal: true

module ChromaWave
  module Dither
    # Floyd-Steinberg error diffusion dithering.
    #
    # Processes pixels left-to-right, top-to-bottom. For each pixel, the
    # accumulated error is added before finding the nearest palette color.
    # The remaining quantization error is distributed to neighboring pixels:
    # - right:       7/16
    # - below-left:  3/16
    # - below:       5/16
    # - below-right: 1/16
    #
    # Uses a 2-row ring buffer to minimize memory allocation. The inner loop
    # works with raw integer r/g/b values and a reusable {RGB} struct to
    # avoid per-pixel Color object allocation.
    #
    # @example
    #   strategy = Dither::FloydSteinberg.new(pixel_format: PixelFormat::MONO)
    #   strategy.call(canvas, framebuffer)
    class FloydSteinberg < Strategy
      # Floyd-Steinberg error distribution weights.
      FS_RIGHT       = 7.0 / 16
      FS_BELOW_LEFT  = 3.0 / 16
      FS_BELOW       = 5.0 / 16
      FS_BELOW_RIGHT = 1.0 / 16

      # Quantizes a canvas into a framebuffer using Floyd-Steinberg error diffusion.
      #
      # @param canvas [Canvas] source RGBA canvas
      # @param framebuffer [Framebuffer] target framebuffer (mutated in place)
      # @return [void]
      def call(canvas, framebuffer)
        pal = palette
        bytes = canvas.raw_buffer
        width = canvas.width
        color_rgb = build_color_rgb(pal)
        pixel = RGB.new(0, 0, 0)

        current_errors = Array.new(width) { [0.0, 0.0, 0.0] }
        next_errors    = Array.new(width) { [0.0, 0.0, 0.0] }

        canvas.height.times do |y|
          process_row(bytes, y, width, pixel, pal, color_rgb, framebuffer,
                      current_errors, next_errors)
          current_errors, next_errors = next_errors, current_errors
          next_errors.each { |err| err[0] = 0.0; err[1] = 0.0; err[2] = 0.0 } # rubocop:disable Style/Semicolon
        end
      end

      private

      # Processes a single row for Floyd-Steinberg dithering.
      #
      # @param bytes [String] raw RGBA canvas bytes
      # @param y_pos [Integer] current row index
      # @param width [Integer] row width in pixels
      # @param pixel [RGB] reusable pixel struct (mutated in place)
      # @param pal [Palette] target palette
      # @param color_rgb [Hash{Symbol => Array<Integer>}] palette color name to [r,g,b]
      # @param framebuffer [Framebuffer] target framebuffer
      # @param current_errors [Array<Array<Float>>] current row error buffer
      # @param next_errors [Array<Array<Float>>] next row error buffer
      def process_row(bytes, y_pos, width, pixel, pal, color_rgb, # rubocop:disable Metrics/ParameterLists
                      framebuffer, current_errors, next_errors)
        row_offset = y_pos * width * BYTES_PER_PIXEL
        width.times do |x|
          adjust_pixel!(pixel, bytes, row_offset + (x * BYTES_PER_PIXEL), current_errors[x])
          nearest_name = pal.nearest_color(pixel)
          framebuffer.set_pixel(x, y_pos, nearest_name)
          distribute(current_errors, next_errors, x, width, pixel, color_rgb[nearest_name])
        end
      end

      # Distributes quantization error to neighboring pixels.
      #
      # Computes per-channel error as separate numeric variables to avoid
      # allocating a temporary 3-element Array on every pixel.
      #
      # @param current [Array<Array<Float>>] current row error buffer
      # @param next_row [Array<Array<Float>>] next row error buffer
      # @param x [Integer] current pixel x coordinate
      # @param width [Integer] row width
      # @param adjusted [RGB] the error-adjusted input pixel
      # @param nearest_rgb [Array<Integer>] [r, g, b] of the quantized palette color
      def distribute(current, next_row, x, width, adjusted, nearest_rgb)
        err_r = adjusted.r - nearest_rgb[0]
        err_g = adjusted.g - nearest_rgb[1]
        err_b = adjusted.b - nearest_rgb[2]

        add_error(current, x + 1, width, err_r, err_g, err_b, FS_RIGHT)
        add_error(next_row, x - 1, width, err_r, err_g, err_b, FS_BELOW_LEFT)
        add_error(next_row, x, width, err_r, err_g, err_b, FS_BELOW)
        add_error(next_row, x + 1, width, err_r, err_g, err_b, FS_BELOW_RIGHT)
      end
    end
  end
end
