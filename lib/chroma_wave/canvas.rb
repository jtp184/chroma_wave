# frozen_string_literal: true

module ChromaWave
  # RGBA pixel buffer for compositing content before rendering to hardware.
  #
  # Canvas stores pixels as a flat binary String of packed RGBA quads
  # (4 bytes per pixel, row-major). This keeps GC overhead minimal — only
  # two Ruby objects (the Canvas and its buffer String).
  #
  # Includes {Surface} for drawing protocol compatibility. Drawing primitives,
  # blit, and clear are all available.
  #
  # @example
  #   canvas = Canvas.new(width: 200, height: 100)
  #   canvas.set_pixel(10, 20, Color::RED)
  #   canvas.clear(Color::BLACK)
  class Canvas
    include Surface

    # Bytes per pixel in the RGBA buffer.
    BYTES_PER_PIXEL = 4

    attr_reader :width, :height

    # Creates a new Canvas filled with the given background color.
    #
    # @param width [Integer] canvas width in pixels (must be positive)
    # @param height [Integer] canvas height in pixels (must be positive)
    # @param background [Color] initial fill color (default: white opaque)
    # @raise [ArgumentError] if width or height is not a positive integer
    def initialize(width:, height:, background: Color::WHITE)
      validate_dimensions!(width, height)
      @width  = width
      @height = height
      @buffer = (background.to_rgba_bytes * (width * height)).b
    end

    # Sets the pixel at (x, y) to the given color.
    #
    # Out-of-bounds coordinates are silently ignored.
    #
    # @param x [Integer] x coordinate
    # @param y [Integer] y coordinate
    # @param color [Color] the color to set
    # @return [self]
    def set_pixel(x, y, color)
      return self unless in_bounds?(x, y)

      offset = pixel_offset(x, y)
      buffer[offset]     = color.r.chr
      buffer[offset + 1] = color.g.chr
      buffer[offset + 2] = color.b.chr
      buffer[offset + 3] = color.a.chr
      self
    end

    # Returns the color at (x, y).
    #
    # @param x [Integer] x coordinate
    # @param y [Integer] y coordinate
    # @return [Color, nil] the pixel color, or nil if out of bounds
    def get_pixel(x, y)
      return nil unless in_bounds?(x, y)

      Color.from_rgba_bytes(buffer.byteslice(pixel_offset(x, y), BYTES_PER_PIXEL))
    end

    # Fills the entire canvas with the given color.
    #
    # Uses a C accelerator when available, falling back to Ruby.
    #
    # @param color [Color] the fill color (default: white opaque)
    # @return [self]
    def clear(color = Color::WHITE)
      if respond_to?(:_canvas_clear, true)
        _canvas_clear(buffer, color.r, color.g, color.b, color.a)
      else
        clear_ruby(color)
      end
      self
    end

    # Copies pixels from +source+ onto this canvas with alpha compositing.
    #
    # Transparent pixels (alpha 0) are skipped, opaque pixels (alpha 255)
    # are copied directly, and semi-transparent pixels are blended using
    # source-over compositing.
    #
    # Uses a C accelerator when available.
    #
    # @param source [Surface] the source surface
    # @param x [Integer] destination x offset
    # @param y [Integer] destination y offset
    # @return [self]
    def blit(source, x:, y:)
      if source.is_a?(Canvas) && respond_to?(:_canvas_blit_alpha, true)
        _canvas_blit_alpha(buffer, source.rgba_bytes, x, y,
                           source.width, source.height, width, height)
      else
        blit_ruby(source, x, y)
      end
      self
    end

    # Bulk-loads raw RGBA bytes into a rectangular region of the canvas.
    #
    # Uses a C accelerator when available.
    #
    # @param bytes [String] raw RGBA pixel data
    # @param width [Integer] source width in pixels
    # @param height [Integer] source height in pixels
    # @param x [Integer] destination x offset
    # @param y [Integer] destination y offset
    # @return [self]
    def load_rgba_bytes(bytes, width:, height:, x:, y:)
      if respond_to?(:_canvas_load_rgba, true)
        _canvas_load_rgba(buffer, bytes, x, y, width, height, self.width)
      else
        load_rgba_bytes_ruby(bytes, width, height, x, y)
      end
      self
    end

    # Returns the raw RGBA buffer as a frozen binary string.
    #
    # @return [String] the pixel data (4 bytes per pixel, row-major)
    def rgba_bytes
      buffer.dup.freeze
    end

    # Creates a {Layer} scoped to a rectangular sub-region of this canvas.
    #
    # If a block is given, yields the layer and returns self for chaining.
    #
    # @param x [Integer] sub-region x offset
    # @param y [Integer] sub-region y offset
    # @param width [Integer] sub-region width
    # @param height [Integer] sub-region height
    # @yield [Layer] the created layer (optional)
    # @return [Layer, self] the layer, or self if a block was given
    def layer(x:, y:, width:, height:, &block)
      l = Layer.new(parent: self, x: x, y: y, width: width, height: height)
      if block
        block.call(l)
        self
      else
        l
      end
    end

    private

    attr_reader :buffer

    # Computes the byte offset for pixel (x, y).
    #
    # @param x [Integer] x coordinate
    # @param y [Integer] y coordinate
    # @return [Integer] byte offset into the buffer
    def pixel_offset(x, y)
      ((y * width) + x) * BYTES_PER_PIXEL
    end

    # Ruby fallback for clear.
    #
    # @param color [Color] the fill color
    def clear_ruby(color)
      stamp = color.to_rgba_bytes
      pixel_count = width * height
      buffer.replace(stamp * pixel_count)
    end

    # Ruby fallback for alpha-composited blit.
    #
    # @param source [Surface] the source surface
    # @param ox [Integer] destination x offset
    # @param oy [Integer] destination y offset
    def blit_ruby(source, ox, oy)
      source.height.times do |sy|
        dy = oy + sy
        next if dy.negative? || dy >= height

        source.width.times do |sx|
          dx = ox + sx
          next if dx.negative? || dx >= width

          src_color = source.get_pixel(sx, sy)
          next if src_color.nil? || src_color.transparent?

          if src_color.opaque?
            set_pixel(dx, dy, src_color)
          else
            dst_color = get_pixel(dx, dy)
            set_pixel(dx, dy, src_color.over(dst_color))
          end
        end
      end
    end

    # Ruby fallback for bulk RGBA load.
    #
    # @param bytes [String] raw RGBA data
    # @param src_w [Integer] source width
    # @param src_h [Integer] source height
    # @param ox [Integer] destination x offset
    # @param oy [Integer] destination y offset
    def load_rgba_bytes_ruby(bytes, src_w, src_h, ox, oy)
      src_row_bytes = src_w * BYTES_PER_PIXEL
      src_h.times do |sy|
        dy = oy + sy
        next if dy.negative? || dy >= height

        dx_start = [0, -ox].max
        dx_end   = [src_w, width - ox].min
        next if dx_start >= dx_end

        src_offset = (sy * src_row_bytes) + (dx_start * BYTES_PER_PIXEL)
        dst_offset = pixel_offset(ox + dx_start, dy)
        copy_len   = (dx_end - dx_start) * BYTES_PER_PIXEL

        buffer[dst_offset, copy_len] = bytes.byteslice(src_offset, copy_len)
      end
    end

    # Validates that dimensions are positive integers.
    #
    # @param w [Object] width to validate
    # @param h [Object] height to validate
    # @raise [ArgumentError] if either is not a positive integer
    def validate_dimensions!(w, h)
      raise ArgumentError, 'width must be a positive Integer' unless w.is_a?(Integer) && w.positive?
      raise ArgumentError, 'height must be a positive Integer' unless h.is_a?(Integer) && h.positive?
    end
  end
end
