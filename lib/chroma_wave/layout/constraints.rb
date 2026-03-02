# frozen_string_literal: true

module ChromaWave
  class Layout
    # Immutable value object for min/max sizing constraints.
    #
    # Used by the {Calculator} to clamp child sizes during flex distribution.
    # Unconstrained dimensions use +nil+ for max values.
    #
    # @example
    #   c = Constraints.new(min_width: 50, max_width: 200)
    #   c.clamp_width(30)   # => 50
    #   c.clamp_width(100)  # => 100
    #   c.clamp_width(300)  # => 200
    Constraints = Data.define(:min_width, :min_height, :max_width, :max_height) do
      # @!attribute [r] min_width
      #   @return [Integer] minimum width in pixels
      # @!attribute [r] min_height
      #   @return [Integer] minimum height in pixels
      # @!attribute [r] max_width
      #   @return [Integer, nil] maximum width in pixels, or nil for unconstrained
      # @!attribute [r] max_height
      #   @return [Integer, nil] maximum height in pixels, or nil for unconstrained

      def initialize(min_width: 0, min_height: 0, max_width: nil, max_height: nil)
        validate_bounds!(min_width, max_width, :width)
        validate_bounds!(min_height, max_height, :height)
        super
      end

      # Clamps a width value to the min/max constraints.
      #
      # @param width [Integer] the width to clamp
      # @return [Integer] the clamped width
      def clamp_width(width) = clamp_dimension(width, min_width, max_width)

      # Clamps a height value to the min/max constraints.
      #
      # @param height [Integer] the height to clamp
      # @return [Integer] the clamped height
      def clamp_height(height) = clamp_dimension(height, min_height, max_height)

      # Returns true if no constraints are set (all defaults).
      #
      # @return [Boolean]
      def unconstrained?
        min_width.zero? && min_height.zero? && max_width.nil? && max_height.nil?
      end

      private

      # Clamps a value to the given min/max range.
      #
      # When max is nil (unconstrained), uses the larger of value and min
      # as the effective upper bound so +clamp+ has a valid range.
      #
      # @param value [Integer] the value to clamp
      # @param min [Integer] minimum bound
      # @param max [Integer, nil] maximum bound, or nil for unconstrained
      # @return [Integer] the clamped value
      def clamp_dimension(value, min, max)
        effective_max = max || [value, min].max
        value.clamp(min, effective_max)
      end

      # @raise [ArgumentError] if max is less than min for the given axis
      def validate_bounds!(min, max, axis)
        return if max.nil? || max >= min

        raise ArgumentError, "max_#{axis} (#{max}) must be >= min_#{axis} (#{min})"
      end

      # Default unconstrained instance.
      const_set(:NONE, new.freeze)
    end
  end
end
