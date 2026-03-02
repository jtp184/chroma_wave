# frozen_string_literal: true

module ChromaWave
  class Layout
    # Shared behavior for leaf nodes whose intrinsic size comes from
    # a font measurement (text, icons, etc.).
    #
    # Including classes call {#init_measurable} during +initialize+,
    # passing a block that performs the measurement. The result is
    # memoized and exposed via {#metrics}, {#intrinsic_width}, and
    # {#intrinsic_height}.
    #
    # @example
    #   class TextContent < Node
    #     include MeasurableContent
    #
    #     def initialize(text:, font:, color:, **)
    #       super(**)
    #       @text = text
    #       init_measurable(font: font, color: color) { font.measure(text) }
    #     end
    #   end
    module MeasurableContent
      # @return [Font, IconFont] the font used for measurement
      attr_reader :font

      # @return [Color] the content color
      attr_reader :color

      # Memoized measurement result.
      #
      # The block passed to {#init_measurable} is called once and cached.
      #
      # @return [Font::Metrics, IconFont::Metrics] cached measurement
      def metrics
        @metrics ||= @measure.call
      end

      # @return [Integer] measured content width
      def intrinsic_width
        metrics.width
      end

      # @return [Integer] measured content height
      def intrinsic_height
        metrics.height
      end

      private

      # Stores font, color, and the measurement block.
      #
      # @param font [Font, IconFont] the font for rendering and measurement
      # @param color [Color] the content color
      # @yield computes the metrics (called lazily, once)
      def init_measurable(font:, color:, &measure)
        @font = font
        @color = color
        @measure = measure
      end
    end
  end
end
