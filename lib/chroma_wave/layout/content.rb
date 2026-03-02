# frozen_string_literal: true

module ChromaWave
  class Layout
    # Text content leaf node.
    #
    # Renders text with font measurement for intrinsic sizing.
    # Supports alignment and vertical alignment within the allocated box.
    #
    # @example
    #   TextContent.new(text: "Hello", font: font, color: Color::BLACK)
    class TextContent < Node
      # @return [String] the text to render
      attr_reader :text

      # @return [Font] the font for rendering and measurement
      attr_reader :font

      # @return [Color] the text color
      attr_reader :color

      # @param text [String] text content
      # @param font [Font] font for rendering
      # @param color [Color] text color
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(text:, font:, color:, **)
        super(**)
        @text = text
        @font = font
        @color = color
      end

      # @return [Integer] measured text width
      def intrinsic_width
        font.measure(text).width
      end

      # @return [Integer] measured text height
      def intrinsic_height
        font.measure(text).height
      end
    end

    # Icon content leaf node.
    #
    # Renders a named icon from an {IconFont}.
    #
    # @example
    #   IconContent.new(name: :wifi, font: icon_font, color: Color::BLACK)
    class IconContent < Node
      # @return [Symbol] the icon name
      attr_reader :name

      # @return [IconFont] the icon font
      attr_reader :font

      # @return [Color] the icon color
      attr_reader :color

      # @param name [Symbol] icon name from the font's glyph map
      # @param font [IconFont] icon font for rendering
      # @param color [Color] icon color
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(name:, font:, color:, **)
        super(**)
        @name = name
        @font = font
        @color = color
      end

      # @return [Integer] measured icon width
      def intrinsic_width
        font.measure_icon(name).width
      end

      # @return [Integer] measured icon height
      def intrinsic_height
        font.measure_icon(name).height
      end
    end

    # Image content leaf node.
    #
    # Renders an image with optional fit mode (:contain, :cover, :stretch).
    #
    # @example
    #   ImageContent.new(source: image, fit: :contain)
    class ImageContent < Node
      # @return [Image] the source image
      attr_reader :source

      # @return [Symbol] fit mode (:contain, :cover, :stretch)
      attr_reader :fit

      # @param source [Image] source image
      # @param fit [Symbol] how to fit the image in the box
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(source:, fit: :contain, **)
        super(**)
        @source = source
        @fit = fit
      end

      # @return [Integer] source image width
      def intrinsic_width
        source.width
      end

      # @return [Integer] source image height
      def intrinsic_height
        source.height
      end
    end

    # Spacer content leaf node.
    #
    # Consumes flex space without rendering anything. Defaults to flex: 1.
    #
    # @example Push content to the right in a row
    #   row { text "left"; spacer; text "right" }
    class SpacerContent < Node
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(**kwargs)
        kwargs[:flex] ||= 1
        super
      end
    end

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
    end
  end
end
