# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds region-limited display refresh to a Display subclass.
    #
    # Regional refresh updates only a rectangular sub-area of the screen,
    # setting a RAM address window and sending only the pixel data for
    # the sub-rectangle. X coordinates are automatically aligned to 8-pixel
    # byte boundaries (the actual refreshed region may be slightly wider
    # than requested).
    #
    # Supported controller families:
    # - SSD1680/SSD1677 (0x44/0x45/0x4E/0x4F window commands)
    # - UC8179 (0x90/0x91/0x92 partial-in/out commands)
    module RegionalRefresh
      # Displays a framebuffer within a rectangular sub-region of the screen.
      #
      # X and width are automatically aligned to 8-pixel byte boundaries.
      # The framebuffer must be full-screen sized; only the region pixels
      # are sent to the display controller.
      #
      # @param framebuffer [Framebuffer] the full-screen framebuffer
      # @param x [Integer] left edge of the region (aligned down to 8px)
      # @param y [Integer] top edge of the region
      # @param width [Integer] region width in pixels (aligned up to 8px)
      # @param height [Integer] region height in pixels
      # @return [self]
      # @raise [ArgumentError] if the region exceeds display bounds
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_region(framebuffer, x:, y:, width:, height:)
        validate_framebuffer!(framebuffer)
        validate_region!(x, y, width, height)
        aligned_x, aligned_w = align_x_to_byte_boundary(x, width)
        ensure_initialized!
        synchronize_device do
          device.send(:_epd_display_region, framebuffer,
                      aligned_x, y, aligned_w, height)
        end
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

      # Aligns X coordinate and width to 8-pixel byte boundaries.
      #
      # Floors X to the nearest lower multiple of 8, and ceils the end
      # (X + width) to the nearest higher multiple of 8. Clamps the
      # result to the display width.
      #
      # @param x [Integer] original X coordinate
      # @param w [Integer] original width
      # @return [Array(Integer, Integer)] aligned [x, width]
      def align_x_to_byte_boundary(x, w)
        aligned_x = x & ~7 # floor to 8px
        aligned_end = ((x + w + 7) & ~7) # ceil end to 8px
        aligned_end = [aligned_end, width].min # clamp to display
        [aligned_x, aligned_end - aligned_x]
      end
    end
  end
end
