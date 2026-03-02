# frozen_string_literal: true

module ChromaWave
  class Layout
    # Icon content leaf node.
    #
    # Renders a named icon from an {IconFont}.
    #
    # @example
    #   IconContent.new(name: :wifi, font: icon_font, color: Color::BLACK)
    class IconContent < Node
      include MeasurableContent

      # @return [Symbol] the icon name
      attr_reader :name

      # @param name [Symbol] icon name from the font's glyph map
      # @param font [IconFont] icon font for rendering
      # @param color [Color] icon color
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(name:, font:, color:, **)
        super(**)
        @name = name
        init_measurable(font: font, color: color) { font.measure_icon(name) }
      end

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} #{name.inspect} #{intrinsic_width}x#{intrinsic_height}>"
      end
    end
  end
end
