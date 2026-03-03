# frozen_string_literal: true

module ChromaWave
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
        value = yield
        store[key] = value
        store.shift if store.size > capacity
        value
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
end
