# frozen_string_literal: true

module ChromaWave
  class Layout
    # Immutable value object for edge insets (top, right, bottom, left).
    #
    # Follows CSS shorthand conventions for parsing:
    # - +nil+ or +0+ -> all zeros
    # - +Integer+ -> uniform on all sides
    # - +Array[3]+ -> [top, horizontal, bottom]
    # - +Array[4]+ -> [top, right, bottom, left]
    # - +Padding+ -> passthrough
    #
    # @example Uniform padding
    #   Padding.parse(10) # => Padding(top: 10, right: 10, bottom: 10, left: 10)
    #
    # @example Explicit edges
    #   Padding.parse([5, 10, 15, 20]) # => Padding(top: 5, right: 10, bottom: 15, left: 20)
    Padding = Data.define(:top, :right, :bottom, :left) do
      # @!attribute [r] top
      #   @return [Integer] top edge inset in pixels
      # @!attribute [r] right
      #   @return [Integer] right edge inset in pixels
      # @!attribute [r] bottom
      #   @return [Integer] bottom edge inset in pixels
      # @!attribute [r] left
      #   @return [Integer] left edge inset in pixels

      # Zero padding singleton.
      const_set(:ZERO, new(top: 0, right: 0, bottom: 0, left: 0).freeze)

      # @raise [ArgumentError] if any edge value is negative
      def initialize(top:, right:, bottom:, left:)
        [top, right, bottom, left].each do |v|
          raise ArgumentError, "padding values must be non-negative, got #{v}" if v.negative?
        end
        super
      end

      # Parses various input formats into a Padding instance.
      #
      # @param value [nil, Integer, Array<Integer>, Padding] the input to parse
      # @return [Padding]
      # @raise [ArgumentError] if the input format is not recognized
      def self.parse(value)
        case value
        when nil      then self::ZERO
        when Padding  then value
        when Integer  then value.zero? ? self::ZERO : new(top: value, right: value, bottom: value, left: value)
        when Array    then parse_array(value)
        else raise ArgumentError, "cannot parse #{value.inspect} as Padding"
        end
      end

      # Total horizontal inset (left + right).
      #
      # @return [Integer]
      def horizontal
        left + right
      end

      # Total vertical inset (top + bottom).
      #
      # @return [Integer]
      def vertical
        top + bottom
      end

      # Parses an array into Padding, supporting CSS-style shorthand.
      #
      # @param ary [Array<Integer>] 1, 2, 3, or 4 element array
      # @return [Padding]
      # @raise [ArgumentError] if array length is not 1, 2, 3, or 4
      private_class_method def self.parse_array(ary)
        case ary.length
        when 1 then parse(ary[0])
        when 2 then new(top: ary[0], right: ary[1], bottom: ary[0], left: ary[1])
        when 3 then new(top: ary[0], right: ary[1], bottom: ary[2], left: ary[1])
        when 4 then new(top: ary[0], right: ary[1], bottom: ary[2], left: ary[3])
        else raise ArgumentError, "expected 1, 2, 3, or 4 element Array, got #{ary.length}"
        end
      end
    end
  end
end
