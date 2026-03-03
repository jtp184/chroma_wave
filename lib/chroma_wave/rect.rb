# frozen_string_literal: true

module ChromaWave
  # Immutable rectangle value type for region tracking.
  #
  # Built on +Data.define+ for automatic equality, freeze, and pattern matching.
  # Primarily used by dirty region tracking to represent bounding boxes.
  #
  # @example
  #   r1 = Rect.new(x: 0, y: 0, width: 10, height: 10)
  #   r2 = Rect.new(x: 5, y: 5, width: 10, height: 10)
  #   r1.union(r2) # => Rect(x: 0, y: 0, width: 15, height: 15)
  Rect = Data.define(:x, :y, :width, :height) do
    # Validates that width and height are non-negative after initialization.
    #
    # @raise [ArgumentError] if width or height is negative
    def initialize(x:, y:, width:, height:)
      raise ArgumentError, "width must be non-negative, got #{width}" if width.negative?
      raise ArgumentError, "height must be non-negative, got #{height}" if height.negative?

      super
    end

    # Returns the smallest rectangle that encloses both this rect and +other+.
    #
    # @param other [Rect] the other rectangle
    # @return [Rect] the bounding union
    def union(other)
      new_x = [x, other.x].min
      new_y = [y, other.y].min
      Rect.new(
        x: new_x,
        y: new_y,
        width: [x + width, other.x + other.width].max - new_x,
        height: [y + height, other.y + other.height].max - new_y
      )
    end
  end
end
