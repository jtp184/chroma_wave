# frozen_string_literal: true

module ChromaWave
  # Protocol module for any drawable pixel surface.
  #
  # Includers must provide +set_pixel(x, y, color)+, +get_pixel(x, y)+,
  # +width+, and +height+. Surface supplies common operations built on top
  # of those four primitives: bounds checking, bulk clear, and pixel-copy blit.
  #
  # Canvas and Framebuffer both include this module. Layer includes it
  # transitively and adds coordinate translation.
  module Surface
    # Returns true if the given coordinates are within the surface bounds.
    #
    # @param x [Integer] x coordinate
    # @param y [Integer] y coordinate
    # @return [Boolean]
    def in_bounds?(x, y)
      x >= 0 && x < width && y >= 0 && y < height
    end

    # Fills every pixel with +color+.
    #
    # The default implementation loops pixel-by-pixel. Framebuffer and Canvas
    # override this with optimized bulk operations.
    #
    # @param color [Object] a color understood by the includer's +set_pixel+
    # @return [self]
    def clear(color)
      height.times do |y|
        width.times { |x| set_pixel(x, y, color) }
      end
      self
    end

    # Copies pixels from +source+ onto this surface at the given offset.
    #
    # The default implementation does a simple pixel-by-pixel copy with
    # bounds clipping. +nil+ pixels from the source are skipped (transparent
    # pass-through). Canvas overrides this with alpha compositing.
    #
    # @param source [Surface] the surface to copy from
    # @param x [Integer] destination x offset
    # @param y [Integer] destination y offset
    # @return [self]
    def blit(source, x:, y:)
      source.height.times do |sy|
        dy = y + sy
        next if dy.negative? || dy >= height

        source.width.times do |sx|
          dx = x + sx
          next if dx.negative? || dx >= width

          pixel = source.get_pixel(sx, sy)
          set_pixel(dx, dy, pixel) unless pixel.nil?
        end
      end
      self
    end
  end
end
