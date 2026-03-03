# frozen_string_literal: true

module ChromaWave
  # Tracks partial refresh counts and enforces minimum intervals between refreshes.
  #
  # E-paper displays accumulate ghosting artifacts after repeated partial refreshes.
  # Waveshare recommends periodic full refreshes to clear this. RefreshScheduler
  # is a pure data/logic class (no hardware interaction) that tracks refresh counts,
  # warns on rapid-fire updates, and signals when a maintenance full refresh is due.
  #
  # Used internally by {Capabilities::ManagedRefresh}; not typically instantiated
  # directly.
  #
  # @example
  #   scheduler = RefreshScheduler.new(partial_limit: 5, min_interval: 180)
  #   scheduler.track_partial!
  #   scheduler.partial_count   # => 1
  #   scheduler.needs_full?     # => false
  class RefreshScheduler
    # Default number of partial refreshes before a full refresh is recommended.
    DEFAULT_PARTIAL_LIMIT = 5

    # Default minimum interval (seconds) between refreshes before a warning is issued.
    DEFAULT_MIN_INTERVAL = 180

    attr_reader :partial_count, :last_refresh_at, :partial_limit, :min_interval

    # Creates a new RefreshScheduler with configurable thresholds.
    #
    # @param partial_limit [Integer] number of partial refreshes before a full refresh
    #   is recommended (default: {DEFAULT_PARTIAL_LIMIT}). Must be >= 1.
    # @param min_interval [Numeric] minimum seconds between refreshes before a
    #   warning is issued (default: {DEFAULT_MIN_INTERVAL})
    # @param auto_full_refresh [Boolean] whether to automatically trigger a full
    #   refresh when the partial limit is reached (default: +true+)
    def initialize(partial_limit: DEFAULT_PARTIAL_LIMIT,
                   min_interval: DEFAULT_MIN_INTERVAL,
                   auto_full_refresh: true)
      validate_params!(partial_limit, min_interval)
      @partial_limit = partial_limit
      @min_interval = min_interval
      @auto_full_refresh = auto_full_refresh
      @partial_count = 0
      @last_refresh_at = nil
    end

    # Records a partial refresh, incrementing the counter and updating the timestamp.
    #
    # @return [void]
    def track_partial!
      @partial_count += 1
      @last_refresh_at = current_time
    end

    # Records a full refresh, resetting the counter and updating the timestamp.
    #
    # @return [void]
    def track_full!
      @partial_count = 0
      @last_refresh_at = current_time
    end

    # Warns via +Kernel#warn+ if less than {#min_interval} seconds have elapsed
    # since the last refresh.
    #
    # No-op on the first refresh (when {#last_refresh_at} is +nil+).
    #
    # @return [void]
    def check_interval!
      return unless last_refresh_at

      elapsed = current_time - last_refresh_at
      return unless elapsed < min_interval

      warn '[ChromaWave] Refresh interval too short ' \
           "(#{elapsed.round(1)}s < #{min_interval}s minimum). " \
           'Frequent refreshes may cause ghosting or damage the display.'
    end

    # Returns whether the partial refresh count has reached the configured limit.
    #
    # @return [Boolean]
    def needs_full?
      partial_count >= partial_limit
    end

    # Returns whether automatic full refresh is enabled.
    #
    # @return [Boolean]
    def auto_full_refresh?
      @auto_full_refresh
    end

    # Resets the partial counter to zero without changing the timestamp.
    #
    # Useful for manually acknowledging the counter without performing a full refresh.
    #
    # @return [void]
    def reset!
      @partial_count = 0
    end

    private

    # Validates constructor parameters.
    #
    # @param partial_limit [Integer] must be >= 1
    # @param min_interval [Numeric] must be >= 0
    # @raise [ArgumentError] if values are out of range
    # @return [void]
    def validate_params!(partial_limit, min_interval)
      raise ArgumentError, "partial_limit must be >= 1, got #{partial_limit}" if partial_limit < 1
      raise ArgumentError, "min_interval must be >= 0, got #{min_interval}" if min_interval.negative?
    end

    # Returns the current monotonic time for interval measurement.
    #
    # Uses the monotonic clock to avoid issues with system clock adjustments.
    #
    # @return [Float] seconds since an arbitrary fixed point
    def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
