# frozen_string_literal: true

module ChromaWave
  class Layout
    # Two-pass layout algorithm that computes positioned boxes for all nodes.
    #
    # The algorithm walks the node tree top-down, distributing available space
    # to children based on their flex factors, fixed sizes, and intrinsic
    # content sizes. Constraints (min/max) are resolved iteratively.
    #
    # == Box Model
    #
    #   +-- Container box (x, y, width, height) --------+
    #   |  border (border_width pixels)                  |
    #   |  +-- padding area -----------------------+    |
    #   |  |  +-- content area ---------------+    |    |
    #   |  |  |  Child1  [gap]  Child2  ...   |    |    |
    #   |  |  +-------------------------------+    |    |
    #   |  +---------------------------------------+    |
    #   +-----------------------------------------------+
    class Calculator
      # @return [Node] the root node of the layout tree
      attr_reader :root

      # @return [Integer] total available width
      attr_reader :width

      # @return [Integer] total available height
      attr_reader :height

      # Computes layout for the given tree within the specified dimensions.
      #
      # @param root [Node] root of the layout tree
      # @param width [Integer] available width in pixels
      # @param height [Integer] available height in pixels
      def initialize(root:, width:, height:)
        @root = root
        @width = width
        @height = height
      end

      # Runs the layout computation, assigning boxes to all nodes.
      #
      # @return [Node] the root node with computed boxes
      def compute
        layout_node(root, 0, 0, width, height)
        root
      end

      private

      # Recursively lays out a node and its children.
      #
      # @param node [Node] the node to lay out
      # @param x [Integer] absolute x position
      # @param y [Integer] absolute y position
      # @param available_w [Integer] available width
      # @param available_h [Integer] available height
      def layout_node(node, x, y, available_w, available_h)
        node.box.x = x
        node.box.y = y
        node.box.width = [available_w, 0].max
        node.box.height = [available_h, 0].max

        return unless node.container? && !node.children.empty?

        layout_children(node)
      end

      # Distributes space among a container's children.
      #
      # @param node [ContainerNode] the container to lay out
      def layout_children(node)
        content = content_area(node)
        return if content.width <= 0 || content.height <= 0

        if node.horizontal?
          distribute_horizontal(node, content)
        else
          distribute_vertical(node, content)
        end
      end

      # Computes the content area inside border and padding.
      #
      # @param node [ContainerNode] the container
      # @return [Box] positioned rectangle of the content area
      def content_area(node)
        inset = node.border_inset
        box = node.box
        pad = node.padding
        Box.new(
          x: box.x + inset + pad.left,
          y: box.y + inset + pad.top,
          width: box.width - (2 * inset) - pad.horizontal,
          height: box.height - (2 * inset) - pad.vertical
        )
      end

      # Distributes space horizontally (row layout).
      #
      # @param node [ContainerNode] the row container
      # @param content [Box] content area dimensions
      def distribute_horizontal(node, content)
        sizes = allocate_main_axis(node.children, content.width, node.gap, :width)
        cursor_x = content.x

        node.children.each_with_index do |child, i|
          child_w = sizes[i]
          child_h = child_cross_size(child, content.height, :height)
          child_y = cross_offset(content.y, content.height, child_h, node.valign)

          layout_node(child, cursor_x, child_y, child_w, child_h)
          cursor_x += child_w + node.gap
        end
      end

      # Distributes space vertically (column layout).
      #
      # @param node [ContainerNode] the column container
      # @param content [Box] content area dimensions
      def distribute_vertical(node, content)
        sizes = allocate_main_axis(node.children, content.height, node.gap, :height)
        cursor_y = content.y

        node.children.each_with_index do |child, i|
          child_h = sizes[i]
          child_w = child_cross_size(child, content.width, :width)
          child_x = cross_offset(content.x, content.width, child_w, node.align)

          layout_node(child, child_x, cursor_y, child_w, child_h)
          cursor_y += child_h + node.gap
        end
      end

      # Computes child size along the cross axis.
      #
      # @param child [Node] the child node
      # @param available [Integer] available cross-axis space
      # @param axis [Symbol] :width or :height
      # @return [Integer] the child's cross-axis size
      def child_cross_size(child, available, axis)
        fixed = axis == :width ? child.fixed_width : child.fixed_height
        clamp = axis == :width ? :clamp_width : :clamp_height
        size = fixed || available
        child.constraints.send(clamp, [size, 0].max)
      end

      # Computes cross-axis offset for alignment.
      #
      # @param origin [Integer] content area origin
      # @param total [Integer] total cross-axis space
      # @param child_size [Integer] child cross-axis size
      # @param alignment [Symbol, nil] :center, :right/:bottom, or default (start)
      # @return [Integer] aligned position
      def cross_offset(origin, total, child_size, alignment)
        slack = [total - child_size, 0].max
        case alignment
        when :center then origin + (slack / 2)
        when :right, :bottom then origin + slack
        else origin
        end
      end

      # Allocates main-axis sizes to children using flex distribution.
      #
      # @param children [Array<Node>] child nodes
      # @param budget [Integer] total available main-axis space
      # @param gap [Integer] gap between children
      # @param axis [Symbol] :width or :height
      # @return [Array<Integer>] allocated size for each child
      def allocate_main_axis(children, budget, gap, axis)
        total_gaps = [children.length - 1, 0].max * gap
        remaining = [budget - total_gaps, 0].max

        sizes = Array.new(children.length, 0)
        frozen = Array.new(children.length, false)

        # First pass: allocate fixed and intrinsic children
        total_flex = 0.0
        children.each_with_index do |child, i|
          if child.flex?
            total_flex += child.flex
          else
            size = child_fixed_or_intrinsic(child, axis)
            clamped = clamp_axis(child, size, axis)
            sizes[i] = clamped
            frozen[i] = true
            remaining -= clamped
          end
        end

        remaining = [remaining, 0].max

        # Second pass: distribute remaining space to flex children with constraint resolution
        distribute_flex(children, sizes, frozen, remaining, total_flex, axis)

        sizes
      end

      # Gets the fixed or intrinsic size for a non-flex child.
      #
      # @param child [Node] the child node
      # @param axis [Symbol] :width or :height
      # @return [Integer] the child's size
      def child_fixed_or_intrinsic(child, axis)
        if axis == :width
          child.fixed_width || child.intrinsic_width
        else
          child.fixed_height || child.intrinsic_height
        end
      end

      # Clamps a size along the given axis.
      #
      # @param child [Node] the child node
      # @param size [Integer] the size to clamp
      # @param axis [Symbol] :width or :height
      # @return [Integer] clamped size
      def clamp_axis(child, size, axis)
        if axis == :width
          child.constraints.clamp_width(size)
        else
          child.constraints.clamp_height(size)
        end
      end

      # Iteratively distributes flex space with constraint re-distribution.
      #
      # Each round allocates proportional shares to unfrozen flex children.
      # If any child is clamped by constraints, it is frozen at its clamped
      # value and the remaining budget/pool are adjusted for the next round.
      # Repeats until no children are frozen in a round (max N rounds).
      #
      # @param children [Array<Node>] child nodes
      # @param sizes [Array<Integer>] size array (mutated in place)
      # @param frozen [Array<Boolean>] frozen state (mutated in place)
      # @param budget [Integer] remaining distributable space
      # @param flex_pool [Float] total flex of unfrozen children
      # @param axis [Symbol] :width or :height
      def distribute_flex(children, sizes, frozen, budget, flex_pool, axis)
        return if flex_pool.zero?

        children.length.times do
          any_frozen = false

          children.each_with_index do |child, i|
            next if frozen[i] || !child.flex?

            share = (budget * child.flex / flex_pool).round
            clamped = clamp_axis(child, share, axis)

            next unless clamped != share

            sizes[i] = clamped
            frozen[i] = true
            budget -= clamped
            flex_pool -= child.flex
            any_frozen = true
          end

          break unless any_frozen
        end

        # Final allocation for remaining unfrozen flex children
        allocate_unfrozen_flex(children, sizes, frozen, budget, flex_pool)
      end

      # Allocates budget to remaining unfrozen flex children.
      #
      # @param children [Array<Node>] child nodes
      # @param sizes [Array<Integer>] size array (mutated in place)
      # @param frozen [Array<Boolean>] frozen state
      # @param budget [Integer] remaining space
      # @param flex_pool [Float] remaining flex total
      def allocate_unfrozen_flex(children, sizes, frozen, budget, flex_pool)
        return if flex_pool.zero? || budget <= 0

        allocated = 0
        last_unfrozen = nil

        children.each_with_index do |child, i|
          next if frozen[i] || !child.flex?

          share = (budget * child.flex / flex_pool).round
          sizes[i] = share
          allocated += share
          last_unfrozen = i
        end

        # Correct rounding error on the last unfrozen child
        sizes[last_unfrozen] += budget - allocated if last_unfrozen
      end
    end
  end
end
