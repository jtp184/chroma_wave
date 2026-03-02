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
      # Coordinates and dimensions are in logical space (respecting the
      # display's rotation). Only the sub-region pixels are extracted and
      # rotated to native orientation -- the full framebuffer is never
      # rotated, making this efficient for small regions on large displays.
      #
      # X and width are automatically aligned to 8-pixel byte boundaries
      # in native space (the actual refreshed region may be slightly wider
      # than requested).
      #
      # @param framebuffer [Framebuffer] the full-screen framebuffer (logical space)
      # @param x [Integer] left edge of the region (aligned down to 8px)
      # @param y [Integer] top edge of the region
      # @param width [Integer] region width in pixels (aligned up to 8px)
      # @param height [Integer] region height in pixels
      # @return [self]
      # @raise [ArgumentError] if the region exceeds display bounds
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_region(framebuffer, x:, y:, width:, height:)
        validate_region!(x, y, width, height)
        # Validates logical (rotated) dimensions — distinct from Display#validate_framebuffer!
        # which checks native dimensions for raw framebuffer input.
        validate_logical_framebuffer!(framebuffer)
        native_x, native_y, native_w, native_h = transform_region_to_native(x, y, width, height)
        aligned_x, aligned_w = align_x_to_byte_boundary(native_x, native_w)
        native_fb = build_native_region_fb(framebuffer, aligned_x, native_y, aligned_w, native_h)
        ensure_initialized!
        synchronize_device do
          device.send(:_epd_display_region, native_fb,
                      aligned_x, native_y, aligned_w, native_h)
        end
        self
      end

      private

      # Validates that the framebuffer matches this display's logical dimensions and format.
      #
      # @param framebuffer [Framebuffer] the framebuffer to validate
      # @raise [FormatMismatchError] if the pixel format does not match
      # @raise [ArgumentError] if dimensions do not match logical display size
      def validate_logical_framebuffer!(framebuffer)
        unless framebuffer.pixel_format == pixel_format
          raise FormatMismatchError,
                "expected #{pixel_format.name} framebuffer, got #{framebuffer.pixel_format.name}"
        end

        return if framebuffer.width == width && framebuffer.height == height

        raise ArgumentError,
              "framebuffer dimensions #{framebuffer.width}x#{framebuffer.height} " \
              "do not match display size #{width}x#{height}"
      end

      # Builds a full-screen native-orientation framebuffer with the aligned
      # sub-region populated from the logical framebuffer.
      #
      # For rotation == 0, returns the original framebuffer unchanged (no copy).
      # For other rotations, extracts the aligned logical sub-region,
      # rotates only that piece, and blits it into a fresh native-sized
      # framebuffer at the correct offset. This avoids rotating the entire
      # full-screen buffer.
      #
      # @param framebuffer [Framebuffer] full-screen logical framebuffer
      # @param aligned_x [Integer] byte-aligned native X coordinate
      # @param native_y [Integer] native Y coordinate
      # @param aligned_w [Integer] byte-aligned native width
      # @param native_h [Integer] native height
      # @return [Framebuffer] full-screen native-orientation framebuffer
      def build_native_region_fb(framebuffer, aligned_x, native_y, aligned_w, native_h)
        return framebuffer if rotation.zero?

        lx, ly, lw, lh = transform_native_to_logical(aligned_x, native_y, aligned_w, native_h)
        rotated_region = framebuffer.extract(lx, ly, lw, lh).rotate(rotation)
        native_fb = Framebuffer.new(native_width, native_height, pixel_format)
        native_fb.blit(rotated_region, x: aligned_x, y: native_y)
        native_fb
      end

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

      # Transforms a logical region to native display coordinates.
      #
      # @param x [Integer] logical left edge
      # @param y [Integer] logical top edge
      # @param w [Integer] logical region width
      # @param h [Integer] logical region height
      # @return [Array(Integer, Integer, Integer, Integer)] native [x, y, width, height]
      def transform_region_to_native(x, y, w, h)
        case rotation
        when 0   then [x, y, w, h]
        when 90  then [native_width - y - h, x, h, w]
        when 180 then [native_width - x - w, native_height - y - h, w, h]
        when 270 then [y, native_height - x - w, h, w]
        else raise ArgumentError, "unsupported rotation: #{rotation}"
        end
      end

      # Transforms a native-space region back to logical coordinates.
      #
      # This is the inverse of {#transform_region_to_native}.
      #
      # @param nat_x [Integer] native left edge
      # @param nat_y [Integer] native top edge
      # @param nat_w [Integer] native region width
      # @param nat_h [Integer] native region height
      # @return [Array(Integer, Integer, Integer, Integer)] logical [x, y, width, height]
      def transform_native_to_logical(nat_x, nat_y, nat_w, nat_h)
        case rotation
        when 0   then [nat_x, nat_y, nat_w, nat_h]
        when 90  then [nat_y, native_width - nat_x - nat_w, nat_h, nat_w]
        when 180 then [native_width - nat_x - nat_w, native_height - nat_y - nat_h, nat_w, nat_h]
        when 270 then [native_height - nat_y - nat_h, nat_x, nat_h, nat_w]
        else raise ArgumentError, "unsupported rotation: #{rotation}"
        end
      end

      # Aligns X coordinate and width to 8-pixel byte boundaries.
      #
      # Floors X to the nearest lower multiple of 8, and ceils the end
      # (X + width) to the nearest higher multiple of 8. Clamps the
      # result to the native display width.
      #
      # @param x [Integer] original X coordinate
      # @param w [Integer] original width
      # @return [Array(Integer, Integer)] aligned [x, width]
      def align_x_to_byte_boundary(x, w)
        aligned_x = x & ~7 # floor to 8px
        aligned_end = ((x + w + 7) & ~7) # ceil end to 8px
        aligned_end = [aligned_end, native_width].min # clamp to display
        [aligned_x, aligned_end - aligned_x]
      end
    end
  end
end
