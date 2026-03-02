# frozen_string_literal: true

module ChromaWave
  class Layout
    # Renders a positioned layout tree onto a Canvas.
    #
    # Walks the node tree and draws each node using a Layer at its absolute
    # position. Draws backgrounds, borders, and content in the correct order.
    class Renderer
      include Alignment

      # @return [Canvas] the target canvas
      attr_reader :canvas

      # Creates a renderer targeting the given canvas.
      #
      # @param canvas [Canvas] the canvas to render onto
      # @param positions [Hash{Node => Box}] position map from Calculator
      def initialize(canvas, positions)
        @canvas = canvas
        @positions = positions
      end

      # Renders the full layout tree onto the canvas.
      #
      # @param root [Node] the root of the positioned layout tree
      # @return [Canvas]
      def render(root)
        render_node(root)
        canvas
      end

      private

      # Recursively renders a node and its children.
      #
      # @param node [Node] the node to render
      def render_node(node)
        box = @positions[node]
        return if box.nil? || box.width <= 0 || box.height <= 0

        layer = canvas.layer(x: box.x, y: box.y, width: box.width, height: box.height)

        if node.container?
          render_container(node, layer)
        else
          render_content(node, layer)
        end
      end

      # Renders a container node: background, border, then children.
      #
      # @param node [ContainerNode] the container
      # @param layer [Layer] the drawing surface
      def render_container(node, layer)
        draw_background(node, layer)
        draw_border(node, layer)

        node.children.each { |child| render_node(child) }
      end

      # Draws the background fill for a container.
      #
      # @param node [ContainerNode] the container
      # @param layer [Layer] the drawing surface
      def draw_background(node, layer)
        return unless node.background

        layer.clear(node.background)
      end

      # Draws border strips (fill_rect, not stroke) for a container.
      #
      # Uses four filled rectangles for precise inward borders,
      # matching the CSS box model.
      #
      # @param node [ContainerNode] the container
      # @param layer [Layer] the drawing surface
      def draw_border(node, layer)
        return unless node.border

        bw = node.border_width
        return if bw <= 0

        w = layer.width
        h = layer.height
        pen = Pen.fill(node.border)

        # Top
        layer.draw_rect(0, 0, w, bw, pen: pen)
        # Bottom
        layer.draw_rect(0, h - bw, w, bw, pen: pen)
        # Left
        layer.draw_rect(0, bw, bw, h - (2 * bw), pen: pen)
        # Right
        layer.draw_rect(w - bw, bw, bw, h - (2 * bw), pen: pen)
      end

      # Dispatches rendering for a leaf content node.
      #
      # @param node [Node] the content node
      # @param layer [Layer] the drawing surface
      def render_content(node, layer)
        case node
        when TextContent        then render_text(node, layer)
        when IconContent        then render_icon(node, layer)
        when ImageContent       then render_image(node, layer)
        when CanvasBlockContent then render_canvas_block(node, layer)
        when SpacerContent      then nil # spacers draw nothing
        end
      end

      # Renders text content with alignment support.
      #
      # Computes horizontal alignment in the Renderer (like icons/images)
      # rather than delegating to +draw_text+'s +align:+ parameter. This
      # ensures all content types use the same alignment mechanism.
      #
      # @param node [TextContent] the text node
      # @param layer [Layer] the drawing surface
      def render_text(node, layer)
        x_offset = align_offset(node.metrics.width, layer.width, node.align)
        y_offset = valign_offset(node.metrics.height, layer.height, node.valign)

        layer.draw_text(
          node.text,
          x: x_offset, y: y_offset,
          font: node.font,
          color: node.color,
          max_width: layer.width - x_offset
        )
      end

      # Renders an icon with alignment support.
      #
      # @param node [IconContent] the icon node
      # @param layer [Layer] the drawing surface
      def render_icon(node, layer)
        x_offset = align_offset(node.metrics.width, layer.width, node.align)
        y_offset = valign_offset(node.metrics.height, layer.height, node.valign)

        node.font.draw(layer, node.name, x: x_offset, y: y_offset, color: node.color)
      end

      # Renders an image with fit mode support.
      #
      # @param node [ImageContent] the image node
      # @param layer [Layer] the drawing surface
      def render_image(node, layer)
        source = node.source
        return if source.width.zero? || source.height.zero?

        fitted = fit_image(source, layer.width, layer.height, node.fit)
        draw_fitted_image(fitted, node, layer)
      end

      # Draws a fitted image at its aligned position within the layer.
      #
      # Draws directly onto the canvas at absolute coordinates because
      # +Image#draw_onto+ writes raw pixel data and does not understand
      # the Layer abstraction. We translate manually via +layer.offset_x/y+.
      #
      # @param image [Image] the fitted/scaled image
      # @param node [ImageContent] the image node (for alignment)
      # @param layer [Layer] the drawing surface
      def draw_fitted_image(image, node, layer)
        x_offset = align_offset(image.width, layer.width, node.align)
        y_offset = valign_offset(image.height, layer.height, node.valign)

        image.draw_onto(canvas, x: layer.offset_x + x_offset,
                                y: layer.offset_y + y_offset)
      end

      # Executes a canvas block with the layer as the drawing context.
      #
      # @param node [CanvasBlockContent] the canvas block node
      # @param layer [Layer] the drawing surface
      def render_canvas_block(node, layer)
        node.block.call(layer)
      end

      # Fits an image to the given dimensions using the specified mode.
      #
      # @param image [Image] the source image
      # @param box_w [Integer] box width
      # @param box_h [Integer] box height
      # @param fit [Symbol] :contain, :cover, or :stretch
      # @return [Image] the fitted image
      def fit_image(image, box_w, box_h, fit)
        case fit
        when :stretch then image.resize(width: box_w, height: box_h)
        when :cover   then fit_cover(image, box_w, box_h)
        else               fit_contain(image, box_w, box_h)
        end
      end

      # Scales image to fit within box preserving aspect ratio.
      #
      # @param image [Image] source image
      # @param box_w [Integer] box width
      # @param box_h [Integer] box height
      # @return [Image]
      def fit_contain(image, box_w, box_h)
        scale = [box_w.to_f / image.width, box_h.to_f / image.height].min
        image.resize(width: (image.width * scale).round, height: (image.height * scale).round)
      end

      # Scales image to fill box preserving aspect ratio, center-crops excess.
      #
      # @param image [Image] source image
      # @param box_w [Integer] box width
      # @param box_h [Integer] box height
      # @return [Image]
      def fit_cover(image, box_w, box_h)
        scale = [box_w.to_f / image.width, box_h.to_f / image.height].max
        scaled = image.resize(width: (image.width * scale).round, height: (image.height * scale).round)
        crop_x = [(scaled.width - box_w) / 2, 0].max
        crop_y = [(scaled.height - box_h) / 2, 0].max
        scaled.crop(x: crop_x, y: crop_y, width: box_w, height: box_h)
      end

      # Computes vertical alignment offset.
      #
      # Alias for {Alignment#align_offset} with vertical alignment names.
      #
      # @param content_h [Integer] content height
      # @param box_h [Integer] box height
      # @param alignment [Symbol, nil] :center, :bottom, or default (:top)
      # @return [Integer]
      def valign_offset(content_h, box_h, alignment)
        align_offset(content_h, box_h, alignment)
      end
    end
  end
end
