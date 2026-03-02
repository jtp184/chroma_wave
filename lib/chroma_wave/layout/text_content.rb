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
      include MeasurableContent

      # @return [String] the text to render
      attr_reader :text

      # @param text [String] text content
      # @param font [Font] font for rendering
      # @param color [Color] text color
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(text:, font:, color:, **)
        super(**)
        @text = text
        init_measurable(font: font, color: color) { font.measure(text) }
      end

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} #{text.inspect} #{intrinsic_width}x#{intrinsic_height}>"
      end
    end
  end
end
