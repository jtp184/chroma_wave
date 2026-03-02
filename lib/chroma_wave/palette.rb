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

    # A minimal LRU cache backed by Ruby's insertion-ordered Hash.
    #
    # On hit the entry is moved to the tail (most-recently-used).
    # On miss after insert the head (least-recently-used) is evicted
    # when the cache exceeds its capacity.
    #
    # @api private
    class LruCache
      # Default maximum number of cached entries.
      DEFAULT_CAPACITY = 4096

      # Creates an LRU cache with the given capacity.
      #
      # @param capacity [Integer] maximum entries before eviction
      def initialize(capacity: DEFAULT_CAPACITY)
        @capacity = capacity
        @store = {}
      end

      # Fetches the value for +key+, or computes and stores it via the block.
      #
      # @param key [Object] the cache key
      # @yield computes the value on cache miss
      # @return [Object] the cached or computed value
      def fetch(key)
        if store.key?(key)
          value = store.delete(key)
          store[key] = value
        else
          store[key] = yield
          store.shift if store.size > capacity
          store[key]
        end
      end

      # Returns the number of cached entries.
      #
      # @return [Integer]
      def size
        store.size
      end

      private

      attr_reader :capacity, :store
    end

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
      @lab_by_entry = @rgba_by_entry.map(&:to_lab).freeze
      @nearest_cache = LruCache.new
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
    # Uses CIE76 Delta E distance in L*a*b* space for perceptually
    # accurate color matching. Results are memoized by the packed
    # 24-bit integer key for zero-allocation cache hits. The cache
    # is LRU-bounded to {LruCache::DEFAULT_CAPACITY} entries to
    # prevent unbounded growth when mapping large images through
    # long-lived palette constants.
    #
    # @param rgba [Color] the color to match
    # @return [Symbol] the nearest palette entry name
    def nearest_color(rgba)
      key = pack_key(rgba)
      nearest_cache.fetch(key) { compute_nearest(rgba) }
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

    attr_reader :index, :rgba_by_entry, :lab_by_entry, :nearest_cache

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
    # Alpha is excluded because the CIE Lab distance calculation
    # operates on RGB only — colors should be composited to opaque
    # before palette matching.
    #
    # @param rgba [Color] the color
    # @return [Integer] packed 24-bit key
    def pack_key(rgba)
      (rgba.r << 16) | (rgba.g << 8) | rgba.b
    end

    # Computes the nearest palette entry using CIE76 Delta E distance.
    #
    # Converts the input pixel to L*a*b* via {Color.compute_lab} and
    # compares against pre-computed {#lab_by_entry} values. Uses squared
    # Delta E to avoid an unnecessary +sqrt+ (valid since we only need
    # ordering, not absolute magnitude).
    #
    # @param rgba [#r, #g, #b] the color to match (Color or duck-typed RGB)
    # @return [Symbol] nearest palette entry name
    def compute_nearest(rgba)
      pixel_lab = Color.compute_lab(rgba.r, rgba.g, rgba.b)
      min_entry = nil
      min_dist = Float::INFINITY

      entries.each_with_index do |name, i|
        dist = delta_e_squared(pixel_lab, lab_by_entry[i])
        if dist < min_dist
          min_dist = dist
          min_entry = name
        end
      end

      min_entry
    end

    # Calculates the squared CIE76 Delta E between two L*a*b* triples.
    #
    # @param lab1 [Array(Float, Float, Float)] [L*, a*, b*]
    # @param lab2 [Array(Float, Float, Float)] [L*, a*, b*]
    # @return [Float] squared perceptual distance (lower = more similar)
    def delta_e_squared(lab1, lab2)
      dl = lab1[0] - lab2[0]
      da = lab1[1] - lab2[1]
      db = lab1[2] - lab2[2]

      (dl * dl) + (da * da) + (db * db)
    end
  end
end
