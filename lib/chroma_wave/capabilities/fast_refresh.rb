# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds fast-refresh display mode to a Display subclass.
    #
    # Fast refresh trades image quality for speed, reducing the time
    # to update the full screen. Useful for animations or rapid updates.
    module FastRefresh
      # Initializes the display for fast refresh mode.
      #
      # @return [self]
      def init_fast
        synchronize_device { _init_fast_mode }
        self
      end

      # Displays a framebuffer using fast refresh.
      #
      # Automatically initializes fast mode if not already active.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_fast(framebuffer)
        validate_framebuffer!(framebuffer)
        synchronize_device do
          _init_fast_mode unless current_mode == :fast
          device.send(:_epd_display, framebuffer)
        end
        self
      end

      private

      # Unsynchronized fast-mode init logic. Caller must hold the device mutex.
      #
      # @return [void]
      def _init_fast_mode
        device.send(:_epd_init, Native::MODE_FAST)
        @current_mode = :fast
        @initialized = true
      end
    end
  end
end
