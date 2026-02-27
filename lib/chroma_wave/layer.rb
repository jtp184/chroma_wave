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

    attr_reader :width, :height

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

    private

    attr_reader :parent, :offset_x, :offset_y
  end
end
