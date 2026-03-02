# frozen_string_literal: true

module ChromaWave
  class Layout
    # Abstract base class for all layout tree nodes.
    #
    # Holds common sizing properties (flex, fixed dimensions, constraints,
    # alignment). Positioned rectangles are computed externally by the
    # {Calculator} and stored in a separate position map.
    #
    # Subclasses must override {#intrinsic_width} and {#intrinsic_height}
    # to report their natural (content-driven) sizes.
    class Node
      # Valid horizontal content alignment values.
      ALIGN_VALUES = %i[left center right].freeze

      # Valid vertical content alignment values.
      VALIGN_VALUES = %i[top center bottom].freeze

      # @return [Numeric, nil] flex factor for proportional sizing
      attr_reader :flex

      # @return [Integer, nil] explicit fixed width
      attr_reader :fixed_width

      # @return [Integer, nil] explicit fixed height
      attr_reader :fixed_height

      # @return [Constraints] min/max sizing constraints
      attr_reader :constraints

      # @return [Symbol, nil] horizontal content alignment (:left, :center, :right)
      attr_reader :align

      # @return [Symbol, nil] vertical content alignment (:top, :center, :bottom)
      attr_reader :valign

      # @param flex [Numeric, nil] flex factor
      # @param width [Integer, nil] fixed width
      # @param height [Integer, nil] fixed height
      # @param min_width [Integer] minimum width constraint
      # @param min_height [Integer] minimum height constraint
      # @param max_width [Integer, nil] maximum width constraint
      # @param max_height [Integer, nil] maximum height constraint
      # @param align [Symbol, nil] horizontal content alignment
      # @param valign [Symbol, nil] vertical content alignment
      def initialize(flex: nil, width: nil, height: nil,
                     min_width: 0, min_height: 0, max_width: nil, max_height: nil,
                     align: nil, valign: nil)
        validate_flex!(flex)
        validate_align!(align)
        validate_valign!(valign)
        @flex = flex
        @fixed_width = width
        @fixed_height = height
        @constraints = Constraints.new(
          min_width: min_width, min_height: min_height,
          max_width: max_width, max_height: max_height
        )
        @align = align
        @valign = valign
      end

      # The node's natural width based on content.
      #
      # @return [Integer]
      def intrinsic_width
        0
      end

      # The node's natural height based on content.
      #
      # @return [Integer]
      def intrinsic_height
        0
      end

      # Whether this node contains children.
      #
      # @return [Boolean]
      def container?
        false
      end

      # Whether this node participates in flex distribution.
      #
      # @return [Boolean]
      def flex?
        !flex.nil? && flex.positive?
      end

      # Whether this node has an explicit fixed width.
      #
      # @return [Boolean]
      def fixed_width?
        !fixed_width.nil?
      end

      # Whether this node has an explicit fixed height.
      #
      # @return [Boolean]
      def fixed_height?
        !fixed_height.nil?
      end

      # Human-readable description.
      #
      # @return [String]
      def inspect
        dims = [fixed_width || '?', fixed_height || '?'].join('x')
        parts = [self.class.name, dims]
        parts << "flex=#{flex}" if flex
        "#<#{parts.join(' ')}>"
      end

      private

      # @raise [ArgumentError] if flex is not positive
      def validate_flex!(flex)
        return if flex.nil? || flex.positive?

        raise ArgumentError, "flex must be positive, got #{flex}"
      end

      # @raise [ArgumentError] if align is not a recognized value
      # @param align [Symbol, nil] the value to validate
      # @param label [String] the parameter name for error messages
      def validate_align!(align, label: 'align')
        return if align.nil? || ALIGN_VALUES.include?(align)

        raise ArgumentError, "#{label} must be one of #{ALIGN_VALUES.inspect}, got #{align.inspect}"
      end

      # @raise [ArgumentError] if valign is not a recognized value
      # @param valign [Symbol, nil] the value to validate
      # @param label [String] the parameter name for error messages
      def validate_valign!(valign, label: 'valign')
        return if valign.nil? || VALIGN_VALUES.include?(valign)

        raise ArgumentError, "#{label} must be one of #{VALIGN_VALUES.inspect}, got #{valign.inspect}"
      end
    end
  end
end
