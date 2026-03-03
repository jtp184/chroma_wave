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
    # Accepts either a {Rect} or four positional arguments (x, y, width, height).
    #
    # @overload union(rect)
    #   @param rect [Rect] the other rectangle
    # @overload union(other_x, other_y, other_width, other_height)
    #   @param other_x [Integer] left edge
    #   @param other_y [Integer] top edge
    #   @param other_width [Integer] width
    #   @param other_height [Integer] height
    # @return [Rect] the bounding union
    def union(other_or_x, other_y = nil, other_w = nil, other_h = nil)
      if other_or_x.is_a?(Rect)
        other_x, other_y, other_w, other_h = other_or_x.deconstruct
      else
        if [other_y, other_w, other_h].any?(&:nil?)
          raise ArgumentError,
                'union requires a Rect or four positional arguments (x, y, width, height)'
        end
        other_x = other_or_x
      end

      new_x = [x, other_x].min
      new_y = [y, other_y].min
      Rect.new(
        x: new_x,
        y: new_y,
        width: [x + width, other_x + other_w].max - new_x,
        height: [y + height, other_y + other_h].max - new_y
      )
    end
  end
end
