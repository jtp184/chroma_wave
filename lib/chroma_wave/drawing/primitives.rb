# frozen_string_literal: true

module ChromaWave
  module Drawing
    # Drawing primitives mixed into {Surface}.
    #
    # Every method returns +self+ for chaining. Colors are duck-typed and
    # passed straight through to +set_pixel+ — no conversion or validation
    # is performed here.
    #
    # Shapes that accept both +stroke:+ and +fill:+ draw fill first, then
    # stroke on top so the outline is always visible.
    module Primitives
      # Draws a straight line using Bresenham's algorithm.
      #
      # @param x0 [Integer] start x
      # @param y0 [Integer] start y
      # @param x1 [Integer] end x
      # @param y1 [Integer] end y
      # @param stroke [Object] line color
      # @param stroke_width [Integer] line thickness (default: 1)
      # @return [self]
      def draw_line(x0, y0, x1, y1, stroke:, stroke_width: 1)
        validate_draw_colors!(stroke, nil, allow_fill: false)

        if stroke_width <= 1
          bresenham(x0, y0, x1, y1) { |x, y| set_pixel(x, y, stroke) }
        else
          draw_thick_line(x0, y0, x1, y1, stroke, stroke_width)
        end
        self
      end

      # Draws a connected series of line segments.
      #
      # @param points [Array<Array(Integer, Integer)>] array of [x, y] pairs
      # @param stroke [Object] line color
      # @param stroke_width [Integer] line thickness (default: 1)
      # @param closed [Boolean] if true, connect last point to first
      # @return [self]
      def draw_polyline(points, stroke:, stroke_width: 1, closed: false)
        validate_draw_colors!(stroke, nil, allow_fill: false)
        return self if points.length < 2

        points.each_cons(2) do |(x0, y0), (x1, y1)|
          draw_line(x0, y0, x1, y1, stroke: stroke, stroke_width: stroke_width)
        end

        if closed
          x0, y0 = points.last
          x1, y1 = points.first
          draw_line(x0, y0, x1, y1, stroke: stroke, stroke_width: stroke_width)
        end
        self
      end

      # Draws a rectangle.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param w [Integer] width
      # @param h [Integer] height
      # @param stroke [Object, nil] outline color
      # @param fill [Object, nil] fill color
      # @param stroke_width [Integer] outline thickness (default: 1)
      # @return [self]
      def draw_rect(x, y, w, h, stroke: nil, fill: nil, stroke_width: 1)
        validate_draw_colors!(stroke, fill)
        return self if w <= 0 || h <= 0

        fill_rect(x, y, w, h, fill) if fill
        stroke_rect(x, y, w, h, stroke, stroke_width) if stroke
        self
      end

      # Draws a rectangle with rounded corners.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param w [Integer] width
      # @param h [Integer] height
      # @param radius [Integer] corner radius (clamped to min(w, h) / 2)
      # @param stroke [Object, nil] outline color
      # @param fill [Object, nil] fill color
      # @param stroke_width [Integer] outline thickness (default: 1)
      # @return [self]
      def draw_rounded_rect(x, y, w, h, radius:, stroke: nil, fill: nil, stroke_width: 1)
        validate_draw_colors!(stroke, fill)
        return self if w <= 0 || h <= 0

        r = clamp_radius(radius, w, h)
        fill_rounded_rect(x, y, w, h, r, fill) if fill
        stroke_rounded_rect(x, y, w, h, r, stroke, stroke_width) if stroke
        self
      end

      # Draws a circle.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param r [Integer] radius
      # @param stroke [Object, nil] outline color
      # @param fill [Object, nil] fill color
      # @param stroke_width [Integer] outline thickness (default: 1)
      # @return [self]
      def draw_circle(cx, cy, r, stroke: nil, fill: nil, stroke_width: 1)
        validate_draw_colors!(stroke, fill)
        return self if r.negative?

        if r.zero?
          color = fill || stroke
          set_pixel(cx, cy, color)
          return self
        end

        fill_circle(cx, cy, r, fill) if fill
        stroke_circle(cx, cy, r, stroke, stroke_width) if stroke
        self
      end

      # Draws an ellipse.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param rx [Integer] horizontal radius
      # @param ry [Integer] vertical radius
      # @param stroke [Object, nil] outline color
      # @param fill [Object, nil] fill color
      # @param stroke_width [Integer] outline thickness (default: 1)
      # @return [self]
      def draw_ellipse(cx, cy, rx, ry, stroke: nil, fill: nil, stroke_width: 1)
        validate_draw_colors!(stroke, fill)
        return self if rx.negative? || ry.negative?

        if rx.zero? && ry.zero?
          color = fill || stroke
          set_pixel(cx, cy, color)
          return self
        end

        fill_ellipse(cx, cy, rx, ry, fill) if fill
        stroke_ellipse(cx, cy, rx, ry, stroke, stroke_width) if stroke
        self
      end

      # Draws a circular arc.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param r [Integer] radius
      # @param start_angle [Float] start angle in radians
      # @param end_angle [Float] end angle in radians
      # @param stroke [Object] arc color
      # @param stroke_width [Integer] arc thickness (default: 1)
      # @return [self]
      def draw_arc(cx, cy, r, start_angle, end_angle, stroke:, stroke_width: 1)
        validate_draw_colors!(stroke, nil, allow_fill: false)
        return self if r <= 0

        draw_arc_pixels(cx, cy, r, start_angle, end_angle, stroke, stroke_width)
        self
      end

      # Draws a filled/stroked polygon.
      #
      # @param points [Array<Array(Integer, Integer)>] vertices as [x, y] pairs
      # @param stroke [Object, nil] outline color
      # @param fill [Object, nil] fill color
      # @param stroke_width [Integer] outline thickness (default: 1)
      # @return [self]
      def draw_polygon(points, stroke: nil, fill: nil, stroke_width: 1)
        validate_draw_colors!(stroke, fill)
        return self if points.length < 3

        fill_polygon(points, fill) if fill
        draw_polyline(points, stroke: stroke, stroke_width: stroke_width, closed: true) if stroke
        self
      end

      # Flood-fills a contiguous region starting at (x, y).
      #
      # Uses a scanline algorithm for O(pixels) time with O(height) stack.
      #
      # @param x [Integer] seed x
      # @param y [Integer] seed y
      # @param color [Object] the fill color
      # @return [self]
      def flood_fill(x, y, color:)
        return self unless in_bounds?(x, y)

        target = get_pixel(x, y)
        return self if target == color

        scanline_fill(x, y, target, color)
        self
      end

      private

      # Validates that at least one of stroke/fill is provided.
      #
      # @param stroke [Object, nil]
      # @param fill [Object, nil]
      # @param allow_fill [Boolean] whether fill is allowed for this shape
      # @raise [ArgumentError] if neither provided or fill disallowed
      def validate_draw_colors!(stroke, fill, allow_fill: true)
        raise ArgumentError, 'fill: is not supported for this shape' if !allow_fill && fill

        return unless stroke.nil? && fill.nil?

        raise ArgumentError, 'must provide at least one of stroke: or fill:'
      end

      # ── Bresenham line ────────────────────────────────────────────

      # Standard Bresenham integer line algorithm.
      #
      # @param x0 [Integer] start x
      # @param y0 [Integer] start y
      # @param x1 [Integer] end x
      # @param y1 [Integer] end y
      # @yield [x, y] called for each pixel along the line
      def bresenham(x0, y0, x1, y1)
        dx = (x1 - x0).abs
        dy = -(y1 - y0).abs
        sx = x0 < x1 ? 1 : -1
        sy = y0 < y1 ? 1 : -1
        err = dx + dy

        loop do
          yield x0, y0
          break if x0 == x1 && y0 == y1

          e2 = 2 * err
          if e2 >= dy
            err += dy
            x0 += sx
          end
          if e2 <= dx
            err += dx
            y0 += sy
          end
        end
      end

      # Draws a thick line using perpendicular offset Bresenham lines.
      #
      # @param x0 [Integer] start x
      # @param y0 [Integer] start y
      # @param x1 [Integer] end x
      # @param y1 [Integer] end y
      # @param color [Object] line color
      # @param w [Integer] line thickness
      def draw_thick_line(x0, y0, x1, y1, color, w) # rubocop:disable Metrics/AbcSize
        half = (w - 1) / 2.0
        dx = x1 - x0
        dy = y1 - y0
        len = Math.sqrt((dx * dx) + (dy * dy))

        if len.zero?
          fill_circle(x0, y0, half.round, color)
          return
        end

        # Perpendicular unit vector
        px = -dy / len
        py = dx / len

        (-half.ceil..half.ceil).each do |offset|
          ox = (px * offset).round
          oy = (py * offset).round
          bresenham(x0 + ox, y0 + oy, x1 + ox, y1 + oy) do |x, y|
            set_pixel(x, y, color)
          end
        end
      end

      # ── Rectangle helpers ─────────────────────────────────────────

      # Fills a solid rectangle with horizontal spans.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param w [Integer] width
      # @param h [Integer] height
      # @param color [Object] fill color
      def fill_rect(x, y, w, h, color)
        h.times do |row|
          w.times { |col| set_pixel(x + col, y + row, color) }
        end
      end

      # Strokes a rectangle outline using four thick lines.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param w [Integer] width
      # @param h [Integer] height
      # @param color [Object] stroke color
      # @param sw [Integer] stroke width
      def stroke_rect(x, y, w, h, color, sw)
        x2 = x + w - 1
        y2 = y + h - 1
        draw_line(x, y, x2, y, stroke: color, stroke_width: sw)
        draw_line(x, y2, x2, y2, stroke: color, stroke_width: sw)
        draw_line(x, y, x, y2, stroke: color, stroke_width: sw)
        draw_line(x2, y, x2, y2, stroke: color, stroke_width: sw)
      end

      # ── Rounded rectangle helpers ─────────────────────────────────

      # Clamps radius to fit within the rectangle.
      #
      # @param radius [Integer] requested radius
      # @param w [Integer] rectangle width
      # @param h [Integer] rectangle height
      # @return [Integer] clamped radius
      def clamp_radius(radius, w, h)
        max = [w, h].min / 2
        [radius, max].min
      end

      # Fills a rounded rectangle.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param w [Integer] width
      # @param h [Integer] height
      # @param r [Integer] corner radius
      # @param color [Object] fill color
      def fill_rounded_rect(x, y, w, h, r, color) # rubocop:disable Metrics/AbcSize
        # Fill center rectangle
        fill_rect(x + r, y, w - (2 * r), h, color)
        # Fill left and right strips
        fill_rect(x, y + r, r, h - (2 * r), color)
        fill_rect(x + w - r, y + r, r, h - (2 * r), color)
        # Fill four corner quadrants
        fill_quarter_circle(x + r, y + r, r, color, -1, -1)
        fill_quarter_circle(x + w - r - 1, y + r, r, color, 1, -1)
        fill_quarter_circle(x + r, y + h - r - 1, r, color, -1, 1)
        fill_quarter_circle(x + w - r - 1, y + h - r - 1, r, color, 1, 1)
      end

      # Fills a quarter circle using midpoint scanlines.
      #
      # @param cx [Integer] corner center x
      # @param cy [Integer] corner center y
      # @param r [Integer] radius
      # @param color [Object] fill color
      # @param sx [Integer] x direction (-1 or 1)
      # @param sy [Integer] y direction (-1 or 1)
      def fill_quarter_circle(cx, cy, r, color, sx, sy)
        xi = 0
        yi = r
        d = 1 - r

        while xi <= yi
          draw_horizontal_span(cx, cy + (sy * xi), sx, yi, color)
          draw_horizontal_span(cx, cy + (sy * yi), sx, xi, color) if xi != yi
          xi += 1
          if d.negative?
            d += (2 * xi) + 1
          else
            yi -= 1
            d += (2 * (xi - yi)) + 1
          end
        end
      end

      # Draws a horizontal span from cx extending in direction sx.
      #
      # @param cx [Integer] center x
      # @param y [Integer] y coordinate
      # @param sx [Integer] direction (-1 or 1)
      # @param len [Integer] span length
      # @param color [Object] color
      def draw_horizontal_span(cx, y, sx, len, color)
        if sx.positive?
          (len + 1).times { |i| set_pixel(cx + i, y, color) }
        else
          (len + 1).times { |i| set_pixel(cx - i, y, color) }
        end
      end

      # Strokes a rounded rectangle outline.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param w [Integer] width
      # @param h [Integer] height
      # @param r [Integer] corner radius
      # @param color [Object] stroke color
      # @param sw [Integer] stroke width
      def stroke_rounded_rect(x, y, w, h, r, color, sw) # rubocop:disable Metrics/AbcSize
        x2 = x + w - 1
        y2 = y + h - 1

        # Four straight edges (excluding corners)
        draw_line(x + r, y, x2 - r, y, stroke: color, stroke_width: sw)       # top
        draw_line(x + r, y2, x2 - r, y2, stroke: color, stroke_width: sw)     # bottom
        draw_line(x, y + r, x, y2 - r, stroke: color, stroke_width: sw)       # left
        draw_line(x2, y + r, x2, y2 - r, stroke: color, stroke_width: sw)     # right

        # Four corner arcs
        half_pi = Math::PI / 2
        draw_arc(x + r, y + r, r, Math::PI, Math::PI + half_pi, stroke: color, stroke_width: sw)
        draw_arc(x2 - r, y + r, r, -half_pi, 0.0, stroke: color, stroke_width: sw)
        draw_arc(x + r, y2 - r, r, half_pi, Math::PI, stroke: color, stroke_width: sw)
        draw_arc(x2 - r, y2 - r, r, 0.0, half_pi, stroke: color, stroke_width: sw)
      end

      # ── Circle helpers ────────────────────────────────────────────

      # Fills a circle using midpoint scanline pairs.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param r [Integer] radius
      # @param color [Object] fill color
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def fill_circle(cx, cy, r, color)
        xi = 0
        yi = r
        d = 1 - r

        while xi <= yi
          (-yi..yi).each { |dx| set_pixel(cx + dx, cy + xi, color) }
          (-yi..yi).each { |dx| set_pixel(cx + dx, cy - xi, color) } if xi != 0
          (-xi..xi).each { |dx| set_pixel(cx + dx, cy + yi, color) } if xi != yi
          (-xi..xi).each { |dx| set_pixel(cx + dx, cy - yi, color) } if xi != yi && yi != 0
          xi += 1
          if d.negative?
            d += (2 * xi) + 1
          else
            yi -= 1
            d += (2 * (xi - yi)) + 1
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Strokes a circle outline using midpoint algorithm.
      #
      # For stroke_width > 1, draws a filled annulus.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param r [Integer] radius
      # @param color [Object] stroke color
      # @param sw [Integer] stroke width
      def stroke_circle(cx, cy, r, color, sw)
        if sw <= 1
          midpoint_circle(cx, cy, r, color)
        else
          outer = r + ((sw - 1) / 2)
          inner = r - (sw / 2)
          inner = 0 if inner.negative?
          fill_annulus(cx, cy, outer, inner, color)
        end
      end

      # Draws a single-pixel circle outline using the midpoint algorithm.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param r [Integer] radius
      # @param color [Object] pixel color
      def midpoint_circle(cx, cy, r, color)
        xi = 0
        yi = r
        d = 1 - r

        while xi <= yi
          plot_circle_octants(cx, cy, xi, yi, color)
          xi += 1
          if d.negative?
            d += (2 * xi) + 1
          else
            yi -= 1
            d += (2 * (xi - yi)) + 1
          end
        end
      end

      # Plots the eight symmetric points of a circle.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param xi [Integer] current x offset
      # @param yi [Integer] current y offset
      # @param color [Object] pixel color
      def plot_circle_octants(cx, cy, xi, yi, color)
        set_pixel(cx + xi, cy + yi, color)
        set_pixel(cx - xi, cy + yi, color)
        set_pixel(cx + xi, cy - yi, color)
        set_pixel(cx - xi, cy - yi, color)
        set_pixel(cx + yi, cy + xi, color)
        set_pixel(cx - yi, cy + xi, color)
        set_pixel(cx + yi, cy - xi, color)
        set_pixel(cx - yi, cy - xi, color)
      end

      # Fills the region between two concentric circles (annulus) using scanlines.
      #
      # For each row, computes the outer and inner x-extents and fills only
      # the annular arcs. O(diameter * stroke_width) instead of O(diameter^2).
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param outer [Integer] outer radius
      # @param inner [Integer] inner radius
      # @param color [Object] fill color
      def fill_annulus(cx, cy, outer, inner, color) # rubocop:disable Metrics/AbcSize
        outer_sq = outer * outer
        inner_sq = inner * inner

        (-outer..outer).each do |dy|
          dy_sq = dy * dy
          outer_x = Integer.sqrt(outer_sq - dy_sq)

          if dy_sq >= inner_sq
            # Row is beyond the inner circle — fill the full span
            (-outer_x..outer_x).each { |dx| set_pixel(cx + dx, cy + dy, color) }
          else
            # Row intersects both circles — fill only the left and right arcs
            inner_x = Integer.sqrt(inner_sq - dy_sq)
            (-outer_x..(-inner_x - 1)).each { |dx| set_pixel(cx + dx, cy + dy, color) }
            ((inner_x + 1)..outer_x).each { |dx| set_pixel(cx + dx, cy + dy, color) }
          end
        end
      end

      # ── Ellipse helpers ───────────────────────────────────────────

      # Fills an ellipse using the midpoint ellipse algorithm.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param rx [Integer] horizontal radius
      # @param ry [Integer] vertical radius
      # @param color [Object] fill color
      def fill_ellipse(cx, cy, rx, ry, color)
        midpoint_ellipse(cx, cy, rx, ry) do |x0, x1, y|
          (x0..x1).each { |xi| set_pixel(xi, y, color) }
        end
      end

      # Strokes an ellipse outline.
      #
      # For stroke_width > 1, draws two ellipses (outer - inner annulus).
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param rx [Integer] horizontal radius
      # @param ry [Integer] vertical radius
      # @param color [Object] stroke color
      # @param sw [Integer] stroke width
      def stroke_ellipse(cx, cy, rx, ry, color, sw)
        if sw <= 1
          midpoint_ellipse_outline(cx, cy, rx, ry, color)
        else
          half = (sw - 1) / 2.0
          orx = (rx + half).ceil
          ory = (ry + half).ceil
          irx = [(rx - half).floor, 0].max
          iry = [(ry - half).floor, 0].max
          fill_ellipse_annulus(cx, cy, orx, ory, irx, iry, color)
        end
      end

      # Iterates scanline spans for a filled ellipse using midpoint algorithm.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param rx [Integer] horizontal radius
      # @param ry [Integer] vertical radius
      # @yield [x0, x1, y] horizontal span for each scanline
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def midpoint_ellipse(cx, cy, rx, ry)
        rx2 = rx * rx
        ry2 = ry * ry
        x = 0
        y = ry
        px = 0
        py = 2 * rx2 * y

        # Region 1
        d = ry2 - (rx2 * ry) + (0.25 * rx2)
        while px < py
          yield cx - x, cx + x, cy + y
          yield cx - x, cx + x, cy - y if y != 0
          x += 1
          px += 2 * ry2
          if d.negative?
            d += ry2 + px
          else
            y -= 1
            py -= 2 * rx2
            d += ry2 + px - py
          end
        end

        # Region 2
        d = (ry2 * (x + 0.5) * (x + 0.5)) + (rx2 * (y - 1) * (y - 1)) - (rx2 * ry2)
        while y >= 0
          yield cx - x, cx + x, cy + y
          yield cx - x, cx + x, cy - y if y != 0
          y -= 1
          py -= 2 * rx2
          if d.positive?
            d += rx2 - py
          else
            x += 1
            px += 2 * ry2
            d += rx2 - py + px
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Draws an ellipse outline (single pixel) using midpoint algorithm.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param rx [Integer] horizontal radius
      # @param ry [Integer] vertical radius
      # @param color [Object] pixel color
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def midpoint_ellipse_outline(cx, cy, rx, ry, color)
        rx2 = rx * rx
        ry2 = ry * ry
        x = 0
        y = ry
        px = 0
        py = 2 * rx2 * y

        # Region 1
        d = ry2 - (rx2 * ry) + (0.25 * rx2)
        while px < py
          plot_ellipse_quadrants(cx, cy, x, y, color)
          x += 1
          px += 2 * ry2
          if d.negative?
            d += ry2 + px
          else
            y -= 1
            py -= 2 * rx2
            d += ry2 + px - py
          end
        end

        # Region 2
        d = (ry2 * (x + 0.5) * (x + 0.5)) + (rx2 * (y - 1) * (y - 1)) - (rx2 * ry2)
        while y >= 0
          plot_ellipse_quadrants(cx, cy, x, y, color)
          y -= 1
          py -= 2 * rx2
          if d.positive?
            d += rx2 - py
          else
            x += 1
            px += 2 * ry2
            d += rx2 - py + px
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Plots the four symmetric points of an ellipse.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param xi [Integer] current x offset
      # @param yi [Integer] current y offset
      # @param color [Object] pixel color
      def plot_ellipse_quadrants(cx, cy, xi, yi, color)
        set_pixel(cx + xi, cy + yi, color)
        set_pixel(cx - xi, cy + yi, color)
        set_pixel(cx + xi, cy - yi, color)
        set_pixel(cx - xi, cy - yi, color)
      end

      # Fills the region between two concentric ellipses using scanlines.
      #
      # For each row, computes the outer and inner x-extents and fills only
      # the annular arcs. O(ory * stroke_width) instead of O(orx * ory).
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param orx [Integer] outer horizontal radius
      # @param ory [Integer] outer vertical radius
      # @param irx [Integer] inner horizontal radius
      # @param iry [Integer] inner vertical radius
      # @param color [Object] fill color
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def fill_ellipse_annulus(cx, cy, orx, ory, irx, iry, color)
        return unless orx.positive? && ory.positive?

        (-ory..ory).each do |dy|
          # Outer ellipse x-extent: dx^2 <= orx^2 * (1 - dy^2/ory^2)
          outer_val = 1.0 - ((dy.to_f / ory)**2)
          next if outer_val.negative?

          outer_x = (orx * Math.sqrt(outer_val)).round
          has_inner_hole = irx.positive? && iry.positive? && dy.abs < iry

          if has_inner_hole
            inner_val = 1.0 - ((dy.to_f / iry)**2)
            inner_x = (irx * Math.sqrt(inner_val)).round
            (-outer_x..(-inner_x - 1)).each { |dx| set_pixel(cx + dx, cy + dy, color) }
            ((inner_x + 1)..outer_x).each { |dx| set_pixel(cx + dx, cy + dy, color) }
          else
            (-outer_x..outer_x).each { |dx| set_pixel(cx + dx, cy + dy, color) }
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # ── Arc helper ────────────────────────────────────────────────

      # Draws an arc by walking the midpoint circle and filtering by angle.
      #
      # @param cx [Integer] center x
      # @param cy [Integer] center y
      # @param r [Integer] radius
      # @param start_angle [Float] start angle in radians
      # @param end_angle [Float] end angle in radians
      # @param color [Object] pixel color
      # @param sw [Integer] stroke width
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def draw_arc_pixels(cx, cy, r, start_angle, end_angle, color, sw)
        # Normalize angles to [0, 2π)
        two_pi = 2 * Math::PI
        sa = start_angle % two_pi
        ea = end_angle % two_pi

        radii = sw <= 1 ? [r] : ((r - (sw / 2))..[r + ((sw - 1) / 2)]).to_a.select(&:positive?)

        radii.each do |current_r|
          xi = 0
          yi = current_r
          d = 1 - current_r

          while xi <= yi
            each_circle_octant(xi, yi) do |dx, dy|
              angle = Math.atan2(-dy, dx) % two_pi
              set_pixel(cx + dx, cy + dy, color) if angle_in_range?(angle, sa, ea)
            end
            xi += 1
            if d.negative?
              d += (2 * xi) + 1
            else
              yi -= 1
              d += (2 * (xi - yi)) + 1
            end
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Yields all 8 octant reflections for a circle point.
      #
      # @param xi [Integer] x offset
      # @param yi [Integer] y offset
      # @yield [dx, dy] reflected coordinate offsets
      def each_circle_octant(xi, yi)
        yield  xi,  yi
        yield -xi,  yi
        yield  xi, -yi
        yield -xi, -yi
        yield  yi,  xi
        yield -yi,  xi
        yield  yi, -xi
        yield -yi, -xi
      end

      # Tests if an angle falls within a range (handling wrap-around).
      #
      # @param angle [Float] the angle to test (0..2π)
      # @param sa [Float] start angle (0..2π)
      # @param ea [Float] end angle (0..2π)
      # @return [Boolean]
      def angle_in_range?(angle, sa, ea)
        if sa <= ea
          angle.between?(sa, ea)
        else
          # Wrap-around case: e.g. 350° to 10°
          angle >= sa || angle <= ea
        end
      end

      # ── Polygon fill ──────────────────────────────────────────────

      # Fills a polygon using scanline edge-intersection.
      #
      # @param points [Array<Array(Integer, Integer)>] polygon vertices
      # @param color [Object] fill color
      def fill_polygon(points, color)
        ys = points.map(&:last)
        min_y = ys.min
        max_y = ys.max

        (min_y..max_y).each do |scan_y|
          intersections = polygon_intersections(points, scan_y)
          intersections.sort!
          intersections.each_slice(2) do |x_start, x_end|
            next unless x_end

            (x_start..x_end).each { |x| set_pixel(x, scan_y, color) }
          end
        end
      end

      # Computes x-intersections of polygon edges with a scanline.
      #
      # @param points [Array<Array(Integer, Integer)>] polygon vertices
      # @param scan_y [Integer] the scanline y coordinate
      # @return [Array<Integer>] sorted x-intersection values
      def polygon_intersections(points, scan_y)
        intersections = []
        n = points.length

        n.times do |i|
          x0, y0 = points[i]
          x1, y1 = points[(i + 1) % n]

          # Skip horizontal edges; ensure y0 < y1
          next if y0 == y1

          y0, y1, x0, x1 = y1, y0, x1, x0 if y0 > y1

          next unless scan_y >= y0 && scan_y < y1

          x_intersect = x0 + ((scan_y - y0) * (x1 - x0) / (y1 - y0))
          intersections << x_intersect
        end

        intersections
      end

      # ── Scanline flood fill ───────────────────────────────────────

      # Scanline flood fill: O(pixels) time, O(height) stack.
      #
      # @param x [Integer] seed x
      # @param y [Integer] seed y
      # @param target [Object] the color being replaced
      # @param replacement [Object] the new color
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def scanline_fill(x, y, target, replacement)
        stack = [[x, y]]

        until stack.empty?
          sx, sy = stack.pop
          next unless in_bounds?(sx, sy) && get_pixel(sx, sy) == target

          # Scan left
          lx = sx
          lx -= 1 while lx.positive? && get_pixel(lx - 1, sy) == target
          # Scan right
          rx = sx
          rx += 1 while rx < width - 1 && get_pixel(rx + 1, sy) == target

          # Fill the span
          (lx..rx).each { |xi| set_pixel(xi, sy, replacement) }

          # Push spans above and below
          scan_push(stack, lx, rx, sy - 1, target) if sy.positive?
          scan_push(stack, lx, rx, sy + 1, target) if sy < height - 1
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Pushes seed points for adjacent scanline spans.
      #
      # @param stack [Array] the work stack
      # @param lx [Integer] left bound
      # @param rx [Integer] right bound
      # @param y [Integer] adjacent scanline y
      # @param target [Object] the target color
      def scan_push(stack, lx, rx, y, target)
        added = false
        (lx..rx).each do |xi|
          if get_pixel(xi, y) == target
            stack.push([xi, y]) unless added
            added = true
          else
            added = false
          end
        end
      end
    end
  end
end

# Include drawing primitives into Surface so all surfaces can draw.
ChromaWave::Surface.include(ChromaWave::Drawing::Primitives)
