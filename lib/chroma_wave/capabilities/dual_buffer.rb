# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds dual-buffer display support to a Display subclass.
    #
    # Tri-color E-Paper displays use separate black and red (or yellow) planes.
    # This module overrides {Display#show} to automatically split Canvas content
    # into two MONO framebuffers via {Renderer#render_dual}, and provides
    # {#show_raw} for pre-rendered dual buffers.
    module DualBuffer
      # Renders a Canvas and sends dual framebuffers, or delegates to super.
      #
      # When given a Canvas on a COLOR4 display, uses {Renderer#render_dual}
      # to split into black and red planes. For non-COLOR4 displays or
      # Framebuffer input, falls back to the default single-buffer
      # {Display#show}.
      #
      # @param canvas_or_fb [Canvas, Framebuffer] content to display
      # @return [self]
      def show(canvas_or_fb)
        if canvas_or_fb.is_a?(Canvas) && pixel_format == PixelFormat::COLOR4
          ensure_initialized!
          black_fb, red_fb = renderer.render_dual(canvas_or_fb)
          synchronize_device { device.send(:_epd_display_dual, black_fb, red_fb) }
          self
        else
          super
        end
      end

      # Sends pre-rendered dual framebuffers directly to the display.
      #
      # @param black_fb [Framebuffer] MONO framebuffer for the black plane
      # @param red_fb [Framebuffer] MONO framebuffer for the red plane
      # @return [self]
      def show_raw(black_fb, red_fb)
        ensure_initialized!
        synchronize_device { device.send(:_epd_display_dual, black_fb, red_fb) }
        self
      end
    end
  end
end
