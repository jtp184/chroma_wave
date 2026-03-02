# frozen_string_literal: true

module ChromaWave
  class Layout
    # Image content leaf node.
    #
    # Renders an image with optional fit mode (:contain, :cover, :stretch).
    #
    # @example
    #   ImageContent.new(source: image, fit: :contain)
    class ImageContent < Node
      # Valid image fit modes.
      FIT_MODES = %i[contain cover stretch].freeze

      # @return [Image] the source image
      attr_reader :source

      # @return [Symbol] fit mode (:contain, :cover, :stretch)
      attr_reader :fit

      # @param source [Image] source image
      # @param fit [Symbol] how to fit the image in the box
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(source:, fit: :contain, **)
        super(**)
        validate_fit!(fit)
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

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} #{intrinsic_width}x#{intrinsic_height} fit=#{fit}>"
      end

      private

      # @raise [ArgumentError] if fit is not a recognized mode
      def validate_fit!(fit)
        return if FIT_MODES.include?(fit)

        raise ArgumentError, "fit must be one of #{FIT_MODES.inspect}, got #{fit.inspect}"
      end
    end
  end
end
