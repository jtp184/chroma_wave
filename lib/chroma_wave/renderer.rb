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
    # Reads the raw packed bytes from the COLOR4 framebuffer and extracts
    # nibbles directly, avoiding per-pixel get_pixel/symbol resolution
    # overhead. Uses a pre-built routing table mapping each 4-bit color
    # index to [black_value, red_value] pairs:
    #
    # - index 0 (:black)  -- black_fb=:black, red_fb=:white
    # - index 1 (:white)  -- black_fb=:white, red_fb=:white
    # - index 2 (:yellow) -- black_fb=:white, red_fb=:black
    # - index 3 (:red)    -- black_fb=:white, red_fb=:black
    #
    # @param color_fb [Framebuffer] COLOR4 framebuffer (already quantized)
    # @param black_fb [Framebuffer] MONO framebuffer for the black plane
    # @param red_fb [Framebuffer] MONO framebuffer for the red plane
    def split_channels_from_fb(color_fb, black_fb, red_fb)
      raw = color_fb.bytes
      width = color_fb.width
      route = build_dual_route_table

      color_fb.height.times do |y|
        width.times do |x|
          byte_idx = (x / 2) + (y * ((width + 1) / 2))
          nibble = if x.even?
                     (raw.getbyte(byte_idx) >> 4) & 0x0F
                   else
                     raw.getbyte(byte_idx) & 0x0F
                   end

          black_val, red_val = route[nibble]
          black_fb.set_pixel(x, y, black_val)
          red_fb.set_pixel(x, y, red_val)
        end
      end
    end

    # Builds a routing table mapping COLOR4 palette indices to dual-buffer values.
    #
    # Each entry is a frozen [black_value, red_value] pair of symbols suitable
    # for passing to MONO framebuffer set_pixel.
    #
    # @return [Array<Array(Symbol, Symbol)>] indexed by COLOR4 palette integer
    def build_dual_route_table
      palette = PixelFormat::COLOR4.palette
      palette.map { |name| route_for_color(name).freeze }.freeze
    end

    # Returns the [black_value, red_value] pair for a given COLOR4 color name.
    #
    # @param name [Symbol] the COLOR4 palette color name
    # @return [Array(Symbol, Symbol)] black and red plane values
    # @raise [ArgumentError] if the name is not a recognized COLOR4 color
    def route_for_color(name)
      case name
      when :black         then [:black, :white]
      when :white         then [:white, :white]
      when :red, :yellow  then [:white, :black]
      else raise ArgumentError, "unexpected COLOR4 palette color: #{name.inspect}"
      end
    end
  end
end
