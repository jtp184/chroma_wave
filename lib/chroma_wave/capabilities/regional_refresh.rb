# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds region-limited display refresh to a Display subclass.
    #
    # Regional refresh updates only a rectangular sub-area of the screen.
    # Currently falls back to a full-screen display as a forward-compatible
    # placeholder; model-specific region commands will be added later.
    module RegionalRefresh
      # Displays a framebuffer within a rectangular sub-region of the screen.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @param x [Integer] left edge of the region
      # @param y [Integer] top edge of the region
      # @param width [Integer] region width in pixels
      # @param height [Integer] region height in pixels
      # @return [self]
      # @raise [ArgumentError] if the region exceeds display bounds
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_region(framebuffer, x:, y:, width:, height:)
        validate_framebuffer!(framebuffer)
        validate_region!(x, y, width, height)
        ensure_initialized!
        # Regional refresh is model-specific; for now, fall back to full display
        synchronize_device { device.send(:_epd_display, framebuffer) }
        self
      end

      private

      # Validates that the given region fits within the display bounds.
      #
      # @param x [Integer] left edge
      # @param y [Integer] top edge
      # @param w [Integer] region width
      # @param h [Integer] region height
      # @raise [ArgumentError] if any coordinate is out of bounds
      def validate_region!(x, y, w, h)
        max_w = width
        max_h = height
        raise ArgumentError, 'region width must be positive' unless w.positive?
        raise ArgumentError, 'region height must be positive' unless h.positive?
        raise ArgumentError, "region x (#{x}) out of bounds" unless x >= 0 && x < max_w
        raise ArgumentError, "region y (#{y}) out of bounds" unless y >= 0 && y < max_h
        raise ArgumentError, 'region width exceeds display' unless x + w <= max_w
        raise ArgumentError, 'region height exceeds display' unless y + h <= max_h
      end
    end
  end
end
