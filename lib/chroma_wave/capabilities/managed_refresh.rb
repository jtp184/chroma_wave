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
    # Tracking and interval checks occur *after* the display operation succeeds,
    # ensuring counters and timestamps are not mutated if the underlying call raises.
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
      # a maintenance full refresh is performed after the partial display to
      # clear ghosting artifacts before the next update.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      def display_partial(framebuffer)
        _with_partial_tracking(framebuffer) { super }
      end

      # Displays a framebuffer using fast refresh, tracking the refresh count.
      #
      # When the partial limit is reached and +auto_full_refresh+ is enabled,
      # a maintenance full refresh is performed after the fast display.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      def display_fast(framebuffer)
        _with_partial_tracking(framebuffer) { super }
      end

      # Displays a sub-region, tracking as a partial refresh.
      #
      # Auto-full-refresh is skipped because the caller intends a regional
      # update only; a full refresh requires re-initializing the display in
      # full mode and pushing a complete framebuffer.
      #
      # @param framebuffer [Framebuffer] full-screen framebuffer in native orientation
      # @param x [Integer] left edge of the region
      # @param y [Integer] top edge of the region
      # @param width [Integer] region width in pixels
      # @param height [Integer] region height in pixels
      # @return [self]
      def display_region(framebuffer, x:, y:, width:, height:)
        _with_partial_tracking(framebuffer, auto_refresh: false) { super }
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
        _with_full_tracking { super(canvas_or_fb) }
      end

      # Displays a base image for subsequent partial updates, tracking as a full refresh.
      #
      # @param framebuffer [Framebuffer] the base framebuffer
      # @return [self]
      def display_base(framebuffer)
        _with_full_tracking { super }
      end

      # Displays a framebuffer using grayscale mode, tracking as a full refresh.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [self]
      def display_grayscale(framebuffer)
        _with_full_tracking { super }
      end

      # Clears the display, tracking as a full refresh.
      #
      # @param color [Symbol] palette color name (default: +:white+)
      # @return [self]
      def clear(color: :white)
        _with_full_tracking { super }
      end

      private

      # Wraps a partial display operation with interval checking, counter
      # tracking, and optional auto-full-refresh.
      #
      # The display operation (+yield+) runs first, outside the device lock,
      # since +super+ already synchronizes its own device I/O internally.
      # Only scheduler state mutations and auto-full-refresh are performed
      # under the lock, keeping the critical section minimal.
      #
      # @param framebuffer [Framebuffer] the framebuffer being displayed
      # @param auto_refresh [Boolean] whether to trigger auto-full-refresh
      #   when the partial limit is reached (default: +true+). Disabled for
      #   regional refreshes which cannot safely trigger a full-screen refresh.
      # @yield the display operation to wrap (must call +super+)
      # @return [self]
      def _with_partial_tracking(framebuffer, auto_refresh: true)
        yield
        synchronize_device do
          refresh_scheduler.check_interval!
          refresh_scheduler.track_partial!
          _auto_full_refresh!(framebuffer) if auto_refresh && _should_auto_refresh?
        end
        self
      end

      # Wraps a full display operation with interval checking and counter reset.
      #
      # The display operation (+yield+) runs first, outside the device lock,
      # since +super+ already synchronizes its own device I/O internally.
      # Only scheduler state mutations are performed under the lock.
      #
      # @yield the display operation to wrap (must call +super+)
      # @return [self]
      def _with_full_tracking
        yield
        synchronize_device do
          refresh_scheduler.check_interval!
          refresh_scheduler.track_full!
        end
        self
      end

      # Returns whether an automatic full refresh should be triggered.
      #
      # @return [Boolean]
      def _should_auto_refresh?
        refresh_scheduler.auto_full_refresh? && refresh_scheduler.needs_full?
      end

      # Performs an automatic maintenance full refresh to clear ghosting.
      #
      # Delegates to {Display#force_full_refresh!} for the device interaction
      # and state mutation, then tracks the full refresh on the scheduler.
      # Must be called while holding the device lock.
      #
      # If the full refresh fails (e.g. hardware error), the error is logged
      # and the counter is reset to avoid retrying on every subsequent partial
      # call. The partial display that triggered this has already succeeded.
      #
      # @param framebuffer [Framebuffer] the content to display in the full refresh
      # @return [void]
      def _auto_full_refresh!(framebuffer)
        force_full_refresh!(framebuffer)
        refresh_scheduler.track_full!
      rescue DeviceError => e
        warn "[ChromaWave] Auto-full-refresh failed: #{e.message}. " \
             'Counter reset; next cycle will retry.'
        refresh_scheduler.reset!
      end
    end
  end
end
