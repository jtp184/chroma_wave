# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds grayscale display mode to a Display subclass.
    #
    # Grayscale mode uses multi-level waveforms to display 4 shades of gray,
    # providing richer image detail at the cost of slower refresh.
    module GrayscaleMode
      # Initializes the display for grayscale mode.
      #
      # @return [self]
      def init_grayscale
        synchronize_device do
          device.send(:_epd_init, Native::MODE_GRAYSCALE)
          @current_mode = :grayscale
          @initialized = true
        end
        self
      end

      # Displays a framebuffer using grayscale mode.
      #
      # Automatically initializes grayscale mode if not already active.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_grayscale(framebuffer)
        validate_framebuffer!(framebuffer)
        init_grayscale unless current_mode == :grayscale
        synchronize_device { device.send(:_epd_display, framebuffer) }
        self
      end
    end
  end
end
