# frozen_string_literal: true

module ChromaWave
  class Layout
    # DSL interpreter that builds a node tree from a Ruby block.
    #
    # Uses +instance_eval+ to evaluate the block in the DSL context,
    # capturing method calls as node construction. Unknown keyword
    # arguments raise +ArgumentError+ via the node constructors.
    #
    # @example
    #   children = DSL.evaluate {
    #     row(gap: 10) {
    #       text "Hello", font: f, color: c
    #       spacer
    #       text "World", font: f, color: c
    #     }
    #   }
    class DSL
      # Evaluates a block in DSL context and returns the resulting children.
      #
      # @yield the DSL block to evaluate
      # @return [Array<Node>] the top-level child nodes
      def self.evaluate(&)
        dsl = new
        dsl.instance_eval(&)
        dsl.children
      end

      # @return [Array<Node>] accumulated child nodes
      attr_reader :children

      def initialize
        @children = []
      end

      # Creates a horizontal container (row).
      #
      # @param kwargs [Hash] container and node keyword arguments
      # @yield nested DSL block for children
      # @return [ContainerNode]
      def row(**, &)
        add_container(:horizontal, **, &)
      end

      # Creates a vertical container (column).
      #
      # @param kwargs [Hash] container and node keyword arguments
      # @yield nested DSL block for children
      # @return [ContainerNode]
      def column(**, &)
        add_container(:vertical, **, &)
      end

      # Alias for {#row} — creates a horizontal container.
      alias columns row

      # Alias for {#column} — creates a vertical container.
      alias rows column

      # Creates a text content node.
      #
      # @param text [String] the text to display
      # @param font [Font] the font for rendering
      # @param color [Color] the text color
      # @param kwargs [Hash] node keyword arguments (flex, width, align, etc.)
      # @return [TextContent]
      def text(text, font:, color:, **)
        add_leaf(TextContent, text: text, font: font, color: color, **)
      end

      # Creates an icon content node.
      #
      # @param name [Symbol] icon name
      # @param font [IconFont] the icon font
      # @param color [Color] the icon color
      # @param kwargs [Hash] node keyword arguments (flex, width, align, etc.)
      # @return [IconContent]
      def icon(name, font:, color:, **)
        add_leaf(IconContent, name: name, font: font, color: color, **)
      end

      # Creates an image content node.
      #
      # @param source [Image] the source image
      # @param fit [Symbol] fit mode (:contain, :cover, :stretch)
      # @param kwargs [Hash] node keyword arguments (flex, width, align, etc.)
      # @return [ImageContent]
      def image(source, fit: :contain, **)
        add_leaf(ImageContent, source: source, fit: fit, **)
      end

      # Creates a spacer node (defaults to flex: 1).
      #
      # @param kwargs [Hash] node keyword arguments (flex, width, etc.)
      # @return [SpacerContent]
      def spacer(**)
        add_leaf(SpacerContent, **)
      end

      # Creates a canvas block node for custom drawing.
      #
      # @param kwargs [Hash] node keyword arguments (flex, width, etc.)
      # @yield [Layer] receives a Layer for custom drawing
      # @return [CanvasBlockContent]
      def canvas_block(**, &block)
        add_leaf(CanvasBlockContent, block: block, **)
      end

      private

      # Builds a container node with nested children from a DSL block.
      #
      # Keyword arguments are forwarded directly to {ContainerNode} and
      # then to {Node}, so unknown keys raise +ArgumentError+.
      #
      # @param direction [:horizontal, :vertical] main axis
      # @param kwargs [Hash] container + node keyword arguments
      # @yield nested DSL block
      # @return [ContainerNode]
      def add_container(direction, **, &block)
        nested_children = block ? self.class.evaluate(&block) : []
        node = ContainerNode.new(direction: direction, children: nested_children, **)
        children << node
        node
      end

      # Builds a leaf node and appends it to the children list.
      #
      # Keyword arguments are forwarded directly to the node class,
      # so unknown keys raise +ArgumentError+.
      #
      # @param klass [Class] the node class to instantiate
      # @param kwargs [Hash] constructor keyword arguments
      # @return [Node]
      def add_leaf(klass, **)
        node = klass.new(**)
        children << node
        node
      end
    end
  end
end
