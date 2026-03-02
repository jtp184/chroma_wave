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

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} #{name.inspect} #{intrinsic_width}x#{intrinsic_height}>"
      end

      # Memoized icon measurement.
      #
      # @return [IconFont::Metrics] cached measurement result
      def metrics
        @metrics ||= font.measure_icon(name)
      end

      # @return [Integer] measured icon width
      def intrinsic_width
        metrics.width
      end

      # @return [Integer] measured icon height
      def intrinsic_height
        metrics.height
      end
    end
  end
end
