# frozen_string_literal: true

module ChromaWave
  class Layout
    # A container node that lays out children along a main axis.
    #
    # Containers can be either +:horizontal+ (row) or +:vertical+ (column).
    # They support padding, gap between children, background color,
    # and border with configurable width.
    #
    # @example Horizontal row with gap
    #   ContainerNode.new(direction: :horizontal, gap: 10, children: [...])
    class ContainerNode < Node
      # @return [:horizontal, :vertical] the main axis direction
      attr_reader :direction

      # @return [Array<Node>] child nodes
      attr_reader :children

      # @return [Padding] edge insets
      attr_reader :padding

      # @return [Integer] gap between children in pixels
      attr_reader :gap

      # @return [Color, nil] background fill color
      attr_reader :background

      # @return [Color, nil] border color
      attr_reader :border

      # @return [Integer] border width in pixels
      attr_reader :border_width

      # @return [Symbol, nil] horizontal alignment for children (:left, :center, :right)
      attr_reader :child_align

      # @return [Symbol, nil] vertical alignment for children (:top, :center, :bottom)
      attr_reader :child_valign

      # Valid main-axis direction values.
      DIRECTIONS = %i[horizontal vertical].freeze

      # @param direction [:horizontal, :vertical] main axis
      # @param children [Array<Node>] child nodes
      # @param padding [nil, Integer, Array, Padding] edge insets
      # @param gap [Integer] spacing between children
      # @param background [Color, nil] fill color
      # @param border [Color, nil] border color
      # @param border_width [Integer] border thickness
      # @param child_align [Symbol, nil] cross-axis horizontal alignment for children
      # @param child_valign [Symbol, nil] cross-axis vertical alignment for children
      # @param kwargs [Hash] forwarded to {Node#initialize}
      def initialize(direction:, children: [], padding: nil, gap: 0,
                     background: nil, border: nil, border_width: 0,
                     child_align: nil, child_valign: nil, **)
        super(**)
        validate_direction!(direction)
        validate_gap!(gap)
        validate_border_width!(border_width)
        validate_border_consistency!(border, border_width)
        @direction = direction
        @children = children
        @padding = Padding.parse(padding)
        @gap = gap
        @background = background
        @border = border
        @border_width = border_width
        @child_align = child_align
        @child_valign = child_valign
      end

      # Whether the main axis is horizontal.
      #
      # @return [Boolean]
      def horizontal?
        direction == :horizontal
      end

      # Whether the main axis is vertical.
      #
      # @return [Boolean]
      def vertical?
        direction == :vertical
      end

      # @return [true]
      def container?
        true
      end

      # Human-readable description.
      #
      # @return [String]
      def inspect
        "#<#{self.class} #{direction} children=#{children.length}>"
      end

      # The total border inset on each side.
      #
      # @return [Integer]
      def border_inset
        border ? border_width : 0
      end

      # Natural width based on children's intrinsic sizes.
      #
      # For horizontal containers: sum of children widths + gaps.
      # For vertical containers: max of children widths.
      # Always adds padding and border inset.
      #
      # @return [Integer]
      def intrinsic_width
        inset = padding.horizontal + (2 * border_inset)
        content = if horizontal?
                    children_main_axis_sum(:intrinsic_width)
                  else
                    children_cross_axis_max(:intrinsic_width)
                  end
        inset + content
      end

      # Natural height based on children's intrinsic sizes.
      #
      # For vertical containers: sum of children heights + gaps.
      # For horizontal containers: max of children heights.
      # Always adds padding and border inset.
      #
      # @return [Integer]
      def intrinsic_height
        inset = padding.vertical + (2 * border_inset)
        content = if vertical?
                    children_main_axis_sum(:intrinsic_height)
                  else
                    children_cross_axis_max(:intrinsic_height)
                  end
        inset + content
      end

      private

      # Sum of children sizes along the main axis, including gaps.
      #
      # @param method [Symbol] :intrinsic_width or :intrinsic_height
      # @return [Integer]
      def children_main_axis_sum(method)
        return 0 if children.empty?

        total_gaps = [children.length - 1, 0].max * gap
        children.sum(&method) + total_gaps
      end

      # Maximum of children sizes along the cross axis.
      #
      # @param method [Symbol] :intrinsic_width or :intrinsic_height
      # @return [Integer]
      def children_cross_axis_max(method)
        children.map(&method).max || 0
      end

      # @raise [ArgumentError] if direction is not :horizontal or :vertical
      def validate_direction!(direction)
        return if DIRECTIONS.include?(direction)

        raise ArgumentError, "direction must be :horizontal or :vertical, got #{direction.inspect}"
      end

      # @raise [ArgumentError] if gap is negative
      def validate_gap!(gap)
        return unless gap.negative?

        raise ArgumentError, "gap must be non-negative, got #{gap}"
      end

      # @raise [ArgumentError] if border_width is negative
      def validate_border_width!(border_width)
        return unless border_width.negative?

        raise ArgumentError, "border_width must be non-negative, got #{border_width}"
      end

      # @raise [ArgumentError] if border_width is set without a border color
      def validate_border_consistency!(border, border_width)
        return unless border.nil? && border_width.positive?

        raise ArgumentError, "border_width is #{border_width} but no border color was provided"
      end
    end
  end
end
