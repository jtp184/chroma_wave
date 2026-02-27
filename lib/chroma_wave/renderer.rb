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
  class Renderer
    attr_reader :pixel_format, :dither

    # Creates a new Renderer for the given pixel format and dither strategy.
    #
    # @param pixel_format [PixelFormat, Symbol] target pixel format
    # @param dither [Symbol] dithering strategy (:floyd_steinberg, :ordered, or :threshold)
    # @raise [ArgumentError] if the dither strategy is not recognized
    def initialize(pixel_format:, dither: :floyd_steinberg)
      @pixel_format = resolve_pixel_format(pixel_format)
      @strategy = Dither.resolve(dither, pixel_format: @pixel_format)
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
      strategy.call(canvas, framebuffer)
      framebuffer
    end

    # Renders a Canvas into two MONO Framebuffers for dual-buffer COLOR4 displays.
    #
    # Tri-color E-Paper displays use separate black and red planes.
    # The canvas is first quantized to a COLOR4 framebuffer using the
    # configured dither strategy, then each pixel is split into planes:
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

      # Quantize through the full dither pipeline first, then split
      color_fb = render(canvas)
      black_fb = Framebuffer.new(canvas.width, canvas.height, PixelFormat::MONO)
      red_fb   = Framebuffer.new(canvas.width, canvas.height, PixelFormat::MONO)
      split_channels_from_fb(color_fb, black_fb, red_fb)
      [black_fb, red_fb]
    end

    private

    attr_reader :strategy

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

      unless into.pixel_format == pixel_format
        raise ArgumentError,
              "framebuffer pixel format #{into.pixel_format.name} " \
              "does not match renderer #{pixel_format.name}"
      end

      into
    end

    # Splits a pre-quantized COLOR4 Framebuffer into two MONO planes.
    #
    # Reads each pixel's palette name from the quantized framebuffer
    # and routes it to the appropriate MONO plane:
    # - +:black+ -- black plane gets 0 (black), red plane gets 1 (white)
    # - +:white+ -- black plane gets 1 (white), red plane gets 1 (white)
    # - +:red+ or +:yellow+ -- black plane gets 1 (white), red plane gets 0 (black)
    #
    # @param color_fb [Framebuffer] COLOR4 framebuffer (already quantized)
    # @param black_fb [Framebuffer] MONO framebuffer for the black plane
    # @param red_fb [Framebuffer] MONO framebuffer for the red plane
    def split_channels_from_fb(color_fb, black_fb, red_fb)
      color_fb.height.times do |y|
        color_fb.width.times do |x|
          route_dual_pixel(color_fb.get_pixel(x, y), black_fb, red_fb, x, y)
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
      else
        raise ArgumentError, "unexpected COLOR4 palette color: #{name.inspect}"
      end
    end
  end
end
