# frozen_string_literal: true

module ChromaWave
  # A clipped sub-region of a parent {Surface}.
  #
  # Layer translates local coordinates to parent coordinates, providing
  # an isolated drawing context that cannot exceed its declared bounds.
  # Layers compose — a Layer of a Layer works via additive offsets.
  #
  # @example
  #   canvas = Canvas.new(width: 200, height: 100)
  #   layer = Layer.new(parent: canvas, x: 10, y: 10, width: 50, height: 30)
  #   layer.set_pixel(0, 0, Color::RED)  # writes to canvas(10, 10)
  class Layer
    include Surface

    attr_reader :width, :height, :offset_x, :offset_y

    # Creates a new Layer scoped to a sub-region of the parent surface.
    #
    # @param parent [Surface] the parent surface to delegate to
    # @param x [Integer] parent x offset
    # @param y [Integer] parent y offset
    # @param width [Integer] layer width in pixels
    # @param height [Integer] layer height in pixels
    def initialize(parent:, x:, y:, width:, height:)
      validate_dimensions!(width, height)
      @parent   = parent
      @offset_x = x
      @offset_y = y
      @width    = width
      @height   = height
    end

    # Returns a human-readable description of the layer.
    #
    # @return [String]
    def inspect
      "#<#{self.class} #{width}x#{height} at (#{offset_x},#{offset_y})>"
    end

    # Sets the pixel at local (x, y) on the parent surface.
    #
    # Out-of-bounds coordinates (relative to the Layer) are silently ignored.
    #
    # @param x [Integer] local x coordinate
    # @param y [Integer] local y coordinate
    # @param color [Object] the color to set
    # @return [self]
    def set_pixel(x, y, color)
      return self unless in_bounds?(x, y)

      parent.set_pixel(offset_x + x, offset_y + y, color)
      self
    end

    # Returns the pixel at local (x, y) from the parent surface.
    #
    # @param x [Integer] local x coordinate
    # @param y [Integer] local y coordinate
    # @return [Object, nil] the pixel color, or nil if out of bounds
    def get_pixel(x, y)
      return nil unless in_bounds?(x, y)

      parent.get_pixel(offset_x + x, offset_y + y)
    end

    # Bulk-loads raw RGBA bytes into a rectangular sub-region of the layer.
    #
    # Clips the source rectangle to this layer's bounds before delegating
    # to the parent, enforcing the same clipping contract as +set_pixel+.
    # Out-of-bounds regions are silently discarded.
    #
    # @param bytes [String] raw RGBA pixel data
    # @param width [Integer] source width in pixels
    # @param height [Integer] source height in pixels
    # @param x [Integer] local x offset
    # @param y [Integer] local y offset
    # @return [self]
    def load_rgba_bytes(bytes, width:, height:, x:, y:)
      clip = clip_rect(x, y, width, height)
      return self unless clip

      cx, cy, cw, ch = clip
      clipped_bytes = cw == width && ch == height ? bytes : clip_rgba_bytes(bytes, width, cx - x, cy - y, cw, ch)
      parent.load_rgba_bytes(clipped_bytes, width: cw, height: ch,
                                            x: offset_x + cx, y: offset_y + cy)
      self
    end

    # Fills the layer region with the given color.
    #
    # Delegates to the parent's +fill_rect+, which writes scanline rows
    # directly into the buffer when the parent is a Canvas, or falls back
    # to the per-pixel Primitives implementation for other Surface types.
    #
    # @param color [Object] a color understood by the parent's +set_pixel+
    # @return [self]
    def clear(color)
      parent.fill_rect(offset_x, offset_y, width, height, color)
      self
    end

    private

    attr_reader :parent

    # Clips a rectangle to this layer's bounds.
    #
    # @param x [Integer] left edge
    # @param y [Integer] top edge
    # @param w [Integer] width
    # @param h [Integer] height
    # @return [Array(Integer,Integer,Integer,Integer), nil] clipped (x, y, w, h) or nil if fully outside
    def clip_rect(x, y, w, h)
      x0 = [x, 0].max
      y0 = [y, 0].max
      x1 = [x + w, width].min
      y1 = [y + h, height].min
      return nil if x0 >= x1 || y0 >= y1

      [x0, y0, x1 - x0, y1 - y0]
    end

    # Extracts a clipped sub-rectangle of RGBA bytes from a source buffer.
    #
    # @param bytes [String] raw RGBA source data
    # @param src_width [Integer] full source width in pixels
    # @param sx [Integer] source x offset to start copying from
    # @param sy [Integer] source y offset to start copying from
    # @param clip_w [Integer] clipped width in pixels
    # @param clip_h [Integer] clipped height in pixels
    # @return [String] the extracted RGBA bytes for the clipped region
    def clip_rgba_bytes(bytes, src_width, sx, sy, clip_w, clip_h)
      bpp = Canvas::BYTES_PER_PIXEL
      src_stride = src_width * bpp
      row_bytes = clip_w * bpp

      String.new(capacity: row_bytes * clip_h, encoding: Encoding::BINARY).tap do |out|
        clip_h.times do |i|
          offset = ((sy + i) * src_stride) + (sx * bpp)
          out << bytes.byteslice(offset, row_bytes)
        end
      end
    end

    # Alpha-composites a glyph bitmap via the parent's C accelerator when possible.
    #
    # Delegates to +parent.blit_glyph+ with translated coordinates when the
    # entire glyph fits within Layer bounds. Falls back to the per-pixel Ruby
    # path for partial-overlap glyphs or when the parent lacks +blit_glyph+.
    #
    # @param glyph [Hash] glyph data from Font#each_glyph
    # @param base_x [Integer] line start x in local coordinates
    # @param base_y [Integer] line start y in local coordinates
    # @param color [Color] text foreground color
    def render_glyph(glyph, base_x, base_y, color)
      return super unless parent.respond_to?(:blit_glyph)

      gx = base_x + glyph[:x]
      gy = base_y + glyph[:y]
      gw = glyph[:width]
      gh = glyph[:height]

      if gx >= 0 && gy >= 0 && (gx + gw) <= width && (gy + gh) <= height &&
         parent.blit_glyph(glyph[:bitmap],
                           x: offset_x + gx, y: offset_y + gy,
                           width: gw, height: gh, color: color)
        return
      end

      super
    end
  end
end
