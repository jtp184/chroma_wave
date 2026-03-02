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
        super
      end

      # Clamps a width value to the min/max constraints.
      #
      # @param width [Integer] the width to clamp
      # @return [Integer] the clamped width
      def clamp_width(width)
        effective_max = max_width || [width, min_width].max
        width.clamp(min_width, effective_max)
      end

      # Clamps a height value to the min/max constraints.
      #
      # @param height [Integer] the height to clamp
      # @return [Integer] the clamped height
      def clamp_height(height)
        effective_max = max_height || [height, min_height].max
        height.clamp(min_height, effective_max)
      end

      # Returns true if no constraints are set (all defaults).
      #
      # @return [Boolean]
      def unconstrained?
        min_width.zero? && min_height.zero? && max_width.nil? && max_height.nil?
      end

      # Default unconstrained instance.
      const_set(:NONE, new.freeze)
    end
  end
end
