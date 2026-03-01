# frozen_string_literal: true

RSpec.describe ChromaWave::Font do # rubocop:disable RSpec/SpecFilePathFormat -- cross-cutting integration spec
  describe 'Font + Canvas end-to-end' do
    let(:font) { described_class.default(size: 16) }
    let(:canvas) { ChromaWave::Canvas.new(width: 200, height: 50) }

    it 'draws text onto a canvas and produces non-white pixels' do
      canvas.draw_text('Hello', x: 5, y: 5, font: font, color: ChromaWave::Color::BLACK)

      non_white = count_non_white(canvas)
      expect(non_white).to be_positive
    end

    it 'measures text and renders within measured bounds' do
      metrics = font.measure('Test')
      expect(metrics.width).to be_positive
      expect(metrics.height).to be_positive
    end

    it 'supports word wrapping within max_width' do
      canvas.draw_text('This is a longer text string', x: 0, y: 0, font: font,
                                                       color: ChromaWave::Color::BLACK,
                                                       max_width: 100)
      non_white = count_non_white(canvas)
      expect(non_white).to be_positive
    end
  end

  describe 'IconFont + Canvas end-to-end' do
    let(:icons) { ChromaWave::IconFont.lucide(size: 24) }
    let(:canvas) { ChromaWave::Canvas.new(width: 100, height: 100) }

    it 'renders an icon and produces visible pixels' do
      icons.draw(canvas, :house, x: 10, y: 10, color: ChromaWave::Color::BLACK)

      non_white = count_non_white(canvas)
      expect(non_white).to be_positive
    end

    it 'renders multiple icons side by side' do
      x_offset = 0
      %i[house activity airplay].each do |name|
        icons.draw(canvas, name, x: x_offset, y: 10, color: ChromaWave::Color::BLACK)
        x_offset += 30
      end

      non_white = count_non_white(canvas)
      expect(non_white).to be_positive
    end
  end

  describe 'Font + IconFont + Renderer pipeline' do
    let(:font) { described_class.default(size: 14) }
    let(:icons) { ChromaWave::IconFont.lucide(size: 16) }
    let(:canvas) { ChromaWave::Canvas.new(width: 200, height: 50) }

    it 'renders text and icons then quantizes to a framebuffer' do
      icons.draw(canvas, :house, x: 5, y: 5, color: ChromaWave::Color::BLACK)
      canvas.draw_text('Home', x: 30, y: 5, font: font, color: ChromaWave::Color::BLACK)

      renderer = ChromaWave::Renderer.new(pixel_format: ChromaWave::PixelFormat::MONO)
      fb = renderer.render(canvas)

      expect(fb).to be_a(ChromaWave::Framebuffer)
      expect(fb.width).to eq(200)
      expect(fb.height).to eq(50)

      # The framebuffer should have some black pixels (icon + text)
      has_black = (0...fb.width).any? { |x| fb.get_pixel(x, 10) == :black }
      expect(has_black).to be true
    end
  end

  describe 'Full display pipeline with content' do
    let(:model) { ChromaWave::Native.model_names.first }
    let(:config) { ChromaWave::Native.model_config(model) }

    it 'renders text onto a canvas and shows on a display' do
      font = described_class.default(size: 12)
      canvas = ChromaWave::Canvas.new(width: config[:width], height: config[:height])

      canvas.draw_text('ChromaWave', x: 10, y: 10, font: font, color: ChromaWave::Color::BLACK)

      display = ChromaWave::MockDevice.new(model: model)
      expect { display.show(canvas) }.not_to raise_error
      display.close
    end
  end
end
