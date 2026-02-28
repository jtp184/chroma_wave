# frozen_string_literal: true

require_relative 'icon_font/lucide_glyphs'

module ChromaWave
  # Renders named icons from an icon font via codepoint lookup.
  #
  # Extends {Font} with a symbol-to-codepoint registry so icons can be
  # drawn by name instead of raw codepoint.
  #
  # @example
  #   icons = IconFont.lucide(size: 24)
  #   icons.draw(canvas, :house, x: 10, y: 10, color: Color::BLACK)
  #   icons.icon_names  #=> [:a_arrow_down, :a_arrow_up, ...]
  class IconFont < Font
    attr_reader :glyph_map

    # Creates an IconFont from a font file with a glyph name registry.
    #
    # @param path_or_name [String] path or name of the icon font
    # @param size [Integer] pixel size for rendering
    # @param glyph_map [Hash{Symbol => Integer}] name-to-codepoint map
    def initialize(path_or_name, size:, glyph_map: {})
      @glyph_map = glyph_map.freeze
      super(path_or_name, size: size)
    end

    # Renders a named icon onto a surface.
    #
    # @param surface [Surface] the surface to draw on
    # @param name [Symbol] icon name from the glyph map
    # @param x [Integer] x position
    # @param y [Integer] y position
    # @param color [Color] icon color
    # @return [surface]
    # @raise [KeyError] if the icon name is not in the glyph map
    def draw(surface, name, x:, y:, color:)
      cp = glyph_map.fetch(name)
      surface.draw_text(cp.chr(Encoding::UTF_8), x: x, y: y, font: self, color: color)
    end

    # Returns a sorted list of available icon names.
    #
    # @return [Array<Symbol>]
    def icon_names
      @icon_names ||= glyph_map.keys.sort.freeze
    end

    # Measures a named icon.
    #
    # @param name [Symbol] icon name from the glyph map
    # @return [TextMetrics]
    # @raise [KeyError] if the icon name is not in the glyph map
    def measure_icon(name)
      cp = glyph_map.fetch(name)
      measure(cp.chr(Encoding::UTF_8))
    end

    # Factory: returns an IconFont using the bundled Lucide icon font.
    #
    # @param size [Integer] pixel size
    # @return [IconFont]
    def self.lucide(size:)
      new(File.join(DATA_DIR, 'fonts', 'lucide.ttf'),
          size: size, glyph_map: LUCIDE_GLYPHS)
    end
  end
end
