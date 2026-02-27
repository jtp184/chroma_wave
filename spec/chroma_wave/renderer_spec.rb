# frozen_string_literal: true

RSpec.describe ChromaWave::Renderer do
  let(:mono_format)   { ChromaWave::PixelFormat::MONO }
  let(:gray_format)   { ChromaWave::PixelFormat::GRAY4 }
  let(:tricolor)      { ChromaWave::PixelFormat::COLOR4 }

  let(:black) { ChromaWave::Color::BLACK }
  let(:white) { ChromaWave::Color::WHITE }
  let(:red)   { ChromaWave::Color::RED }

  describe '#initialize' do
    it 'accepts :threshold strategy' do
      renderer = described_class.new(pixel_format: mono_format, dither: :threshold)
      expect(renderer.dither).to eq(:threshold)
    end

    it 'accepts :floyd_steinberg strategy' do
      renderer = described_class.new(pixel_format: mono_format, dither: :floyd_steinberg)
      expect(renderer.dither).to eq(:floyd_steinberg)
    end

    it 'accepts :ordered strategy' do
      renderer = described_class.new(pixel_format: mono_format, dither: :ordered)
      expect(renderer.dither).to eq(:ordered)
    end

    it 'defaults to :floyd_steinberg' do
      renderer = described_class.new(pixel_format: mono_format)
      expect(renderer.dither).to eq(:floyd_steinberg)
    end

    it 'raises ArgumentError for unknown strategy' do
      expect { described_class.new(pixel_format: mono_format, dither: :halftone) }
        .to raise_error(ArgumentError, /unknown dither strategy/)
    end

    it 'accepts a symbol for pixel_format' do
      renderer = described_class.new(pixel_format: :mono)
      expect(renderer.pixel_format).to equal(mono_format)
    end

    it 'stores the pixel_format' do
      renderer = described_class.new(pixel_format: gray_format)
      expect(renderer.pixel_format).to equal(gray_format)
    end

    it 'raises TypeError for invalid pixel_format type' do
      expect { described_class.new(pixel_format: 42) }
        .to raise_error(TypeError)
    end
  end

  describe '#render' do
    let(:renderer) { described_class.new(pixel_format: mono_format, dither: :threshold) }

    it 'returns a Framebuffer with correct dimensions' do
      canvas = ChromaWave::Canvas.new(width: 10, height: 5, background: white)
      framebuffer = renderer.render(canvas)
      expect(framebuffer.width).to eq(10)
      expect(framebuffer.height).to eq(5)
    end

    it 'returns a Framebuffer with the correct pixel format' do
      canvas = ChromaWave::Canvas.new(width: 4, height: 4, background: white)
      framebuffer = renderer.render(canvas)
      expect(framebuffer.pixel_format).to equal(mono_format)
    end

    it 'delegates to the dither strategy' do
      canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
      framebuffer = renderer.render(canvas)
      8.times do |x|
        4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:black) }
      end
    end

    context 'with into: parameter' do
      it 'reuses a provided framebuffer' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
        existing = ChromaWave::Framebuffer.new(8, 4, mono_format)
        result = renderer.render(canvas, into: existing)
        expect(result).to equal(existing)
      end

      it 'raises ArgumentError on dimension mismatch' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
        wrong_size = ChromaWave::Framebuffer.new(16, 4, mono_format)
        expect { renderer.render(canvas, into: wrong_size) }
          .to raise_error(ArgumentError, /dimensions/)
      end
    end

    context 'with error cases' do
      it 'raises TypeError for nil canvas' do
        expect { renderer.render(nil) }.to raise_error(TypeError, /expected Canvas/)
      end

      it 'raises TypeError for wrong type' do
        expect { renderer.render('not a canvas') }.to raise_error(TypeError, /expected Canvas/)
      end
    end
  end

  describe '#render_dual' do
    let(:renderer) { described_class.new(pixel_format: tricolor, dither: :threshold) }

    it 'raises ArgumentError if pixel_format is not COLOR4' do
      mono_renderer = described_class.new(pixel_format: mono_format, dither: :threshold)
      canvas = ChromaWave::Canvas.new(width: 4, height: 4, background: white)
      expect { mono_renderer.render_dual(canvas) }
        .to raise_error(ArgumentError, /COLOR4/)
    end

    it 'returns an array of two MONO framebuffers' do
      canvas = ChromaWave::Canvas.new(width: 4, height: 4, background: white)
      black_fb, red_fb = renderer.render_dual(canvas)
      expect(black_fb.pixel_format).to equal(ChromaWave::PixelFormat::MONO)
      expect(red_fb.pixel_format).to equal(ChromaWave::PixelFormat::MONO)
    end

    it 'returns framebuffers with correct dimensions' do
      canvas = ChromaWave::Canvas.new(width: 8, height: 6, background: white)
      black_fb, red_fb = renderer.render_dual(canvas)
      expect(black_fb.width).to eq(8)
      expect(black_fb.height).to eq(6)
      expect(red_fb.width).to eq(8)
      expect(red_fb.height).to eq(6)
    end

    it 'splits black pixels correctly (black=0, red=1)' do
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: black)
      black_fb, red_fb = renderer.render_dual(canvas)
      expect(black_fb.get_pixel(0, 0)).to eq(:black)
      expect(red_fb.get_pixel(0, 0)).to eq(:white)
    end

    it 'splits white pixels correctly (black=1, red=1)' do
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: white)
      black_fb, red_fb = renderer.render_dual(canvas)
      expect(black_fb.get_pixel(0, 0)).to eq(:white)
      expect(red_fb.get_pixel(0, 0)).to eq(:white)
    end

    it 'splits red pixels correctly (black=1, red=0)' do
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: red)
      black_fb, red_fb = renderer.render_dual(canvas)
      expect(black_fb.get_pixel(0, 0)).to eq(:white)
      expect(red_fb.get_pixel(0, 0)).to eq(:black)
    end

    it 'splits yellow pixels correctly (black=1, red=0)' do
      yellow = ChromaWave::Color::YELLOW
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: yellow)
      black_fb, red_fb = renderer.render_dual(canvas)
      expect(black_fb.get_pixel(0, 0)).to eq(:white)
      expect(red_fb.get_pixel(0, 0)).to eq(:black)
    end

    it 'raises TypeError for nil canvas' do
      expect { renderer.render_dual(nil) }.to raise_error(TypeError, /expected Canvas/)
    end
  end
end
