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
      #   @param width [Numeric] target width, rounded to Integer (aspect ratio preserved)
      # @overload scale(height:)
      #   @param height [Numeric] target height, rounded to Integer (aspect ratio preserved)
      # @overload scale(width:, height:)
      #   @param width  [Numeric] target width, rounded to Integer
      #   @param height [Numeric] target height, rounded to Integer
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
      # @param x      [Numeric] left edge of the crop rectangle (rounded to Integer)
      # @param y      [Numeric] top edge of the crop rectangle (rounded to Integer)
      # @param width  [Numeric] requested width  (rounded to Integer, must be positive)
      # @param height [Numeric] requested height (rounded to Integer, must be positive)
      # @return [Canvas] a new canvas containing the cropped pixels
      # @raise [ArgumentError] if +width+ or +height+ is not a positive Numeric,
      #   or if the clipped region is entirely outside the canvas
      def crop(x:, y:, width:, height:)
        raise ArgumentError, 'crop width must be a positive Numeric' unless width.is_a?(Numeric) && width.positive?
        raise ArgumentError, 'crop height must be a positive Numeric' unless height.is_a?(Numeric) && height.positive?

        crop_clipped(x.round, y.round, width.round, height.round)
      end

      private

      # Builds a new Canvas directly from a pre-filled RGBA buffer.
      #
      # Bypasses +initialize+'s background-fill step so transforms can
      # construct the output without writing pixels twice. The buffer is
      # always duplicated to guarantee isolation from the caller.
      #
      # @param w   [Integer] canvas width
      # @param h   [Integer] canvas height
      # @param buf [String]  raw RGBA bytes (+w * h * 4+ bytes)
      # @return [Canvas]
      # @raise [ArgumentError] if dimensions or buffer size are invalid
      def build_canvas(w, h, buf)
        Surface.validate_dimensions!(w, h)

        expected = w * h * BYTES_PER_PIXEL
        raise ArgumentError, "buffer size #{buf.bytesize} != #{expected}" unless buf.bytesize == expected

        self.class.allocate.tap do |canvas|
          canvas.instance_variable_set(:@width, w)
          canvas.instance_variable_set(:@height, h)
          canvas.instance_variable_set(:@buffer, buf.dup.force_encoding(Encoding::BINARY))
        end
      end

      # Mirrors left-to-right by reversing pixels within each row.
      #
      # @return [Canvas]
      def flip_horizontal
        src = raw_buffer
        row_bytes = width * BYTES_PER_PIXEL
        out = String.new(capacity: src.bytesize)

        height.times do |row_y|
          row_start = row_y * row_bytes
          out << src.byteslice(row_start, row_bytes).unpack('V*').reverse.pack('V*')
        end

        build_canvas(width, height, out)
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

        build_canvas(width, height, out)
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
          [coerce_scale_dimension!(:width, target_w),
           coerce_scale_dimension!(:height, target_h)]
        elsif target_w
          w = coerce_scale_dimension!(:width, target_w)
          [w, [(height * w.to_f / width).round, 1].max]
        elsif target_h
          h = coerce_scale_dimension!(:height, target_h)
          [[(width * h.to_f / height).round, 1].max, h]
        else
          raise ArgumentError, 'scale requires a factor or width:/height: keywords'
        end
      end

      # Converts the various scale argument forms into +[new_w, new_h]+.
      #
      # @return [Array(Integer, Integer)]
      # @raise [ArgumentError] on invalid or conflicting arguments
      def resolve_scale_dimensions(factor, target_w, target_h)
        new_w, new_h = if factor
                         resolve_scale_factor(factor, target_w, target_h)
                       else
                         resolve_scale_keywords(target_w, target_h)
                       end

        max = Surface::MAX_DIMENSION
        raise ArgumentError, "scaled width #{new_w} exceeds maximum dimension #{max}" if new_w > max
        raise ArgumentError, "scaled height #{new_h} exceeds maximum dimension #{max}" if new_h > max

        [new_w, new_h]
      end

      # Coerces and validates a single target dimension for scale.
      #
      # Accepts Integer or Float (rounded to nearest Integer).
      #
      # @param name [Symbol] :width or :height
      # @param value [Numeric] the value to coerce and check
      # @return [Integer] the validated dimension
      # @raise [ArgumentError] unless a positive Numeric
      def coerce_scale_dimension!(name, value)
        raise ArgumentError, "#{name} must be a positive Numeric" unless value.is_a?(Numeric) && value.positive?

        value.round
      end

      # Nearest-neighbor resampling into a +new_w+ x +new_h+ canvas.
      #
      # Pre-computes the source-x lookup table to avoid per-pixel division,
      # and builds each output row as a single string before appending.
      #
      # @param new_w [Integer] output width
      # @param new_h [Integer] output height
      # @return [Canvas]
      def scale_nearest(new_w, new_h)
        src = raw_buffer
        src_w = width
        out = String.new(capacity: new_w * new_h * BYTES_PER_PIXEL)

        # Pre-compute source x byte-offset for each destination column
        x_map = Array.new(new_w) { |dx| (dx * src_w / new_w) * BYTES_PER_PIXEL }

        new_h.times do |dy|
          src_row = (dy * height / new_h) * src_w * BYTES_PER_PIXEL
          row = String.new(capacity: new_w * BYTES_PER_PIXEL)
          x_map.each { |src_x| row << src.byteslice(src_row + src_x, BYTES_PER_PIXEL) }
          out << row
        end

        build_canvas(new_w, new_h, out)
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

        build_canvas(out_w, out_h, out)
      end
    end
  end
end

ChromaWave::Canvas.include(ChromaWave::Canvas::Transforms)
