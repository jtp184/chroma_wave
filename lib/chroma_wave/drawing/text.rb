# frozen_string_literal: true

module ChromaWave
  module Drawing
    # Text drawing mixin for {Surface} implementations.
    #
    # Provides +draw_text+ with word wrapping, alignment, and anti-aliased
    # glyph rendering via alpha compositing. Mixed into Surface alongside
    # {Drawing::Primitives}.
    module Text
      # Draws text onto the surface with optional word wrapping and alignment.
      #
      # Each glyph pixel is alpha-composited against the surface background.
      # Fully opaque pixels (alpha 255) are set directly for performance.
      #
      # @param text [String] the text to render
      # @param x [Integer] left edge for :left alignment, center for :center
      # @param y [Integer] top of the first line (not baseline)
      # @param font [Font] loaded Font instance
      # @param color [Color] text color (alpha channel ignored — glyph alpha used)
      # @param align [:left, :center, :right] horizontal alignment
      # @param max_width [Integer, nil] maximum width before word wrapping
      # @param line_spacing [Float] multiplier for line height (default 1.2)
      # @return [self]
      def draw_text(text, x:, y:, font:, color:, align: :left, max_width: nil, line_spacing: 1.2) # rubocop:disable Metrics/ParameterLists
        lines = max_width ? word_wrap(text, font, max_width) : [text]
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
      # pixels (alpha 255) skip compositing for performance.
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

            alpha = bitmap.getbyte((row * gw) + col)
            next if alpha.zero?

            if alpha == 255
              set_pixel(px, py, color)
            else
              fg = Color.new(r: color.r, g: color.g, b: color.b, a: alpha)
              bg = get_pixel(px, py)
              set_pixel(px, py, fg.over(bg)) if bg
            end
          end
        end
      end

      # Breaks text into lines that fit within max_width pixels.
      #
      # Uses greedy word-boundary wrapping. Words that exceed max_width
      # on their own are placed on their own line without breaking.
      #
      # @param text [String] text to wrap
      # @param font [Font] loaded Font for measurement
      # @param max_width [Integer] maximum line width in pixels
      # @return [Array<String>] wrapped lines
      def word_wrap(text, font, max_width)
        words = text.split(/\s+/)
        return [''] if words.empty?

        lines = []
        current = words.shift

        words.each do |word|
          candidate = "#{current} #{word}"
          if font.measure(candidate).width <= max_width
            current = candidate
          else
            lines << current
            current = word
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
      def compute_text_x(line, x, font, align, max_width)
        return x if align == :left || max_width.nil?

        line_w = font.measure(line).width
        case align
        when :center then x + ((max_width - line_w) / 2)
        when :right  then x + (max_width - line_w)
        else x
        end
      end
    end
  end
end

ChromaWave::Surface.include(ChromaWave::Drawing::Text)
