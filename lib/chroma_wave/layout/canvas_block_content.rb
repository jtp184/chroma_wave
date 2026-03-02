# frozen_string_literal: true

module ChromaWave
  class Layout
    # Canvas block content leaf node.
    #
    # Delegates rendering to a user-provided block that receives a {Layer}.
    # Intrinsic size is zero — the block occupies whatever space is allocated.
    #
    # @example Custom drawing
    #   CanvasBlockContent.new(block: ->(layer) { layer.draw_circle(10, 10, 5, pen: p) })
    class CanvasBlockContent < Node
      # @return [Proc] the drawing block
      attr_reader :block

      # @param block [Proc] receives a Layer for custom drawing
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(block:, **)
        super(**)
        @block = block
      end

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class}>"
      end
    end
  end
end
