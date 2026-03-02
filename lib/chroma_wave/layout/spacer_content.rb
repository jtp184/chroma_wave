# frozen_string_literal: true

module ChromaWave
  class Layout
    # Spacer content leaf node.
    #
    # Consumes flex space without rendering anything. Defaults to flex: 1.
    #
    # @example Push content to the right in a row
    #   row { text "left"; spacer; text "right" }
    class SpacerContent < Node
      # @param flex [Numeric] flex factor, defaults to 1
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(flex: 1, **)
        super
      end

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} flex=#{flex}>"
      end
    end
  end
end
