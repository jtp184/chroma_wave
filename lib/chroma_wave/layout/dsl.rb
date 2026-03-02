# frozen_string_literal: true

module ChromaWave
  class Layout
    # DSL interpreter that builds a node tree from a Ruby block.
    #
    # Uses +instance_eval+ to evaluate the block in the DSL context,
    # capturing method calls as node construction.
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
      # Container keyword arguments (styling).
      CONTAINER_KEYS = %i[padding gap background border border_width].freeze

      # Node keyword arguments (sizing/alignment).
      NODE_KEYS = %i[flex width height min_width min_height max_width max_height align valign].freeze

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
      # @param kwargs [Hash] node keyword arguments
      # @return [TextContent]
      def text(text, font:, color:, **kwargs)
        node_kwargs = extract_node_kwargs(kwargs)
        node = TextContent.new(text: text, font: font, color: color, **node_kwargs)
        children << node
        node
      end

      # Creates an icon content node.
      #
      # @param name [Symbol] icon name
      # @param font [IconFont] the icon font
      # @param color [Color] the icon color
      # @param kwargs [Hash] node keyword arguments
      # @return [IconContent]
      def icon(name, font:, color:, **kwargs)
        node_kwargs = extract_node_kwargs(kwargs)
        node = IconContent.new(name: name, font: font, color: color, **node_kwargs)
        children << node
        node
      end

      # Creates an image content node.
      #
      # @param source [Image] the source image
      # @param fit [Symbol] fit mode (:contain, :cover, :stretch)
      # @param kwargs [Hash] node keyword arguments
      # @return [ImageContent]
      def image(source, fit: :contain, **kwargs)
        node_kwargs = extract_node_kwargs(kwargs)
        node = ImageContent.new(source: source, fit: fit, **node_kwargs)
        children << node
        node
      end

      # Creates a spacer node (defaults to flex: 1).
      #
      # @param kwargs [Hash] node keyword arguments
      # @return [SpacerContent]
      def spacer(**kwargs)
        node_kwargs = extract_node_kwargs(kwargs)
        node = SpacerContent.new(**node_kwargs)
        children << node
        node
      end

      # Creates a canvas block node for custom drawing.
      #
      # @param kwargs [Hash] node keyword arguments
      # @yield [Layer] receives a Layer for custom drawing
      # @return [CanvasBlockContent]
      def canvas_block(**kwargs, &block)
        node_kwargs = extract_node_kwargs(kwargs)
        node = CanvasBlockContent.new(block: block, **node_kwargs)
        children << node
        node
      end

      private

      # Builds a container node with nested children from a DSL block.
      #
      # @param direction [:horizontal, :vertical] main axis
      # @param kwargs [Hash] container + node keyword arguments
      # @yield nested DSL block
      # @return [ContainerNode]
      def add_container(direction, **kwargs, &block)
        container_kwargs = extract_container_kwargs(kwargs)
        node_kwargs = extract_node_kwargs(kwargs)

        nested_children = block ? self.class.evaluate(&block) : []

        node = ContainerNode.new(
          direction: direction,
          children: nested_children,
          **container_kwargs,
          **node_kwargs
        )
        children << node
        node
      end

      # Extracts container-specific kwargs.
      #
      # @param kwargs [Hash] mixed keyword arguments
      # @return [Hash] container-only kwargs
      def extract_container_kwargs(kwargs)
        kwargs.slice(*CONTAINER_KEYS)
      end

      # Extracts node-specific kwargs.
      #
      # @param kwargs [Hash] mixed keyword arguments
      # @return [Hash] node-only kwargs
      def extract_node_kwargs(kwargs)
        kwargs.slice(*NODE_KEYS)
      end
    end
  end
end
