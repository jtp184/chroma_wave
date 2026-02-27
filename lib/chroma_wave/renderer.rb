# frozen_string_literal: true

module ChromaWave
  # Bridges Canvas (RGBA pixels) to Framebuffer (format-specific packed pixels).
  #
  # Converts full-color RGBA content to the limited palette of an E-Paper
  # display using configurable dithering strategies. Supports single-buffer
  # rendering via {#render} and dual-buffer rendering for tri-color displays
  # via {#render_dual}.
  #
  # @example Render a canvas to a monochrome framebuffer
  #   renderer = Renderer.new(pixel_format: PixelFormat::MONO, dither: :threshold)
  #   fb = renderer.render(canvas)
  #
  # @example Render to dual buffers for a tri-color display
  #   renderer = Renderer.new(pixel_format: PixelFormat::COLOR4, dither: :threshold)
  #   black_fb, red_fb = renderer.render_dual(canvas)
  class Renderer # rubocop:disable Metrics/ClassLength
    # Supported dithering strategies.
    STRATEGIES = %i[floyd_steinberg ordered threshold].freeze

    # Bytes per pixel in the Canvas RGBA buffer.
    BYTES_PER_PIXEL = 4

    # Lightweight RGB triple used in hot loops to avoid full Color allocation.
    # Responds to .r, .g, .b for duck-type compatibility with Palette#nearest_color.
    RGB = Struct.new(:r, :g, :b)
    private_constant :RGB

    # Standard 4x4 Bayer matrix normalized to [0, 1) range.
    BAYER_4X4 = [
      [0.0 / 16, 8.0 / 16, 2.0 / 16, 10.0 / 16],
      [12.0 / 16, 4.0 / 16, 14.0 / 16, 6.0 / 16],
      [3.0 / 16, 11.0 / 16, 1.0 / 16, 9.0 / 16],
      [15.0 / 16, 7.0 / 16, 13.0 / 16, 5.0 / 16]
    ].freeze

    # Floyd-Steinberg error distribution weights.
    FS_RIGHT       = 7.0 / 16
    FS_BELOW_LEFT  = 3.0 / 16
    FS_BELOW       = 5.0 / 16
    FS_BELOW_RIGHT = 1.0 / 16

    attr_reader :pixel_format, :dither

    # Creates a new Renderer for the given pixel format and dither strategy.
    #
    # @param pixel_format [PixelFormat, Symbol] target pixel format
    # @param dither [Symbol] dithering strategy (:floyd_steinberg, :ordered, or :threshold)
    # @raise [ArgumentError] if the dither strategy is not recognized
    def initialize(pixel_format:, dither: :floyd_steinberg)
      @pixel_format = resolve_pixel_format(pixel_format)
      validate_dither!(dither)
      @dither = dither
    end

    # Renders a Canvas into a Framebuffer.
    #
    # @param canvas [Canvas] source RGBA canvas
    # @param into [Framebuffer, nil] optional pre-allocated framebuffer to reuse
    # @return [Framebuffer] the rendered framebuffer
    # @raise [TypeError] if canvas is not a Canvas
    # @raise [ArgumentError] if +into+ dimensions do not match the canvas
    def render(canvas, into: nil)
      validate_canvas!(canvas)
      framebuffer = prepare_framebuffer(canvas, into)
      quantize(canvas, framebuffer)
      framebuffer
    end

    # Renders a Canvas into two MONO Framebuffers for dual-buffer COLOR4 displays.
    #
    # Tri-color E-Paper displays use separate black and red planes.
    # Each pixel is quantized to the COLOR4 palette, then routed:
    # - +:black+ -- black_fb=0, red_fb=1
    # - +:white+ -- black_fb=1, red_fb=1
    # - +:red+ or +:yellow+ -- black_fb=1, red_fb=0
    #
    # @param canvas [Canvas] source RGBA canvas
    # @return [Array(Framebuffer, Framebuffer)] [black_fb, red_fb] both MONO format
    # @raise [ArgumentError] if pixel_format is not COLOR4
    # @raise [TypeError] if canvas is not a Canvas
    def render_dual(canvas)
      validate_canvas!(canvas)
      raise ArgumentError, 'render_dual requires COLOR4 pixel format' unless pixel_format == PixelFormat::COLOR4

      black_fb = Framebuffer.new(canvas.width, canvas.height, PixelFormat::MONO)
      red_fb   = Framebuffer.new(canvas.width, canvas.height, PixelFormat::MONO)
      split_channels(canvas, black_fb, red_fb)
      [black_fb, red_fb]
    end

    private

    # Resolves a pixel format argument into a PixelFormat object.
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

    # Validates that the dither strategy is recognized.
    #
    # @param strategy [Symbol] the dithering strategy
    # @raise [ArgumentError] if the strategy is not in STRATEGIES
    def validate_dither!(strategy)
      return if STRATEGIES.include?(strategy)

      raise ArgumentError,
            "unknown dither strategy: #{strategy.inspect} (expected one of #{STRATEGIES.join(', ')})"
    end

    # Validates that the canvas argument is a Canvas.
    #
    # @param canvas [Object] the object to validate
    # @raise [TypeError] if canvas is not a Canvas
    def validate_canvas!(canvas)
      return if canvas.is_a?(Canvas)

      raise TypeError, "expected Canvas, got #{canvas.class}"
    end

    # Prepares a Framebuffer for rendering, either reusing +into+ or allocating a new one.
    #
    # @param canvas [Canvas] source canvas for dimensions
    # @param into [Framebuffer, nil] optional pre-allocated framebuffer
    # @return [Framebuffer]
    # @raise [ArgumentError] if +into+ dimensions do not match the canvas
    def prepare_framebuffer(canvas, into)
      return Framebuffer.new(canvas.width, canvas.height, pixel_format) if into.nil?

      unless into.width == canvas.width && into.height == canvas.height
        raise ArgumentError,
              "framebuffer dimensions #{into.width}x#{into.height} " \
              "do not match canvas #{canvas.width}x#{canvas.height}"
      end

      into
    end

    # Dispatches to the appropriate quantization method based on the dither strategy.
    #
    # @param canvas [Canvas] source RGBA canvas
    # @param framebuffer [Framebuffer] target framebuffer
    def quantize(canvas, framebuffer)
      case dither
      when :threshold       then quantize_threshold(canvas, framebuffer)
      when :floyd_steinberg then quantize_floyd_steinberg(canvas, framebuffer)
      when :ordered         then quantize_ordered(canvas, framebuffer)
      else raise ArgumentError, "unreachable: unknown dither #{dither}"
      end
    end

    # Threshold quantization: simple nearest-color mapping with no error diffusion.
    #
    # Reads raw RGBA bytes from the canvas and maps each pixel to the nearest
    # palette color using the palette's redmean distance calculation. Uses a
    # reusable {RGB} struct to avoid per-pixel Color allocation.
    #
    # @param canvas [Canvas] source RGBA canvas
    # @param framebuffer [Framebuffer] target framebuffer
    def quantize_threshold(canvas, framebuffer)
      palette = pixel_format.palette
      bytes = canvas.rgba_bytes
      width = canvas.width
      pixel = RGB.new(0, 0, 0)

      canvas.height.times do |y|
        width.times do |x|
          offset = ((y * width) + x) * BYTES_PER_PIXEL
          pixel.r = bytes.getbyte(offset)
          pixel.g = bytes.getbyte(offset + 1)
          pixel.b = bytes.getbyte(offset + 2)
          framebuffer.set_pixel(x, y, palette.nearest_color(pixel))
        end
      end
    end

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
    # @param canvas [Canvas] source RGBA canvas
    # @param framebuffer [Framebuffer] target framebuffer
    def quantize_floyd_steinberg(canvas, framebuffer)
      palette = pixel_format.palette
      bytes = canvas.rgba_bytes
      width = canvas.width
      color_rgb = fs_build_color_rgb(palette)
      pixel = RGB.new(0, 0, 0)

      current_errors = Array.new(width) { [0.0, 0.0, 0.0] }
      next_errors    = Array.new(width) { [0.0, 0.0, 0.0] }

      canvas.height.times do |y|
        fs_process_row(bytes, y, width, pixel, palette, color_rgb, framebuffer,
                       current_errors, next_errors)
        current_errors, next_errors = next_errors, current_errors
        next_errors.each { |err| err[0] = 0.0; err[1] = 0.0; err[2] = 0.0 } # rubocop:disable Style/Semicolon
      end
    end

    # Processes a single row for Floyd-Steinberg dithering.
    #
    # @param bytes [String] raw RGBA canvas bytes
    # @param y_pos [Integer] current row index
    # @param width [Integer] row width in pixels
    # @param pixel [RGB] reusable pixel struct (mutated in place)
    # @param palette [Palette] target palette
    # @param color_rgb [Hash{Symbol => Array<Integer>}] palette color name to [r,g,b]
    # @param framebuffer [Framebuffer] target framebuffer
    # @param current_errors [Array<Array<Float>>] current row error buffer
    # @param next_errors [Array<Array<Float>>] next row error buffer
    def fs_process_row(bytes, y_pos, width, pixel, palette, color_rgb, # rubocop:disable Metrics/ParameterLists
                       framebuffer, current_errors, next_errors)
      row_offset = y_pos * width * BYTES_PER_PIXEL
      width.times do |x|
        fs_adjust_pixel!(pixel, bytes, row_offset + (x * BYTES_PER_PIXEL), current_errors[x])
        nearest_name = palette.nearest_color(pixel)
        framebuffer.set_pixel(x, y_pos, nearest_name)
        fs_distribute(current_errors, next_errors, x, width, pixel, color_rgb[nearest_name])
      end
    end

    # Adjusts a pixel in-place with accumulated error for Floyd-Steinberg.
    #
    # Mutates the given {RGB} struct to avoid per-pixel allocation.
    #
    # @param pixel [RGB] the struct to fill (mutated)
    # @param bytes [String] raw RGBA canvas bytes
    # @param offset [Integer] byte offset into the canvas buffer
    # @param err [Array<Float>] [r, g, b] accumulated error for this pixel
    def fs_adjust_pixel!(pixel, bytes, offset, err)
      pixel.r = (bytes.getbyte(offset) + err[0]).round.clamp(0, 255)
      pixel.g = (bytes.getbyte(offset + 1) + err[1]).round.clamp(0, 255)
      pixel.b = (bytes.getbyte(offset + 2) + err[2]).round.clamp(0, 255)
    end

    # Builds a lookup table from palette color names to [r, g, b] arrays.
    #
    # Pre-computed once per render to avoid per-pixel Color.from_name lookups
    # during Floyd-Steinberg error distribution.
    #
    # @param palette [Palette] the palette to index
    # @return [Hash{Symbol => Array<Integer>}] name to [r, g, b] mapping
    def fs_build_color_rgb(palette)
      palette.each_with_object({}) do |name, map|
        c = Color.from_name(name)
        map[name] = [c.r, c.g, c.b].freeze
      end
    end

    # Distributes Floyd-Steinberg quantization error to neighboring pixels.
    #
    # @param current [Array<Array<Float>>] current row error buffer
    # @param next_row [Array<Array<Float>>] next row error buffer
    # @param x [Integer] current pixel x coordinate
    # @param width [Integer] row width
    # @param adjusted [RGB] the error-adjusted input pixel
    # @param nearest_rgb [Array<Integer>] [r, g, b] of the quantized palette color
    def fs_distribute(current, next_row, x, width, adjusted, nearest_rgb)
      error = [adjusted.r - nearest_rgb[0], adjusted.g - nearest_rgb[1], adjusted.b - nearest_rgb[2]]

      fs_add_error(current, x + 1, width, error, FS_RIGHT)
      fs_add_error(next_row, x - 1, width, error, FS_BELOW_LEFT)
      fs_add_error(next_row, x, width, error, FS_BELOW)
      fs_add_error(next_row, x + 1, width, error, FS_BELOW_RIGHT)
    end

    # Adds a weighted error to a single pixel in an error buffer row.
    #
    # @param row [Array<Array<Float>>] error buffer row
    # @param x [Integer] target pixel x coordinate
    # @param width [Integer] row width (for bounds check)
    # @param error [Array<Numeric>] [r, g, b] quantization error
    # @param weight [Float] distribution weight
    def fs_add_error(row, x, width, error, weight)
      return unless x >= 0 && x < width

      cell = row[x]
      cell[0] += error[0] * weight
      cell[1] += error[1] * weight
      cell[2] += error[2] * weight
    end

    # Ordered dithering using a 4x4 Bayer matrix.
    #
    # For each pixel, a threshold from the Bayer matrix is added to each
    # channel before finding the nearest palette color. The threshold is
    # scaled proportionally to the palette size so that pure extremes
    # (black, white) are preserved. Produces a regular halftone-like pattern.
    #
    # @param canvas [Canvas] source RGBA canvas
    # @param framebuffer [Framebuffer] target framebuffer
    def quantize_ordered(canvas, framebuffer)
      palette = pixel_format.palette
      bytes = canvas.rgba_bytes
      width = canvas.width
      spread = 256.0 / palette.size
      pixel = RGB.new(0, 0, 0)

      canvas.height.times do |y|
        width.times do |x|
          offset = ((y * width) + x) * BYTES_PER_PIXEL
          threshold = (BAYER_4X4[y % 4][x % 4] - 0.5) * spread
          bayer_adjust_pixel!(pixel, bytes, offset, threshold)
          framebuffer.set_pixel(x, y, palette.nearest_color(pixel))
        end
      end
    end

    # Fills a reusable {RGB} struct with Bayer-threshold-adjusted values for ordered dithering.
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

    # Splits a Canvas into two MONO Framebuffers for dual-buffer COLOR4 displays.
    #
    # Quantizes each pixel to the COLOR4 palette, then routes based on color name:
    # - +:black+ -- black plane gets 0 (black), red plane gets 1 (white)
    # - +:white+ -- black plane gets 1 (white), red plane gets 1 (white)
    # - +:red+ or +:yellow+ -- black plane gets 1 (white), red plane gets 0 (black)
    #
    # @param canvas [Canvas] source RGBA canvas
    # @param black_fb [Framebuffer] MONO framebuffer for the black plane
    # @param red_fb [Framebuffer] MONO framebuffer for the red plane
    def split_channels(canvas, black_fb, red_fb)
      palette = pixel_format.palette
      bytes = canvas.rgba_bytes
      width = canvas.width
      pixel = RGB.new(0, 0, 0)

      canvas.height.times do |y|
        width.times do |x|
          offset = ((y * width) + x) * BYTES_PER_PIXEL
          pixel.r = bytes.getbyte(offset)
          pixel.g = bytes.getbyte(offset + 1)
          pixel.b = bytes.getbyte(offset + 2)
          route_dual_pixel(palette.nearest_color(pixel), black_fb, red_fb, x, y)
        end
      end
    end

    # Routes a single quantized pixel to the appropriate dual-buffer planes.
    #
    # @param name [Symbol] the quantized palette color name
    # @param black_fb [Framebuffer] black plane framebuffer
    # @param red_fb [Framebuffer] red plane framebuffer
    # @param x [Integer] pixel x coordinate
    # @param y [Integer] pixel y coordinate
    def route_dual_pixel(name, black_fb, red_fb, x, y)
      case name
      when :black
        black_fb.set_pixel(x, y, :black)
        red_fb.set_pixel(x, y, :white)
      when :white
        black_fb.set_pixel(x, y, :white)
        red_fb.set_pixel(x, y, :white)
      when :red, :yellow
        black_fb.set_pixel(x, y, :white)
        red_fb.set_pixel(x, y, :black)
      end
    end
  end
end
