# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds partial-refresh display mode to a Display subclass.
    #
    # Partial refresh avoids the full screen flash, enabling fast updates
    # for small changes. The recommended workflow is:
    #
    # 1. Display a base image via {#display_base} (uses full refresh).
    # 2. Update the display via {#display_partial} (uses partial refresh).
    #
    # On V2+ models, the vendor recommends displaying a base image before
    # the first partial update; otherwise the first few seconds may show
    # artifacts. Partial init is self-contained and does not require a
    # prior full-mode init.
    #
    # @example Partial refresh workflow
    #   display.display_base(base_fb)      # full refresh, sets base image
    #   display.display_partial(updated_fb) # fast partial update
    module PartialRefresh
      # Initializes the display for partial refresh mode.
      #
      # @return [self]
      def init_partial
        synchronize_device do
          device.send(:_epd_init, Native::MODE_PARTIAL)
          @current_mode = :partial
        end
        self
      end

      # Displays a framebuffer using partial refresh (fast, no full flash).
      #
      # Automatically initializes partial mode if not already active.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_partial(framebuffer)
        validate_framebuffer!(framebuffer)
        init_partial unless current_mode == :partial
        synchronize_device { device.send(:_epd_display, framebuffer) }
        self
      end

      # Displays a framebuffer as the base image for subsequent partial updates.
      #
      # @param framebuffer [Framebuffer] the base framebuffer
      # @return [self]
      # @raise [FormatMismatchError] if the framebuffer format does not match
      def display_base(framebuffer)
        validate_framebuffer!(framebuffer)
        ensure_initialized!
        synchronize_device { device.send(:_epd_display, framebuffer) }
        self
      end
    end
  end
end
