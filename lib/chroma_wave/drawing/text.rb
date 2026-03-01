# frozen_string_literal: true

module ChromaWave
  module Drawing
    # Text drawing mixin for {Canvas} and {Layer}.
    #
    # Provides +draw_text+ with word wrapping, alignment, and anti-aliased
    # glyph rendering via alpha compositing. Included only into Color-based
    # surfaces (Canvas, Layer), not into Framebuffer whose +get_pixel+
    # returns palette symbols.
    module Text
      # Draws text onto the surface with optional word wrapping and alignment.
      #
      # Each glyph pixel is alpha-composited against the surface background.
      # Fully opaque pixels (alpha 255) are set directly for performance.
      #
      # @param text [String] the text to render
      # @param x [Integer] left edge of the alignment box.
      #   For +align: :left+, text starts at this x coordinate.
      #   For +align: :center+ or +:right+, text is offset within the
      #   box of width +max_width+ starting at this x coordinate.
      # @param y [Integer] top of the first line (not baseline)
      # @param font [Font] loaded Font instance
      # @param color [Color] text color (alpha channel ignored — glyph alpha used)
      # @param align [:left, :center, :right] horizontal alignment within the
      #   alignment box (requires +max_width+ for +:center+ and +:right+)
      # @param max_width [Integer, nil] width of the alignment box; also used
      #   for word wrapping
      # @param line_spacing [Float] multiplier for line height (default 1.2)
      # @return [self]
      def draw_text(text, x:, y:, font:, color:, align: :left, max_width: nil, line_spacing: 1.2) # rubocop:disable Metrics/ParameterLists
        lines = max_width ? word_wrap(text, font, max_width) : text.split("\n", -1)
        line_h = (font.line_height * line_spacing).round

        lines.each_with_index do |line, i|
          line_y = y + (i * line_h)
          line_x = compute_text_x(line, x, font, align, max_width)
          render_line(line, line_x, line_y, font, color)
        end

        self
      end

      private

      # Renders a single line of text at the given position.
      #
      # @param line [String] text line
      # @param x [Integer] x position
      # @param y [Integer] y position (top of line)
      # @param font [Font] loaded Font
      # @param color [Color] text color
      def render_line(line, x, y, font, color)
        font.each_glyph(line) do |glyph|
          render_glyph(glyph, x, y, color)
        end
      end

      # Alpha-composites a single glyph bitmap onto the surface.
      #
      # For each pixel in the glyph bitmap, if the alpha value is > 0,
      # the pixel is composited using source-over blending. Fully opaque
      # pixels (alpha 255) skip compositing for performance. Anti-aliased
      # pixels are blended inline to avoid per-pixel Color allocations.
      #
      # @param glyph [Hash] glyph data from Font#each_glyph
      # @param base_x [Integer] line start x
      # @param base_y [Integer] line start y
      # @param color [Color] text foreground color
      def render_glyph(glyph, base_x, base_y, color) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        bitmap = glyph[:bitmap]
        gw     = glyph[:width]
        gh     = glyph[:height]
        gx     = base_x + glyph[:x]
        gy     = base_y + glyph[:y]

        gh.times do |row|
          py = gy + row
          next if py.negative? || py >= height

          gw.times do |col|
            px = gx + col
            next if px.negative? || px >= width

            # Bitmap is packed (stride == width) by ft_render_glyph in freetype.c
            alpha = bitmap.getbyte((row * gw) + col)
            next if alpha.zero?

            if alpha == 255
              set_pixel(px, py, color)
            else
              bg = get_pixel(px, py)
              set_pixel(px, py, blend_over(color, alpha, bg)) if bg
            end
          end
        end
      end

      # Source-over alpha composites a foreground color at a given alpha
      # onto a background color.
      #
      # Uses an integer-only fast path when the background is opaque
      # (the common case for e-paper canvases) to avoid floating-point
      # arithmetic and per-channel validation overhead.
      #
      # @param foreground [Color] foreground color (RGB channels used)
      # @param alpha [Integer] foreground alpha (0..255)
      # @param background [Color] background color (RGBA)
      # @return [Color] composited result with correct alpha
      def blend_over(foreground, alpha, background)
        if background.opaque?
          blend_over_opaque(foreground, alpha, background)
        else
          blend_over_general(foreground, alpha, background)
        end
      end

      # Fast path for opaque backgrounds (a_out = 1.0, result is always opaque).
      #
      # Integer math with rounding: blended = (fg * alpha + bg * (255 - alpha) + 127) / 255
      #
      # @param foreground [Color] foreground color (RGB channels used)
      # @param alpha [Integer] foreground alpha (0..255)
      # @param background [Color] background color (opaque)
      # @return [Color] composited result (always opaque)
      def blend_over_opaque(foreground, alpha, background)
        inv = 255 - alpha
        Color.new(
          r: ((foreground.r * alpha) + (background.r * inv) + 127) / 255,
          g: ((foreground.g * alpha) + (background.g * inv) + 127) / 255,
          b: ((foreground.b * alpha) + (background.b * inv) + 127) / 255
        )
      end

      # General source-over blend for semi-transparent backgrounds.
      #
      # RGB channels are weighted by computed Porter-Duff alpha for
      # correctness, but the output alpha is clamped to 255 (opaque)
      # to match the C accelerator (+_canvas_blit_glyph+) and
      # +Color#over+ semantics.
      #
      # @param foreground [Color] foreground color
      # @param alpha [Integer] foreground alpha (0..255)
      # @param background [Color] background color
      # @return [Color] composited result (always opaque)
      def blend_over_general(foreground, alpha, background) # rubocop:disable Metrics/AbcSize
        a_fg = alpha / 255.0
        a_bg = background.a / 255.0
        a_out = a_fg + (a_bg * (1.0 - a_fg))

        return Color::TRANSPARENT if a_out.zero?

        inv = a_bg * (1.0 - a_fg) / a_out
        w_fg = a_fg / a_out
        Color.new(
          r: ((foreground.r * w_fg) + (background.r * inv)).round,
          g: ((foreground.g * w_fg) + (background.g * inv)).round,
          b: ((foreground.b * w_fg) + (background.b * inv)).round
        )
      end

      # Breaks text into lines that fit within max_width pixels.
      #
      # Respects explicit newlines (+\n+) first, then applies greedy
      # word-boundary wrapping within each paragraph. Words that exceed
      # max_width on their own are placed on their own line without breaking.
      #
      # @param text [String] text to wrap
      # @param font [Font] loaded Font for measurement
      # @param max_width [Integer] maximum line width in pixels
      # @return [Array<String>] wrapped lines
      def word_wrap(text, font, max_width)
        text.split("\n", -1).flat_map { |paragraph| wrap_paragraph(paragraph, font, max_width) }
      end

      # Wraps a single paragraph (no embedded newlines) to max_width.
      #
      # Leading/trailing whitespace is stripped and internal runs of
      # whitespace are collapsed to a single space. This is intentional --
      # e-paper text rendering has no use for preserved whitespace runs.
      #
      # Uses incremental width accumulation (O(N) font measurements) rather
      # than re-measuring the entire candidate line for each word (O(N^2)).
      # Each word is measured once, and the space width is cached outside
      # the loop since it is constant for a given font.
      #
      # @param paragraph [String] a single line of text
      # @param font [Font] loaded Font for measurement
      # @param max_width [Integer] maximum line width in pixels
      # @return [Array<String>] wrapped lines
      def wrap_paragraph(paragraph, font, max_width)
        words = paragraph.split(/\s+/).reject(&:empty?)
        return [''] if words.empty?

        space_width = font.measure(' ').width
        lines = []
        current = words.shift
        current_width = font.measure(current).width

        words.each do |word|
          word_width = font.measure(word).width
          candidate_width = current_width + space_width + word_width

          if candidate_width <= max_width
            current = "#{current} #{word}"
            current_width = candidate_width
          else
            lines << current
            current = word
            current_width = word_width
          end
        end
        lines << current
      end

      # Computes the x offset for a line based on alignment.
      #
      # @param line [String] the text line
      # @param x [Integer] base x position
      # @param font [Font] loaded Font for measurement
      # @param align [Symbol] :left, :center, or :right
      # @param max_width [Integer, nil] area width for alignment
      # @return [Integer] adjusted x position
      # @raise [ArgumentError] if align is not :left and max_width is nil
      def compute_text_x(line, x, font, align, max_width)
        return x if align == :left

        raise ArgumentError, "max_width is required for #{align.inspect} alignment" if max_width.nil?

        line_w = font.measure(line).width
        case align
        when :center then x + ((max_width - line_w) / 2)
        when :right  then x + (max_width - line_w)
        else raise ArgumentError, "unknown align: #{align.inspect} (expected :left, :center, or :right)"
        end
      end
    end
  end
end

# Included into Canvas and Layer by lib/chroma_wave.rb after both classes
# are defined. Not included into Framebuffer (palette-based get_pixel).
