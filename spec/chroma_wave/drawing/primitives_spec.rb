# frozen_string_literal: true

RSpec.describe ChromaWave::Drawing::Primitives do
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red)   { ChromaWave::Color::RED }
  let(:blue)  { ChromaWave::Color::BLUE }
  let(:green) { ChromaWave::Color::GREEN }

  # Small Canvas for pixel-level verification
  let(:canvas) { ChromaWave::Canvas.new(width: 20, height: 20, background: white) }

  describe '#draw_line' do
    it 'draws a horizontal line' do
      canvas.draw_line(2, 5, 8, 5, stroke: black)
      (2..8).each { |x| expect(canvas.get_pixel(x, 5)).to eq(black) }
    end

    it 'draws a vertical line' do
      canvas.draw_line(5, 2, 5, 8, stroke: black)
      (2..8).each { |y| expect(canvas.get_pixel(5, y)).to eq(black) }
    end

    it 'draws a diagonal line covering start and end' do
      canvas.draw_line(0, 0, 5, 5, stroke: black)
      expect(canvas.get_pixel(0, 0)).to eq(black)
      expect(canvas.get_pixel(5, 5)).to eq(black)
    end

    it 'draws a single point when start equals end' do
      canvas.draw_line(5, 5, 5, 5, stroke: red)
      expect(canvas.get_pixel(5, 5)).to eq(red)
    end

    it 'supports thick lines' do
      canvas.draw_line(5, 10, 15, 10, stroke: black, stroke_width: 3)
      expect(canvas.get_pixel(10, 10)).to eq(black)
      expect(canvas.get_pixel(10, 9)).to eq(black)
      expect(canvas.get_pixel(10, 11)).to eq(black)
    end

    it 'raises ArgumentError when stroke is nil' do
      expect { canvas.draw_line(0, 0, 5, 5, stroke: nil) }
        .to raise_error(ArgumentError, /at least one of stroke: or fill:/)
    end

    it 'clips pixels outside canvas bounds' do
      expect { canvas.draw_line(-5, 10, 25, 10, stroke: black) }.not_to raise_error
    end

    it 'returns self for chaining' do
      expect(canvas.draw_line(0, 0, 5, 5, stroke: black)).to equal(canvas)
    end
  end

  describe '#draw_polyline' do
    it 'draws connected segments' do
      points = [[0, 0], [5, 0], [5, 5]]
      canvas.draw_polyline(points, stroke: black)
      expect(canvas.get_pixel(3, 0)).to eq(black)
      expect(canvas.get_pixel(5, 3)).to eq(black)
    end

    it 'connects last to first when closed' do
      points = [[0, 0], [5, 0], [5, 5]]
      canvas.draw_polyline(points, stroke: black, closed: true)
      # The closing segment from (5,5) to (0,0) passes through pixels along the diagonal
      expect(canvas.get_pixel(0, 0)).to eq(black)
      expect(canvas.get_pixel(5, 5)).to eq(black)
    end

    it 'is a no-op for fewer than 2 points' do
      expect(canvas.draw_polyline([[1, 1]], stroke: black)).to equal(canvas)
    end
  end

  describe '#draw_rect' do
    it 'raises ArgumentError when neither stroke nor fill' do
      expect { canvas.draw_rect(0, 0, 10, 8) }
        .to raise_error(ArgumentError, /at least one of stroke: or fill:/)
    end

    context 'with fill only' do
      before { canvas.draw_rect(2, 3, 4, 3, fill: red) }

      it 'fills the interior' do
        expect(canvas.get_pixel(3, 4)).to eq(red)
      end

      it 'fills the corners' do
        expect(canvas.get_pixel(2, 3)).to eq(red)
        expect(canvas.get_pixel(5, 5)).to eq(red)
      end

      it 'does not fill outside' do
        expect(canvas.get_pixel(1, 3)).to eq(white)
        expect(canvas.get_pixel(6, 3)).to eq(white)
      end
    end

    context 'with stroke only' do
      before { canvas.draw_rect(2, 3, 6, 4, stroke: black) }

      it 'draws the top edge' do
        expect(canvas.get_pixel(4, 3)).to eq(black)
      end

      it 'draws the bottom edge' do
        expect(canvas.get_pixel(4, 6)).to eq(black)
      end

      it 'draws the left edge' do
        expect(canvas.get_pixel(2, 5)).to eq(black)
      end

      it 'draws the right edge' do
        expect(canvas.get_pixel(7, 5)).to eq(black)
      end

      it 'leaves the interior empty' do
        expect(canvas.get_pixel(4, 5)).to eq(white)
      end
    end

    context 'with both stroke and fill' do
      it 'draws fill then stroke (stroke on top)' do
        canvas.draw_rect(2, 2, 8, 6, stroke: black, fill: red)
        expect(canvas.get_pixel(2, 2)).to eq(black)  # corner is stroke
        expect(canvas.get_pixel(5, 5)).to eq(red)    # interior is fill
      end
    end

    it 'is a no-op for zero dimensions' do
      canvas.draw_rect(5, 5, 0, 5, fill: red)
      expect(canvas.get_pixel(5, 5)).to eq(white)
    end

    it 'returns self for chaining' do
      expect(canvas.draw_rect(0, 0, 5, 5, fill: red)).to equal(canvas)
    end
  end

  describe '#draw_rounded_rect' do
    it 'raises ArgumentError when neither stroke nor fill' do
      expect { canvas.draw_rounded_rect(0, 0, 10, 8, radius: 2) }
        .to raise_error(ArgumentError)
    end

    it 'fills a rounded rectangle' do
      canvas.draw_rounded_rect(2, 2, 12, 10, radius: 3, fill: red)
      expect(canvas.get_pixel(8, 7)).to eq(red) # center
    end

    it 'clamps radius to half the smaller dimension' do
      # 6x4 rect, radius 10 → clamped to 2
      expect { canvas.draw_rounded_rect(2, 2, 6, 4, radius: 10, fill: red) }.not_to raise_error
    end

    it 'returns self for chaining' do
      expect(canvas.draw_rounded_rect(0, 0, 10, 10, radius: 2, fill: red)).to equal(canvas)
    end
  end

  describe '#draw_circle' do
    it 'raises ArgumentError when neither stroke nor fill' do
      expect { canvas.draw_circle(10, 10, 5) }
        .to raise_error(ArgumentError)
    end

    it 'draws a single pixel for radius 0' do
      canvas.draw_circle(10, 10, 0, fill: red)
      expect(canvas.get_pixel(10, 10)).to eq(red)
    end

    context 'with fill only' do
      before { canvas.draw_circle(10, 10, 4, fill: red) }

      it 'fills the center' do
        expect(canvas.get_pixel(10, 10)).to eq(red)
      end

      it 'fills a point on the edge' do
        expect(canvas.get_pixel(10, 6)).to eq(red)
      end

      it 'does not fill outside' do
        expect(canvas.get_pixel(10, 5)).to eq(white)
      end
    end

    context 'with stroke only' do
      before { canvas.draw_circle(10, 10, 4, stroke: black) }

      it 'draws pixels on the circumference' do
        expect(canvas.get_pixel(14, 10)).to eq(black)
        expect(canvas.get_pixel(10, 14)).to eq(black)
      end

      it 'leaves the center unfilled' do
        expect(canvas.get_pixel(10, 10)).to eq(white)
      end
    end

    it 'supports thick stroke' do
      canvas.draw_circle(10, 10, 5, stroke: black, stroke_width: 3)
      # Should have colored pixels near the circumference
      expect(canvas.get_pixel(15, 10)).to eq(black)
    end

    it 'returns self for chaining' do
      expect(canvas.draw_circle(10, 10, 3, fill: red)).to equal(canvas)
    end

    it 'is a no-op for negative radius' do
      canvas.draw_circle(10, 10, -1, fill: red)
      expect(canvas.get_pixel(10, 10)).to eq(white)
    end
  end

  describe '#draw_ellipse' do
    it 'raises ArgumentError when neither stroke nor fill' do
      expect { canvas.draw_ellipse(10, 10, 5, 3) }
        .to raise_error(ArgumentError)
    end

    context 'with fill only' do
      before { canvas.draw_ellipse(10, 10, 5, 3, fill: red) }

      it 'fills the center' do
        expect(canvas.get_pixel(10, 10)).to eq(red)
      end

      it 'fills a point on the horizontal axis' do
        expect(canvas.get_pixel(15, 10)).to eq(red)
      end

      it 'fills a point on the vertical axis' do
        expect(canvas.get_pixel(10, 13)).to eq(red)
      end
    end

    context 'with stroke only' do
      before { canvas.draw_ellipse(10, 10, 5, 3, stroke: black) }

      it 'draws pixels on the outline' do
        expect(canvas.get_pixel(15, 10)).to eq(black)
        expect(canvas.get_pixel(10, 13)).to eq(black)
      end

      it 'leaves center unfilled' do
        expect(canvas.get_pixel(10, 10)).to eq(white)
      end
    end

    it 'draws a single pixel for zero radii' do
      canvas.draw_ellipse(10, 10, 0, 0, fill: red)
      expect(canvas.get_pixel(10, 10)).to eq(red)
    end

    it 'returns self for chaining' do
      expect(canvas.draw_ellipse(10, 10, 3, 2, fill: red)).to equal(canvas)
    end
  end

  describe '#draw_arc' do
    it 'draws pixels along the arc' do
      # Quarter circle, top-right quadrant (0 to π/2)
      canvas.draw_arc(10, 10, 5, 0, Math::PI / 2, stroke: black)
      expect(canvas.get_pixel(15, 10)).to eq(black) # 0 radians
    end

    it 'raises when stroke is nil' do
      expect { canvas.draw_arc(10, 10, 5, 0, Math::PI, stroke: nil) }
        .to raise_error(ArgumentError)
    end

    it 'is a no-op for zero radius' do
      canvas.draw_arc(10, 10, 0, 0, Math::PI, stroke: black)
      expect(canvas.get_pixel(10, 10)).to eq(white)
    end

    it 'handles wrap-around (start > end after normalization)' do
      expect { canvas.draw_arc(10, 10, 5, -0.5, 0.5, stroke: black) }.not_to raise_error
    end

    it 'returns self for chaining' do
      expect(canvas.draw_arc(10, 10, 5, 0, Math::PI, stroke: black)).to equal(canvas)
    end
  end

  describe '#draw_polygon' do
    it 'raises ArgumentError when neither stroke nor fill' do
      expect { canvas.draw_polygon([[0, 0], [5, 0], [5, 5]]) }
        .to raise_error(ArgumentError)
    end

    context 'with fill only' do
      let(:triangle) { [[5, 2], [15, 2], [10, 12]] }

      before { canvas.draw_polygon(triangle, fill: red) }

      it 'fills interior pixels' do
        expect(canvas.get_pixel(10, 5)).to eq(red)
      end

      it 'fills the top edge' do
        expect(canvas.get_pixel(10, 2)).to eq(red)
      end
    end

    context 'with stroke only' do
      let(:triangle) { [[2, 2], [10, 2], [6, 10]] }

      before { canvas.draw_polygon(triangle, stroke: black) }

      it 'draws the edges' do
        expect(canvas.get_pixel(6, 2)).to eq(black) # top edge
        expect(canvas.get_pixel(2, 2)).to eq(black) # first vertex
      end
    end

    it 'is a no-op for fewer than 3 points' do
      expect(canvas.draw_polygon([[0, 0], [1, 1]], fill: red)).to equal(canvas)
    end

    it 'returns self for chaining' do
      expect(canvas.draw_polygon([[0, 0], [5, 0], [5, 5]], fill: red)).to equal(canvas)
    end
  end

  describe '#flood_fill' do
    it 'fills a contiguous white region' do
      # Draw a red box boundary
      canvas.draw_rect(5, 5, 10, 10, stroke: red)
      # Flood fill the interior
      canvas.flood_fill(10, 10, color: blue)
      expect(canvas.get_pixel(10, 10)).to eq(blue)
      expect(canvas.get_pixel(6, 6)).to eq(blue)
    end

    it 'stops at boundary color' do
      canvas.draw_rect(5, 5, 10, 10, stroke: red)
      canvas.flood_fill(10, 10, color: blue)
      # Red boundary should remain
      expect(canvas.get_pixel(5, 5)).to eq(red)
      # Outside should remain white
      expect(canvas.get_pixel(0, 0)).to eq(white)
    end

    it 'is a no-op when target == fill color' do
      canvas.flood_fill(0, 0, color: white)
      expect(canvas.get_pixel(0, 0)).to eq(white)
    end

    it 'is a no-op for out-of-bounds seed' do
      expect(canvas.flood_fill(-1, -1, color: red)).to equal(canvas)
    end

    it 'handles filling an entire canvas' do
      canvas.flood_fill(0, 0, color: red)
      expect(canvas.get_pixel(0, 0)).to eq(red)
      expect(canvas.get_pixel(19, 19)).to eq(red)
    end

    it 'returns self for chaining' do
      expect(canvas.flood_fill(0, 0, color: red)).to equal(canvas)
    end
  end

  describe 'works on Framebuffer' do
    let(:fb) { ChromaWave::Framebuffer.new(20, 20, :mono) }

    it 'draws a line with palette symbols' do
      fb.clear(:white)
      fb.draw_line(0, 0, 10, 0, stroke: :black)
      expect(fb.get_pixel(5, 0)).to eq(:black)
    end

    it 'draws a filled rectangle with palette symbols' do
      fb.clear(:white)
      fb.draw_rect(2, 2, 5, 5, fill: :black)
      expect(fb.get_pixel(4, 4)).to eq(:black)
    end

    it 'draws a circle with palette symbols' do
      fb.clear(:white)
      fb.draw_circle(10, 10, 3, fill: :black)
      expect(fb.get_pixel(10, 10)).to eq(:black)
    end
  end

  describe 'works on Layer' do
    let(:layer) { ChromaWave::Layer.new(parent: canvas, x: 5, y: 5, width: 10, height: 10) }

    it 'draws within the layer region' do
      layer.draw_rect(0, 0, 5, 5, fill: red)
      expect(canvas.get_pixel(5, 5)).to eq(red)
      expect(canvas.get_pixel(9, 9)).to eq(red)
    end

    it 'clips at layer bounds' do
      layer.draw_rect(8, 8, 5, 5, fill: red)
      expect(canvas.get_pixel(4, 4)).to eq(white) # outside layer
    end
  end

  describe 'chaining multiple primitives' do
    it 'allows method chaining' do
      result = canvas
               .draw_rect(0, 0, 10, 10, fill: red)
               .draw_circle(5, 5, 3, stroke: black)
               .draw_line(0, 0, 19, 19, stroke: blue)

      expect(result).to equal(canvas)
    end
  end
end
