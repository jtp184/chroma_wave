# frozen_string_literal: true

module ChromaWave
  class Layout
    # Positioned rectangle representing a node's computed layout bounds.
    #
    # Created by the {Calculator} during the layout pass and stored
    # in an external position map (+{Node => Box}+), keeping nodes
    # free of mutable layout state.
    #
    # @example
    #   box = Box.new(x: 10, y: 20, width: 100, height: 50)
    class Box
      attr_accessor :x, :y, :width, :height

      # Creates a new unpositioned Box.
      #
      # @param x [Integer] left edge x coordinate
      # @param y [Integer] top edge y coordinate
      # @param width [Integer] box width in pixels
      # @param height [Integer] box height in pixels
      def initialize(x: 0, y: 0, width: 0, height: 0)
        @x = x
        @y = y
        @width = width
        @height = height
      end

      # Returns a human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} (#{x},#{y}) #{width}x#{height}>"
      end

      # Value equality based on all four attributes.
      #
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(Box) &&
          x == other.x && y == other.y &&
          width == other.width && height == other.height
      end

      alias eql? ==

      # @return [Integer]
      def hash
        [self.class, x, y, width, height].hash
      end
    end
  end
end
