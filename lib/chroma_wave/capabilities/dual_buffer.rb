# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Adds dual-buffer display support to a Display subclass.
    #
    # Dual-buffer mode covers two hardware workflows:
    #
    # 1. **Tri-color** (COLOR4) -- the display has separate black and
    #    red/yellow planes. {#show} automatically splits a Canvas into two
    #    MONO framebuffers via {Renderer#render_dual}.
    # 2. **Monochrome dual-RAM** -- the display has two RAM banks (old and
    #    new buffer). The same data is written to both banks so the
    #    controller can compute the differential waveform.
    #
    # In both cases, {#show_raw} sends two MONO framebuffers to the two
    # RAM banks regardless of color model.
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
      # Both framebuffers must be MONO format with dimensions matching
      # this display's width and height.
      #
      # @param black_fb [Framebuffer] MONO framebuffer for the black (or old) plane
      # @param red_fb [Framebuffer] MONO framebuffer for the red (or new) plane
      # @return [self]
      # @raise [TypeError] if either argument is not a Framebuffer
      # @raise [FormatMismatchError] if either framebuffer is not MONO
      # @raise [ArgumentError] if dimensions do not match
      def show_raw(black_fb, red_fb)
        validate_dual_framebuffers!(black_fb, red_fb)
        ensure_initialized!
        synchronize_device { device.send(:_epd_display_dual, black_fb, red_fb) }
        self
      end

      private

      # Validates that both framebuffers are MONO and match this display's dimensions.
      #
      # @param black_fb [Object] first framebuffer to validate
      # @param red_fb [Object] second framebuffer to validate
      # @raise [TypeError] if either argument is not a Framebuffer
      # @raise [FormatMismatchError] if either framebuffer is not MONO
      # @raise [ArgumentError] if dimensions do not match
      def validate_dual_framebuffers!(black_fb, red_fb)
        [black_fb, red_fb].each do |fb|
          raise TypeError, "expected Framebuffer, got #{fb.class}" unless fb.is_a?(Framebuffer)

          unless fb.pixel_format == PixelFormat::MONO
            raise FormatMismatchError,
                  "expected MONO framebuffer, got #{fb.pixel_format.name}"
          end
        end

        return if black_fb.width == width && black_fb.height == height &&
                  red_fb.width == width && red_fb.height == height

        raise ArgumentError,
              "framebuffer dimensions must match display (#{width}x#{height})"
      end
    end
  end
end
