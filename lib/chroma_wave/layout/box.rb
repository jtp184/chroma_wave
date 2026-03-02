# frozen_string_literal: true

module ChromaWave
  class Layout
    # Mutable positioned rectangle written by {Calculator} and read by {Renderer}.
    #
    # Unlike the immutable +Data.define+ value objects, Box is intentionally
    # mutable because it is populated incrementally during the top-down layout
    # pass. The Calculator assigns coordinates and dimensions as it walks the
    # node tree.
    #
    # @example
    #   box = Box.new
    #   box.x = 10
    #   box.y = 20
    #   box.width = 100
    #   box.height = 50
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
