# frozen_string_literal: true

module ChromaWave
  # Loads a TrueType font and provides glyph measurement and iteration.
  #
  # Wraps the FreeType C bindings (see +freetype.c+) with a Ruby interface
  # for font discovery, text measurement, and glyph-by-glyph iteration.
  #
  # When FreeType is not available (compiled with +-DNO_FREETYPE+),
  # +Font.new+ raises +DependencyError+ with an install hint.
  #
  # @example Load by path
  #   font = Font.new('/usr/share/fonts/TTF/DejaVuSans.ttf', size: 24)
  #
  # @example Load by name (discovered from system dirs)
  #   font = Font.new('DejaVu Sans', size: 16)
  #
  # @example Use the bundled default font
  #   font = Font.default(size: 20)
  class Font
    # Standard system font directories to search.
    FONT_DIRS = [
      '/usr/share/fonts',
      '/usr/local/share/fonts',
      '~/.fonts',
      '~/.local/share/fonts'
    ].freeze

    # Path to the gem's bundled data directory.
    DATA_DIR = File.expand_path('../../data', __dir__).freeze

    # Glob pattern for TrueType files.
    TTF_GLOB = '**/*.{ttf,TTF}'

    # Mutex protecting the class-level font discovery cache.
    FONT_CACHE_MUTEX = Mutex.new

    # @!visibility private
    class << self
      private

      attr_accessor :font_cache
    end

    attr_reader :path, :size

    # Loads a font from a file path or discovers it by name.
    #
    # @param path_or_name [String] absolute path to a +.ttf+ file, or a
    #   font name to discover (e.g. +'DejaVu Sans'+)
    # @param size [Integer] pixel size for rendering
    # @raise [DependencyError] if FreeType is not available
    # @raise [ArgumentError] if the font cannot be found or loaded
    def initialize(path_or_name, size:)
      assert_freetype!

      @size = size
      @path = resolve_path(path_or_name)
      _ft_load_face(@path, @size)
    end

    # Measures the pixel dimensions of rendered text.
    #
    # @note Kerning is not applied — each glyph advance is summed
    #   independently. This is sufficient for e-paper displays but
    #   may overestimate width for tightly-kerned pairs like "AV".
    #
    # @param text [String] the text to measure
    # @return [TextMetrics] width, height, ascent, and descent
    def measure(text)
      w = 0
      text.each_codepoint do |cp|
        m = _ft_glyph_metrics(cp)
        w += m[:advance_x]
      end
      TextMetrics.new(width: w, height: line_height, ascent: ascent, descent: descent)
    end

    # Iterates over each glyph in the text, yielding positioned glyph data.
    #
    # @note Kerning is not applied between glyphs.
    #
    # Each yielded hash contains:
    # - +:bitmap+ — grayscale alpha String (1 byte/pixel)
    # - +:x+ — horizontal position (pen x + bearing_x)
    # - +:y+ — vertical position relative to baseline (ascent - bearing_y)
    # - +:width+ — bitmap width in pixels
    # - +:height+ — bitmap height in pixels
    #
    # @param text [String] the text to iterate
    # @yield [Hash] glyph data for each character
    # @return [Enumerator] if no block given
    def each_glyph(text, &block)
      return enum_for(:each_glyph, text) unless block

      pen_x = 0
      text.each_codepoint do |cp|
        glyph = _ft_render_glyph(cp)

        yield({
          bitmap: glyph[:bitmap],
          x: pen_x + glyph[:bearing_x],
          y: ascent - glyph[:bearing_y],
          width: glyph[:width],
          height: glyph[:height]
        })

        pen_x += glyph[:advance_x]
      end
    end

    # Returns the line height in pixels.
    #
    # @return [Integer]
    def line_height
      _ft_line_height
    end

    # Returns the ascent (baseline to top) in pixels.
    #
    # @return [Integer]
    def ascent
      _ft_ascent
    end

    # Returns the descent (baseline to bottom) in pixels.
    #
    # @return [Integer] positive value
    def descent
      _ft_descent
    end

    # Returns a human-readable description.
    #
    # @return [String]
    def inspect
      "#<#{self.class} #{File.basename(path)} @#{size}px>"
    end

    # Factory: returns a Font using the bundled DejaVu Sans.
    #
    # @param size [Integer] pixel size
    # @return [Font]
    def self.default(size:)
      new(File.join(DATA_DIR, 'fonts', 'dejavu-sans.ttf'), size: size)
    end

    # Clears the font discovery cache.
    #
    # Call this after installing new fonts to pick up changes.
    #
    # @return [void]
    def self.clear_font_cache!
      FONT_CACHE_MUTEX.synchronize { self.font_cache = nil }
    end

    private

    # Raises DependencyError when FreeType is not compiled in.
    #
    # @raise [DependencyError]
    def assert_freetype!
      return if respond_to?(:_ft_load_face, true)

      raise DependencyError,
            'FreeType is required for text rendering. ' \
            'Install libfreetype-dev and recompile the gem.'
    end

    # Resolves a path or font name to an absolute file path.
    #
    # @param path_or_name [String] path or name
    # @return [String] absolute path to a .ttf file
    # @raise [ArgumentError] if the font cannot be found
    def resolve_path(path_or_name)
      return File.expand_path(path_or_name) if File.exist?(path_or_name)

      discover_font(path_or_name) ||
        raise(ArgumentError, "font not found: #{path_or_name.inspect}")
    end

    # Searches bundled and system font directories for a matching font.
    #
    # Results are cached at the class level. Call {.clear_font_cache!}
    # to pick up newly installed fonts.
    #
    # Checks the gem's +data/fonts/+ first, then system dirs.
    # Tries exact stem match, then case-insensitive partial match.
    #
    # @param name [String] font name to search for
    # @return [String, nil] absolute path or nil
    def discover_font(name)
      stem = normalize_name(name)
      candidates = font_candidates

      # Exact match first, then fuzzy partial match
      candidates.find { |s, _| s == stem }&.last ||
        candidates.find { |s, _| s.include?(stem) }&.last
    end

    # Returns cached font candidates, building the cache on first call.
    #
    # Thread-safe via {FONT_CACHE_MUTEX}.
    #
    # @return [Array<Array(String, String)>] pairs of [normalized_stem, path]
    def font_candidates
      # Fast path — avoid Mutex overhead when cache is warm
      cache = self.class.send(:font_cache)
      return cache if cache

      FONT_CACHE_MUTEX.synchronize do
        self.class.send(:font_cache) || begin
          search_dirs = [File.join(DATA_DIR, 'fonts')] + FONT_DIRS.map { |d| File.expand_path(d) }
          result = collect_font_candidates(search_dirs)
          self.class.send(:font_cache=, result)
          result
        end
      end
    end

    # Collects font paths and their normalized stems from search directories.
    #
    # @param dirs [Array<String>] directories to search
    # @return [Array<Array(String, String)>] pairs of [normalized_stem, path]
    def collect_font_candidates(dirs)
      dirs.each_with_object([]) do |dir, result|
        next unless File.directory?(dir)

        Dir.glob(File.join(dir, TTF_GLOB)).each do |font_path|
          stem = normalize_name(File.basename(font_path, File.extname(font_path)))
          result << [stem, font_path]
        end
      end
    end

    # Normalizes a font name for comparison: lowercase, strip non-alphanumeric.
    #
    # @param name [String]
    # @return [String]
    def normalize_name(name)
      name.downcase.gsub(/[^a-z0-9]/, '')
    end
  end
end
