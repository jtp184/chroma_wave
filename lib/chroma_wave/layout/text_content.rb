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

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} #{text.inspect} #{intrinsic_width}x#{intrinsic_height}>"
      end

      # Memoized font measurement for the text content.
      #
      # @return [Font::Metrics] cached measurement result
      def metrics
        @metrics ||= font.measure(text)
      end

      # @return [Integer] measured text width
      def intrinsic_width
        metrics.width
      end

      # @return [Integer] measured text height
      def intrinsic_height
        metrics.height
      end
    end
  end
end
