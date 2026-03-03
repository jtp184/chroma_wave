# frozen_string_literal: true

module ChromaWave
  # Mixin for bounding-box dirty region tracking.
  #
  # Tracks a single axis-aligned bounding box that expands as regions are
  # marked dirty. Designed for inclusion in any class that provides +width+
  # and +height+ methods (the Surface protocol).
  #
  # @example
  #   class MyCanvas
  #     include DirtyTracking
  #     attr_reader :width, :height
  #     # ...
  #   end
  module DirtyTracking
    # Returns true if any region has been marked dirty since the last {#clean!}.
    #
    # @return [Boolean]
    def dirty?
      !@dirty_x.nil?
    end

    # Returns the bounding box of all modifications since the last {#clean!}.
    #
    # @return [Rect, nil] the dirty bounding box or nil if clean
    def dirty_region
      return nil unless @dirty_x

      Rect.new(x: @dirty_x, y: @dirty_y, width: @dirty_w, height: @dirty_h)
    end

    # Resets dirty tracking, marking the surface as clean.
    #
    # @return [self]
    def clean!
      @dirty_x = @dirty_y = @dirty_w = @dirty_h = nil
      self
    end

    # Explicitly marks a rectangular region as dirty.
    #
    # Accepts either a {Rect} or keyword arguments.
    #
    # @param rect [Rect, nil] a Rect to mark dirty
    # @param x [Integer, nil] left edge
    # @param y [Integer, nil] top edge
    # @param width [Integer, nil] width
    # @param height [Integer, nil] height
    # @return [self]
    def mark_dirty(rect = nil, x: nil, y: nil, width: nil, height: nil)
      if rect
        mark_clipped_dirty(rect.x, rect.y, rect.width, rect.height)
      else
        unless x && y && width && height
          raise ArgumentError, 'mark_dirty requires a Rect or x:, y:, width:, height: keywords'
        end

        mark_clipped_dirty(x, y, width, height)
      end
      self
    end

    private

    # Copies dirty state from +source+ into this instance.
    #
    # Intended for use in +initialize_copy+ to deep-copy dirty tracking
    # state when duplicating or cloning the includer.
    #
    # @param source [DirtyTracking] the source to copy dirty state from
    # @return [void]
    def copy_dirty_state(source)
      region = source.dirty_region
      if region
        @dirty_x = region.x
        @dirty_y = region.y
        @dirty_w = region.width
        @dirty_h = region.height
      else
        @dirty_x = @dirty_y = @dirty_w = @dirty_h = nil
      end
    end

    # Clips a rectangle to surface bounds and marks it dirty.
    #
    # Used by operations where the source rect may extend beyond surface
    # boundaries (e.g. +blit+, +load_rgba_bytes+).
    #
    # @param src_x [Integer] left edge of the source rect
    # @param src_y [Integer] top edge of the source rect
    # @param src_w [Integer] width of the source rect
    # @param src_h [Integer] height of the source rect
    # @return [void]
    def mark_clipped_dirty(src_x, src_y, src_w, src_h)
      cx = [src_x, 0].max
      cy = [src_y, 0].max
      cw = [src_x + src_w, width].min - cx
      ch = [src_y + src_h, height].min - cy
      expand_dirty(cx, cy, cw, ch) if cw.positive? && ch.positive?
    end

    # Expands the dirty bounding box to include the given rectangle.
    #
    # Uses ternary operators instead of +[a, b].min/max+ to avoid
    # Array allocations on the hot path (called per-pixel in +set_pixel+).
    #
    # @param new_x [Integer] left edge of the new dirty area
    # @param new_y [Integer] top edge of the new dirty area
    # @param new_w [Integer] width of the new dirty area
    # @param new_h [Integer] height of the new dirty area
    # @return [void]
    # rubocop:disable Style/MinMaxComparison -- ternaries avoid Array allocs on hot path
    def expand_dirty(new_x, new_y, new_w, new_h)
      if @dirty_x
        right = new_x + new_w
        bottom = new_y + new_h
        old_right = @dirty_x + @dirty_w
        old_bottom = @dirty_y + @dirty_h
        @dirty_x = new_x < @dirty_x ? new_x : @dirty_x
        @dirty_y = new_y < @dirty_y ? new_y : @dirty_y
        @dirty_w = (right > old_right ? right : old_right) - @dirty_x
        @dirty_h = (bottom > old_bottom ? bottom : old_bottom) - @dirty_y
      else
        @dirty_x = new_x
        @dirty_y = new_y
        @dirty_w = new_w
        @dirty_h = new_h
      end
    end
    # rubocop:enable Style/MinMaxComparison
  end
end
