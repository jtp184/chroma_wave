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

    # Returns true if the canvas has been modified since the last {#clean!}.
    #
    # @return [Boolean]
    def dirty?
      !@dirty_x.nil?
    end

    # Returns the bounding box of all modifications since the last {#clean!}.
    #
    # @return [Rect, nil] the dirty bounding box or nil if clean
    def dirty_region
      return nil unless @dirty_x

      Rect.new(x: @dirty_x, y: @dirty_y, width: @dirty_w, height: @dirty_h)
    end

    # Resets dirty tracking, marking the canvas as clean.
    #
    # @return [self]
    def clean!
      @dirty_x = @dirty_y = @dirty_w = @dirty_h = nil
      self
    end

    # Explicitly marks a rectangular region as dirty.
    #
    # Accepts either a {Rect} or keyword arguments.
    #
    # @param rect [Rect, nil] a Rect to mark dirty
    # @param x [Integer, nil] left edge
    # @param y [Integer, nil] top edge
    # @param width [Integer, nil] width
    # @param height [Integer, nil] height
    # @return [self]
    def mark_dirty(rect = nil, x: nil, y: nil, width: nil, height: nil)
      if rect
        expand_dirty(rect.x, rect.y, rect.width, rect.height)
      else
        unless x && y && width && height
          raise ArgumentError, 'mark_dirty requires a Rect or x:, y:, width:, height: keywords'
        end

        expand_dirty(x, y, width, height)
      end
      self
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

      buffer[pixel_offset(x, y), BYTES_PER_PIXEL] = color.to_rgba_bytes
      expand_dirty(x, y, 1, 1)
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
      expand_dirty(0, 0, width, height)
      self
    end

    # Copies pixels from +source+ onto this canvas with alpha compositing.
    #
    # Transparent pixels (alpha 0) are skipped, opaque pixels (alpha 255)
    # are copied directly, and semi-transparent pixels are blended using
    # source-over compositing.
    #
    # *Note:* The result alpha is always set to 255 (fully opaque). This is
    # correct for compositing onto an opaque background but will discard
    # destination alpha if the canvas was initialized with a transparent
    # background.
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
      mark_clipped_dirty(x, y, source.width, source.height)
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
      mark_clipped_dirty(x, y, width, height)
      self
    end

    # Returns the raw RGBA buffer as a frozen binary string.
    #
    # @return [String] the pixel data (4 bytes per pixel, row-major)
    def rgba_bytes
      buffer.dup.freeze
    end

    # Returns true if +other+ is a Canvas with the same dimensions and pixels.
    #
    # @param other [Object] the object to compare
    # @return [Boolean]
    def ==(other)
      other.is_a?(Canvas) &&
        width == other.width &&
        height == other.height &&
        buffer == other.raw_buffer
    end

    # Returns a hash code consistent with {#==} and {#eql?}.
    #
    # @return [Integer]
    def hash
      [self.class, width, height, buffer].hash
    end

    alias eql? ==

    # Returns a human-readable description of the canvas.
    #
    # @return [String]
    def inspect
      "#<#{self.class} #{width}x#{height}>"
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
    def layer(x:, y:, width:, height:)
      l = Layer.new(parent: self, x: x, y: y, width: width, height: height)
      if block_given?
        yield l
        self
      else
        l
      end
    end

    # Composites a glyph bitmap directly into the RGBA buffer via the C accelerator.
    #
    # Wraps the private +_canvas_blit_glyph+ C method in a public, keyword-arg
    # interface. Returns +true+ if the C path was used, +false+ if unavailable
    # so callers can fall back gracefully.
    #
    # @param bitmap [String] grayscale alpha bitmap (1 byte/pixel)
    # @param x [Integer] destination x in canvas coordinates
    # @param y [Integer] destination y in canvas coordinates
    # @param width [Integer] glyph bitmap width
    # @param height [Integer] glyph bitmap height
    # @param color [Color] foreground color for the glyph
    # @return [Boolean] true if C accelerator was used, false otherwise
    def blit_glyph(bitmap, x:, y:, width:, height:, color:) # rubocop:disable Naming/PredicateMethod
      return false unless respond_to?(:_canvas_blit_glyph, true)

      _canvas_blit_glyph(buffer, bitmap, x, y, width, height,
                         self.width, self.height,
                         color.r, color.g, color.b)
      expand_dirty(x, y, width, height)
      true
    end

    # Returns the raw RGBA buffer without copying.
    #
    # Unlike {#rgba_bytes}, which duplicates the buffer for safety, this
    # method returns a direct reference. Callers must not mutate the
    # returned string. Intended for read-only hot paths (e.g. dithering)
    # where copying 1+ MB of pixel data is wasteful.
    #
    # Also used for same-class peer comparison in {#==}.
    #
    # @return [String] the raw RGBA buffer (do not mutate)
    def raw_buffer
      @buffer
    end

    # Optimized fill_rect that writes scanline rows directly into the buffer.
    #
    # Clips the rectangle to canvas bounds, then writes one memcpy-style
    # row per scanline instead of per-pixel set_pixel calls.
    #
    # @param x [Integer] top-left x
    # @param y [Integer] top-left y
    # @param w [Integer] width
    # @param h [Integer] height
    # @param color [#to_rgba_bytes] fill color (any object responding to +to_rgba_bytes+)
    # @raise [TypeError] if +color+ does not respond to +to_rgba_bytes+
    def fill_rect(x, y, w, h, color)
      raise TypeError, "#{color.class} does not respond to #to_rgba_bytes" unless color.respond_to?(:to_rgba_bytes)

      # Clip to canvas bounds
      x0 = [x, 0].max
      y0 = [y, 0].max
      x1 = [x + w, width].min
      y1 = [y + h, height].min
      return if x0 >= x1 || y0 >= y1

      stamp = color.to_rgba_bytes
      row = stamp * (x1 - x0)

      (y0...y1).each do |row_y|
        offset = pixel_offset(x0, row_y)
        buffer[offset, row.bytesize] = row
      end

      expand_dirty(x0, y0, x1 - x0, y1 - y0)
    end

    private

    attr_reader :buffer

    # Deep-copies the pixel buffer and dirty state so dup/clone get independent data.
    #
    # @param source [Canvas] the canvas being copied
    def initialize_copy(source)
      super
      @buffer = source.raw_buffer.dup
      region = source.dirty_region
      if region
        @dirty_x = region.x
        @dirty_y = region.y
        @dirty_w = region.width
        @dirty_h = region.height
      else
        @dirty_x = @dirty_y = @dirty_w = @dirty_h = nil
      end
    end

    # Clips a rectangle to canvas bounds and marks it dirty.
    #
    # Used by +blit+ and +load_rgba_bytes+ where the source rect may
    # extend beyond canvas boundaries.
    #
    # @param src_x [Integer] left edge of the source rect
    # @param src_y [Integer] top edge of the source rect
    # @param src_w [Integer] width of the source rect
    # @param src_h [Integer] height of the source rect
    # @return [void]
    def mark_clipped_dirty(src_x, src_y, src_w, src_h)
      cx = [src_x, 0].max
      cy = [src_y, 0].max
      cw = [src_x + src_w, width].min - cx
      ch = [src_y + src_h, height].min - cy
      expand_dirty(cx, cy, cw, ch) if cw.positive? && ch.positive?
    end

    # Expands the dirty bounding box to include the given rectangle.
    #
    # Uses ternary operators instead of +[a, b].min/max+ to avoid
    # Array allocations on the hot path (called per-pixel in +set_pixel+).
    #
    # @param new_x [Integer] left edge of the new dirty area
    # @param new_y [Integer] top edge of the new dirty area
    # @param new_w [Integer] width of the new dirty area
    # @param new_h [Integer] height of the new dirty area
    # @return [void]
    # rubocop:disable Style/MinMaxComparison -- ternaries avoid Array allocs on hot path
    def expand_dirty(new_x, new_y, new_w, new_h)
      if @dirty_x
        right = new_x + new_w
        bottom = new_y + new_h
        old_right = @dirty_x + @dirty_w
        old_bottom = @dirty_y + @dirty_h
        @dirty_x = new_x < @dirty_x ? new_x : @dirty_x
        @dirty_y = new_y < @dirty_y ? new_y : @dirty_y
        @dirty_w = (right > old_right ? right : old_right) - @dirty_x
        @dirty_h = (bottom > old_bottom ? bottom : old_bottom) - @dirty_y
      else
        @dirty_x = new_x
        @dirty_y = new_y
        @dirty_w = new_w
        @dirty_h = new_h
      end
    end
    # rubocop:enable Style/MinMaxComparison

    # Byte offset for pixel (x, y) in the RGBA buffer.
    def pixel_offset(x, y)
      ((y * width) + x) * BYTES_PER_PIXEL
    end

    # C-accelerated glyph compositing. Blends directly into the RGBA
    # buffer with integer alpha math, avoiding per-pixel Color allocation.
    # Falls back to the pure-Ruby path when the C method is unavailable.
    def render_glyph(glyph, base_x, base_y, color)
      if respond_to?(:_canvas_blit_glyph, true)
        gx = base_x + glyph[:x]
        gy = base_y + glyph[:y]
        _canvas_blit_glyph(buffer, glyph[:bitmap],
                           gx, gy,
                           glyph[:width], glyph[:height],
                           width, height,
                           color.r, color.g, color.b)
        expand_dirty(gx, gy, glyph[:width], glyph[:height])
      else
        super
      end
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
  end
end
