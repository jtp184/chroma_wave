# frozen_string_literal: true

module ChromaWave
  # An ordered, immutable color lookup table (CLT) for pixel formats.
  #
  # Each entry is a +Symbol+ name from {Color::NAME_MAP}. The entry index
  # matches the hardware integer value for that color — making Palette
  # the bridge between symbolic colors and the C framebuffer's integers.
  #
  # @example
  #   palette = Palette[:black, :white]
  #   palette.index_of(:black)  # => 0
  #   palette.color_at(1)       # => :white
  class Palette
    include Enumerable

    # Creates a new Palette from an array of named color entries.
    #
    # @param entries [Array<Symbol>] color names that must exist in {Color::NAME_MAP}
    # @raise [ArgumentError] if any entry is not a registered color name
    def initialize(entries)
      entries = entries.dup.freeze
      validate_entries!(entries)

      @entries = entries
      @index = entries.each_with_index.to_h.freeze
      @rgba_by_entry = entries.map { |name| Color.from_name(name) }.freeze
      @nearest_cache = {}
    end

    # Bracket constructor for creating palettes concisely.
    #
    # @param entries [Array<Symbol>] color names
    # @return [Palette]
    # @example
    #   Palette[:black, :white, :red]
    def self.[](*entries)
      new(entries)
    end

    # Iterates over each entry name in palette order.
    #
    # @yieldparam name [Symbol] color name
    # @return [Enumerator] if no block given
    def each(&)
      entries.each(&)
    end

    # Returns the number of entries in the palette.
    #
    # @return [Integer]
    def size
      entries.length
    end

    # Returns true if the palette contains the given color name.
    #
    # @param name [Symbol] color name to check
    # @return [Boolean]
    def include?(name)
      index.key?(name)
    end

    # Returns the integer index for a palette color name.
    #
    # This is the integer value used by the C framebuffer for this color.
    #
    # @param name [Symbol] color name
    # @return [Integer] the palette index
    # @raise [KeyError] if the name is not in this palette
    def index_of(name)
      index.fetch(name)
    end

    # Returns the color name at a given integer index.
    #
    # @param idx [Integer] the palette index
    # @return [Symbol] the color name
    # @raise [IndexError] if the index is out of range
    def color_at(idx)
      entries.fetch(idx)
    end

    # Finds the nearest palette color to an arbitrary RGBA color.
    #
    # Uses redmean perceptual distance for better color matching.
    # Results are memoized by the packed 32-bit integer key for
    # zero-allocation cache hits. The cache is unbounded; for palettes
    # with few entries (typical for e-ink), the practical key space is
    # small. Clear the palette and create a new one if memory is a concern.
    #
    # @param rgba [Color] the color to match
    # @return [Symbol] the nearest palette entry name
    def nearest_color(rgba)
      key = pack_key(rgba)
      nearest_cache.fetch(key) { nearest_cache[key] = compute_nearest(rgba) }
    end

    # Value equality based on the ordered entry list.
    #
    # @param other [Object] object to compare
    # @return [Boolean]
    def ==(other)
      other.is_a?(self.class) && entries == other.entries
    end
    alias eql? ==

    # Hash code consistent with {#==}.
    #
    # @return [Integer]
    def hash
      [self.class, entries].hash
    end

    # @return [String] human-readable representation
    def inspect
      "#<#{self.class} [#{entries.join(', ')}]>"
    end

    protected

    attr_reader :entries

    private

    attr_reader :index, :rgba_by_entry, :nearest_cache

    # Validates that entries are non-empty, unique, and registered color names.
    #
    # @param entries [Array<Symbol>] color names to validate
    # @raise [ArgumentError] if entries is empty, contains duplicates, or has unknown names
    def validate_entries!(entries)
      raise ArgumentError, 'palette must have at least one entry' if entries.empty?

      seen = {}
      entries.each do |name|
        raise ArgumentError, "duplicate palette entry: #{name.inspect}" if seen.key?(name)

        unless Color::NAME_MAP.key?(name)
          raise ArgumentError,
                "unknown color name: #{name.inspect} (registered: #{Color::NAME_MAP.keys.join(', ')})"
        end
        seen[name] = true
      end
    end

    # Packs an RGB color into a 24-bit integer cache key.
    #
    # Alpha is excluded because the redmean distance calculation
    # operates on RGB only — colors should be composited to opaque
    # before palette matching.
    #
    # @param rgba [Color] the color
    # @return [Integer] packed 24-bit key
    def pack_key(rgba)
      (rgba.r << 16) | (rgba.g << 8) | rgba.b
    end

    # Computes the nearest palette entry using redmean perceptual distance.
    #
    # Redmean formula weights R/G/B channels differently based on the
    # average red value, providing better perceptual accuracy than
    # simple Euclidean distance, particularly for dark colors.
    #
    # @param rgba [Color] the color to match
    # @return [Symbol] nearest palette entry name
    def compute_nearest(rgba)
      min_entry = nil
      min_dist = Float::INFINITY

      entries.each_with_index do |name, i|
        candidate = rgba_by_entry[i]
        dist = redmean_distance(rgba, candidate)
        if dist < min_dist
          min_dist = dist
          min_entry = name
        end
      end

      min_entry
    end

    # Calculates the redmean perceptual color distance.
    #
    # @param c1 [Color] first color
    # @param c2 [Color] second color
    # @return [Float] perceptual distance (lower = more similar)
    def redmean_distance(c1, c2)
      r_mean = (c1.r + c2.r) / 2.0
      dr = c1.r - c2.r
      dg = c1.g - c2.g
      db = c1.b - c2.b

      ((2 + (r_mean / 256.0)) * dr * dr) +
        (4 * dg * dg) +
        ((2 + ((255 - r_mean) / 256.0)) * db * db)
    end
  end
end
