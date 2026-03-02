# frozen_string_literal: true

module ChromaWave
  class Layout
    # Shared alignment offset calculation for layout components.
    #
    # Computes the pixel offset needed to position content within a
    # container according to a start/center/end alignment scheme.
    # Used by both {Calculator} (cross-axis positioning) and
    # {Renderer} (content alignment within boxes).
    module Alignment
      # Computes the alignment offset for positioning content within a container.
      #
      # @param content_size [Integer] size of the content to align
      # @param container_size [Integer] size of the container
      # @param alignment [Symbol, nil] alignment mode — +:center+, +:right+/+:bottom+ (end),
      #   or +nil+/+:left+/+:top+ (start, default)
      # @return [Integer] pixel offset from the container's origin
      def align_offset(content_size, container_size, alignment)
        slack = [container_size - content_size, 0].max
        case alignment
        when :center         then slack / 2
        when :right, :bottom then slack
        else 0
        end
      end
    end
  end
end
