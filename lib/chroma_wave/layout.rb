# frozen_string_literal: true

require_relative 'layout/padding'
require_relative 'layout/constraints'
require_relative 'layout/box'
require_relative 'layout/node'
require_relative 'layout/container_node'
require_relative 'layout/text_content'
require_relative 'layout/icon_content'
require_relative 'layout/image_content'
require_relative 'layout/spacer_content'
require_relative 'layout/canvas_block_content'
require_relative 'layout/dsl'
require_relative 'layout/alignment'
require_relative 'layout/calculator'
require_relative 'layout/renderer'

module ChromaWave
  # Declarative layout DSL for composing e-paper display content.
  #
  # Users describe UI layouts with Ruby blocks (+row+, +column+, +text+,
  # +spacer+, etc.) and the system builds a node tree, computes positions
  # via a two-pass flex algorithm, and renders to a {Canvas}.
  #
  # @example Simple status bar
  #   layout = Layout.build(width: 250, height: 122) {
  #     row(padding: 5, gap: 10) {
  #       text "Hello", font: font, color: Color::BLACK
  #       spacer
  #       text "World", font: font, color: Color::BLACK
  #     }
  #   }
  #   canvas = layout.render
  #   display.show(canvas)
  #
  # @example Nested layout
  #   Layout.build(width: 200, height: 200, background: Color::WHITE) {
  #     column(padding: 10, gap: 5) {
  #       row(flex: 1, gap: 10) {
  #         text "Left", font: f, color: c
  #         spacer
  #         text "Right", font: f, color: c
  #       }
  #       row(flex: 2, background: Color::LIGHT_GRAY) {
  #         text "Body", font: f, color: c, align: :center
  #       }
  #     }
  #   }
  class Layout
    # @return [Integer] layout width in pixels
    attr_reader :width

    # @return [Integer] layout height in pixels
    attr_reader :height

    # @return [ContainerNode] the root node of the layout tree
    attr_reader :root

    # Builds a layout from a DSL block.
    #
    # Wraps children in an implicit root column. The root column fills
    # the entire layout area and applies the given background color.
    #
    # @param width [Integer] layout width in pixels
    # @param height [Integer] layout height in pixels
    # @param background [Color] root background color
    # @yield DSL block for defining layout content
    # @return [Layout]
    def self.build(width:, height:, background: Color::WHITE, &)
      children = DSL.evaluate(&)
      root = ContainerNode.new(
        direction: :vertical,
        children: children,
        background: background
      )
      new(width: width, height: height, root: root)
    end

    # Creates a new Layout instance.
    #
    # @param width [Integer] layout width
    # @param height [Integer] layout height
    # @param root [ContainerNode] root node
    def initialize(width:, height:, root:)
      @width = width
      @height = height
      @root = root
    end

    # Computes layout and renders the tree to a new Canvas.
    #
    # The node tree is not mutated — positions are computed externally
    # by the {Calculator} and passed to the {Renderer} as a position map.
    #
    # @return [Canvas] the rendered canvas
    def render
      positions = Calculator.new(root: root, width: width, height: height).compute
      canvas = Canvas.new(width: width, height: height)
      Renderer.new(canvas, positions).render(root)
      canvas
    end

    # Human-readable description.
    #
    # @return [String]
    def inspect
      "#<#{self.class} #{width}x#{height}>"
    end
  end
end
