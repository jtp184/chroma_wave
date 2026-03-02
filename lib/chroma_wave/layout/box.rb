# frozen_string_literal: true

module ChromaWave
  class Layout
    # Immutable positioned rectangle representing a node's computed layout bounds.
    #
    # Created by the {Calculator} during the layout pass and stored
    # in an external position map (+{Node => Box}+), keeping nodes
    # free of mutable layout state.
    #
    # @example
    #   box = Box.new(x: 10, y: 20, width: 100, height: 50)
    #
    # @!attribute [r] x
    #   @return [Integer] left edge x coordinate
    # @!attribute [r] y
    #   @return [Integer] top edge y coordinate
    # @!attribute [r] width
    #   @return [Integer] box width in pixels
    # @!attribute [r] height
    #   @return [Integer] box height in pixels
    Box = Data.define(:x, :y, :width, :height) do
      def initialize(x: 0, y: 0, width: 0, height: 0)
        super
      end

      # Returns a human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} (#{x},#{y}) #{width}x#{height}>"
      end
    end
  end
end
