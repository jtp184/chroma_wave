# frozen_string_literal: true

module ChromaWave
  class Canvas
    # Pure-Ruby image transforms for {Canvas}.
    #
    # Every method returns a **new** Canvas — the receiver is never mutated.
    # This makes transforms safe to chain:
    #
    #   canvas.crop(x: 10, y: 10, width: 80, height: 60)
    #         .flip(:horizontal)
    #         .scale(2.0)
    #
    # Included into {Canvas} at the bottom of this file.
    module Transforms
      # Hooks the +ClassMethods+ extension when included.
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class-level factory methods added to {Canvas}.
      module ClassMethods
        private

        # Builds a Canvas directly from a pre-filled RGBA buffer.
        #
        # Bypasses +initialize+'s background-fill step so transforms can
        # construct the output without writing pixels twice.
        #
        # @param width  [Integer] canvas width in pixels
        # @param height [Integer] canvas height in pixels
        # @param buf    [String]  raw RGBA bytes (+width * height * 4+ bytes)
        # @return [Canvas]
        # @raise [ArgumentError] if dimensions or buffer size are invalid
        def from_buffer(width, height, buf)
          raise ArgumentError, 'width must be a positive Integer' unless width.is_a?(Integer) && width.positive?
          raise ArgumentError, 'height must be a positive Integer' unless height.is_a?(Integer) && height.positive?
          raise ArgumentError, "width must be <= #{Surface::MAX_DIMENSION}" if width > Surface::MAX_DIMENSION
          raise ArgumentError, "height must be <= #{Surface::MAX_DIMENSION}" if height > Surface::MAX_DIMENSION

          expected = width * height * BYTES_PER_PIXEL
          raise ArgumentError, "buffer size #{buf.bytesize} != #{expected}" unless buf.bytesize == expected

          allocate.tap do |canvas|
            canvas.instance_variable_set(:@width, width)
            canvas.instance_variable_set(:@height, height)
            canvas.instance_variable_set(:@buffer, buf.b)
          end
        end
      end

      # Mirrors the canvas horizontally or vertically.
      #
      # @param direction [:horizontal, :vertical] the flip axis
      # @return [Canvas] a new, mirrored canvas
      # @raise [ArgumentError] if +direction+ is not +:horizontal+ or +:vertical+
      def flip(direction)
        case direction
        when :horizontal then flip_horizontal
        when :vertical   then flip_vertical
        else raise ArgumentError, "direction must be :horizontal or :vertical, got #{direction.inspect}"
        end
      end

      # Scales the canvas using nearest-neighbor interpolation.
      #
      # Accepts either a uniform +factor+ or explicit +width:+/+height:+
      # keywords. When only one keyword is given, the other dimension is
      # calculated to preserve the aspect ratio. Output dimensions are
      # clamped to a minimum of 1.
      #
      # @overload scale(factor)
      #   @param factor [Numeric] uniform scale factor (must be positive)
      # @overload scale(width:)
      #   @param width [Integer] target width (aspect ratio preserved)
      # @overload scale(height:)
      #   @param height [Integer] target height (aspect ratio preserved)
      # @overload scale(width:, height:)
      #   @param width  [Integer] target width
      #   @param height [Integer] target height
      # @return [Canvas] a new, scaled canvas
      # @raise [ArgumentError] on invalid or conflicting arguments
      def scale(factor = nil, width: nil, height: nil)
        new_w, new_h = resolve_scale_dimensions(factor, width, height)
        scale_nearest(new_w, new_h)
      end

      # Extracts a rectangular sub-region of the canvas.
      #
      # The requested rectangle is silently clipped to the canvas bounds.
      # The returned canvas may therefore be smaller than +width+ x +height+
      # if the rectangle extends past the edges.
      #
      # @param x      [Integer] left edge of the crop rectangle
      # @param y      [Integer] top edge of the crop rectangle
      # @param width  [Integer] requested width  (must be positive before clipping)
      # @param height [Integer] requested height (must be positive before clipping)
      # @return [Canvas] a new canvas containing the cropped pixels
      # @raise [ArgumentError] if +width+ or +height+ is not positive,
      #   or if the clipped region is entirely outside the canvas
      def crop(x:, y:, width:, height:)
        raise ArgumentError, 'crop width must be positive' unless width.is_a?(Integer) && width.positive?
        raise ArgumentError, 'crop height must be positive' unless height.is_a?(Integer) && height.positive?

        crop_clipped(x, y, width, height)
      end

      private

      # Mirrors left-to-right by reversing pixels within each row.
      #
      # @return [Canvas]
      def flip_horizontal
        src = raw_buffer
        row_bytes = width * BYTES_PER_PIXEL
        out = String.new(capacity: src.bytesize)

        height.times do |row_y|
          row_start = row_y * row_bytes
          (width - 1).downto(0) do |col_x|
            out << src.byteslice(row_start + (col_x * BYTES_PER_PIXEL), BYTES_PER_PIXEL)
          end
        end

        Canvas.send(:from_buffer, width, height, out)
      end

      # Mirrors top-to-bottom by copying rows in reverse order.
      #
      # @return [Canvas]
      def flip_vertical
        src = raw_buffer
        row_bytes = width * BYTES_PER_PIXEL
        out = String.new(capacity: src.bytesize)

        (height - 1).downto(0) do |row_y|
          out << src.byteslice(row_y * row_bytes, row_bytes)
        end

        Canvas.send(:from_buffer, width, height, out)
      end

      # Resolves uniform-factor scale arguments into +[new_w, new_h]+.
      #
      # @return [Array(Integer, Integer)]
      # @raise [ArgumentError] on invalid arguments
      def resolve_scale_factor(factor, target_w, target_h)
        raise ArgumentError, 'scale factor must be a positive number' unless factor.is_a?(Numeric) && factor.positive?
        raise ArgumentError, 'cannot mix positional factor with width:/height: keywords' if target_w || target_h

        [[(width * factor).round, 1].max,
         [(height * factor).round, 1].max]
      end

      # Resolves keyword-based scale arguments into +[new_w, new_h]+.
      #
      # @return [Array(Integer, Integer)]
      # @raise [ArgumentError] on invalid arguments
      def resolve_scale_keywords(target_w, target_h)
        if target_w && target_h
          validate_scale_dimension!(:width, target_w)
          validate_scale_dimension!(:height, target_h)
          [target_w, target_h]
        elsif target_w
          validate_scale_dimension!(:width, target_w)
          [target_w, [(height * target_w.to_f / width).round, 1].max]
        elsif target_h
          validate_scale_dimension!(:height, target_h)
          [[(width * target_h.to_f / height).round, 1].max, target_h]
        else
          raise ArgumentError, 'scale requires a factor or width:/height: keywords'
        end
      end

      # Converts the various scale argument forms into +[new_w, new_h]+.
      #
      # @return [Array(Integer, Integer)]
      # @raise [ArgumentError] on invalid or conflicting arguments
      def resolve_scale_dimensions(factor, target_w, target_h)
        if factor
          resolve_scale_factor(factor, target_w, target_h)
        else
          resolve_scale_keywords(target_w, target_h)
        end
      end

      # Validates a single target dimension for scale.
      #
      # @param name [Symbol] :width or :height
      # @param value [Object] the value to check
      # @raise [ArgumentError] unless positive Integer
      def validate_scale_dimension!(name, value)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer"
      end

      # Nearest-neighbor resampling into a +new_w+ x +new_h+ canvas.
      #
      # Pre-computes the source-x lookup table to avoid per-pixel division.
      #
      # @param new_w [Integer] output width
      # @param new_h [Integer] output height
      # @return [Canvas]
      def scale_nearest(new_w, new_h)
        src = raw_buffer
        src_w = width
        out = String.new(capacity: new_w * new_h * BYTES_PER_PIXEL)

        # Pre-compute source x for each destination column
        x_map = Array.new(new_w) { |dx| (dx * src_w / new_w) * BYTES_PER_PIXEL }

        new_h.times do |dy|
          src_row = (dy * height / new_h) * src_w * BYTES_PER_PIXEL
          new_w.times do |dx|
            out << src.byteslice(src_row + x_map[dx], BYTES_PER_PIXEL)
          end
        end

        Canvas.send(:from_buffer, new_w, new_h, out)
      end

      # Clips the crop rectangle to canvas bounds and copies rows.
      #
      # @param x [Integer] left edge
      # @param y [Integer] top edge
      # @param w [Integer] requested width
      # @param h [Integer] requested height
      # @return [Canvas]
      # @raise [ArgumentError] if the clipped region is entirely outside
      def crop_clipped(x, y, w, h)
        x0, y0, out_w, out_h = compute_crop_bounds(x, y, w, h)
        raise ArgumentError, 'crop region is entirely outside the canvas' if out_w <= 0 || out_h <= 0

        copy_crop_rows(x0, y0, out_w, out_h)
      end

      # Computes the clipped crop bounds as +[x0, y0, out_w, out_h]+.
      #
      # @return [Array(Integer, Integer, Integer, Integer)]
      def compute_crop_bounds(x, y, w, h)
        x0 = x.clamp(0, width)
        y0 = y.clamp(0, height)
        x1 = (x + w).clamp(0, width)
        y1 = (y + h).clamp(0, height)
        [x0, y0, x1 - x0, y1 - y0]
      end

      # Copies rows from the raw buffer for a crop operation.
      #
      # @return [Canvas]
      def copy_crop_rows(x0, y0, out_w, out_h)
        src = raw_buffer
        src_row_bytes = width * BYTES_PER_PIXEL
        copy_len = out_w * BYTES_PER_PIXEL
        out = String.new(capacity: out_w * out_h * BYTES_PER_PIXEL)

        (y0...(y0 + out_h)).each do |row_y|
          offset = (row_y * src_row_bytes) + (x0 * BYTES_PER_PIXEL)
          out << src.byteslice(offset, copy_len)
        end

        Canvas.send(:from_buffer, out_w, out_h, out)
      end
    end
  end
end

ChromaWave::Canvas.include(ChromaWave::Canvas::Transforms)
