# frozen_string_literal: true

RSpec.describe ChromaWave::Drawing::Text do
  let(:font) { ChromaWave::Font.default(size: 14) }
  let(:canvas) { ChromaWave::Canvas.new(width: 200, height: 100) }
  let(:black) { ChromaWave::Color::BLACK }
  let(:white) { ChromaWave::Color::WHITE }

  describe 'module inclusion' do
    it 'is included in Canvas' do
      expect(ChromaWave::Canvas.new(width: 10, height: 10)).to respond_to(:draw_text)
    end

    it 'is included in Layer' do
      layer = ChromaWave::Canvas.new(width: 20, height: 20).layer(x: 0, y: 0, width: 10, height: 10)
      expect(layer).to respond_to(:draw_text)
    end

    it 'is NOT included in Framebuffer' do
      fb = ChromaWave::Framebuffer.new(16, 8, :mono)
      expect(fb).not_to respond_to(:draw_text)
    end
  end

  describe '#draw_text' do
    it 'renders text pixels onto the canvas' do
      canvas.draw_text('Hello', x: 5, y: 5, font: font, color: black)
      expect(count_non_white(canvas)).to be_positive
    end

    it 'returns self for chaining' do
      result = canvas.draw_text('Hi', x: 0, y: 0, font: font, color: black)
      expect(result).to be(canvas)
    end

    it 'renders anti-aliased pixels (not just black and white)' do
      canvas.draw_text('Hello', x: 5, y: 5, font: font, color: black)
      expect(has_grey_pixel?(canvas)).to be(true)
    end

    context 'with word wrapping' do
      it 'wraps text across multiple lines' do
        canvas.draw_text('The quick brown fox jumps over the lazy dog',
                         x: 0, y: 0, font: font, color: black, max_width: 100)
        expect(has_lower_pixel?(canvas, font.line_height + 5)).to be(true)
      end
    end

    context 'with explicit newlines' do
      it 'renders text on separate lines without max_width' do
        canvas.draw_text("Top\nBottom", x: 0, y: 0, font: font, color: black)
        expect(has_lower_pixel?(canvas, font.line_height + 5)).to be(true)
      end

      it 'respects newlines within word-wrapped text' do
        canvas.draw_text("A\nB", x: 0, y: 0, font: font, color: black, max_width: 200)
        expect(has_lower_pixel?(canvas, font.line_height + 5)).to be(true)
      end
    end

    context 'with center alignment' do
      it 'centers text within max_width' do
        left_x = draw_and_find_first_x(:left)
        center_x = draw_and_find_first_x(:center)
        expect(center_x).to be > left_x
      end

      it 'raises ArgumentError without max_width' do
        expect { canvas.draw_text('Hi', x: 0, y: 0, font: font, color: black, align: :center) }
          .to raise_error(ArgumentError, /max_width is required/)
      end
    end

    context 'with right alignment' do
      it 'right-aligns text within max_width' do
        left_x = draw_and_find_first_x(:left)
        right_x = draw_and_find_first_x(:right)
        expect(right_x).to be > left_x
      end

      it 'raises ArgumentError without max_width' do
        expect { canvas.draw_text('Hi', x: 0, y: 0, font: font, color: black, align: :right) }
          .to raise_error(ArgumentError, /max_width is required/)
      end
    end
  end

  private

  def draw_and_find_first_x(align)
    cvs = ChromaWave::Canvas.new(width: 200, height: 30)
    cvs.draw_text('Hi',
                  x: 0, y: 0, font: font, color: black,
                  align: align, max_width: 200)
    first_non_white_x(cvs)
  end
end
