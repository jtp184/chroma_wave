# frozen_string_literal: true

module ChromaWave
  module Capabilities
    # Opt-in capability that wraps display methods with automatic refresh scheduling.
    #
    # Mixed in via +extend+ on individual Display instances when +managed_refresh:+
    # is passed to {Display.new} or {MockDevice.new}. Because it is +extend+ed
    # (not +include+d), it only affects the specific instance, keeping the default
    # behavior unchanged for other instances of the same class.
    #
    # Wraps 7 display methods:
    # - **Partial trackers** (+display_partial+, +display_fast+, +display_region+):
    #   increment the partial counter after each call. +display_partial+ and
    #   +display_fast+ may trigger an automatic maintenance full refresh when the
    #   partial limit is reached. +display_region+ skips auto-refresh (sub-region only).
    # - **Full trackers** (+show+, +display_base+, +display_grayscale+, +clear+):
    #   reset the partial counter after each call.
    #
    # Requires the Device to use a reentrant lock (Monitor) since wrappers
    # call +synchronize_device+ around +super+, which itself synchronizes.
    #
    # @example
    #   display = Display.new(model: :epd_2in13_v4, managed_refresh: true)
    #   display.refresh_scheduler.partial_count  # => 0
    #   5.times { display.display_partial(fb) }  # auto-triggers full refresh on 5th
    #
    # @see RefreshScheduler
    module ManagedRefresh
      # Returns the refresh scheduler for this display instance.
      #
      # @return [RefreshScheduler]
      attr_reader :refresh_scheduler

      # --- Partial trackers ---

      # Displays a framebuffer using partial refresh, tracking the refresh count.
      #
      # When the partial limit is reached and +auto_full_refresh+ is enabled,
      # a maintenance full refresh is performed first to clear ghosting artifacts,
      # then the partial display proceeds.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      def display_partial(framebuffer)
        validate_framebuffer!(framebuffer)
        synchronize_device do
          refresh_scheduler.check_interval!
          refresh_scheduler.track_partial!
          _auto_full_refresh!(framebuffer) if _should_auto_refresh?
          super
        end
        self
      end

      # Displays a framebuffer using fast refresh, tracking the refresh count.
      #
      # When the partial limit is reached and +auto_full_refresh+ is enabled,
      # a maintenance full refresh is performed first.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      def display_fast(framebuffer)
        validate_framebuffer!(framebuffer)
        synchronize_device do
          refresh_scheduler.check_interval!
          refresh_scheduler.track_partial!
          _auto_full_refresh!(framebuffer) if _should_auto_refresh?
          super
        end
        self
      end

      # Displays a sub-region, tracking as a partial refresh.
      #
      # The partial counter increments but auto-full-refresh is skipped because
      # only a sub-region framebuffer is available — a full refresh requires a
      # full-screen framebuffer.
      #
      # @param framebuffer [Framebuffer] the full-screen framebuffer (logical space)
      # @param x [Integer] left edge of the region
      # @param y [Integer] top edge of the region
      # @param width [Integer] region width in pixels
      # @param height [Integer] region height in pixels
      # @return [self]
      def display_region(framebuffer, x:, y:, width:, height:)
        synchronize_device do
          refresh_scheduler.check_interval!
          refresh_scheduler.track_partial!
          # No auto-full-refresh for sub-regions — only a sub-region is available
          super
        end
        self
      end

      # --- Full trackers ---

      # Shows content on the display, tracking as a full refresh.
      #
      # Resolves Layout input to Canvas before delegating to avoid double-tracking
      # from Layout's recursive +show+ call.
      #
      # @param canvas_or_fb [Canvas, Layout, Framebuffer] content to display
      # @return [self]
      def show(canvas_or_fb)
        canvas_or_fb = canvas_or_fb.render if canvas_or_fb.is_a?(Layout)
        synchronize_device do
          refresh_scheduler.check_interval!
          super(canvas_or_fb)
          refresh_scheduler.track_full!
        end
        self
      end

      # Displays a base image for subsequent partial updates, tracking as a full refresh.
      #
      # @param framebuffer [Framebuffer] the base framebuffer
      # @return [self]
      def display_base(framebuffer)
        synchronize_device do
          refresh_scheduler.check_interval!
          super
          refresh_scheduler.track_full!
        end
        self
      end

      # Displays a framebuffer using grayscale mode, tracking as a full refresh.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      def display_grayscale(framebuffer)
        synchronize_device do
          refresh_scheduler.check_interval!
          super
          refresh_scheduler.track_full!
        end
        self
      end

      # Clears the display, tracking as a full refresh.
      #
      # @param color [Symbol] palette color name (default: +:white+)
      # @return [self]
      def clear(color: :white)
        synchronize_device do
          refresh_scheduler.check_interval!
          super
          refresh_scheduler.track_full!
        end
        self
      end

      private

      # Returns whether an automatic full refresh should be triggered.
      #
      # @return [Boolean]
      def _should_auto_refresh?
        refresh_scheduler.auto_full_refresh? && refresh_scheduler.needs_full?
      end

      # Performs an automatic maintenance full refresh to clear ghosting.
      #
      # Operates directly on the device to avoid re-entering ManagedRefresh
      # wrappers (no double interval-check or double tracking). Must be called
      # while holding the device lock.
      #
      # @param framebuffer [Framebuffer] the content to display in the full refresh
      # @return [void]
      def _auto_full_refresh!(framebuffer)
        device.send(:_epd_init, Native::MODE_FULL)
        device.send(:_epd_display, framebuffer)
        @current_mode = :full
        @initialized = true
        refresh_scheduler.track_full!
      end
    end
  end
end
