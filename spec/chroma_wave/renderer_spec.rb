# frozen_string_literal: true

RSpec.describe ChromaWave::Renderer do
  let(:mono_format)   { ChromaWave::PixelFormat::MONO }
  let(:gray_format)   { ChromaWave::PixelFormat::GRAY4 }
  let(:tricolor)      { ChromaWave::PixelFormat::COLOR4 }
  let(:seven_color)   { ChromaWave::PixelFormat::COLOR7 }

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
    context 'with threshold dithering' do
      let(:renderer) { described_class.new(pixel_format: mono_format, dither: :threshold) }

      it 'renders a solid black canvas to an all-black framebuffer' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
        framebuffer = renderer.render(canvas)
        8.times do |x|
          4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:black) }
        end
      end

      it 'renders a solid white canvas to an all-white framebuffer' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: white)
        framebuffer = renderer.render(canvas)
        8.times do |x|
          4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:white) }
        end
      end

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

      it 'renders red to the nearest MONO palette color (black)' do
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: red)
        framebuffer = renderer.render(canvas)
        expect(framebuffer.get_pixel(0, 0)).to eq(:black)
      end

      context 'with GRAY4 format' do
        let(:renderer) { described_class.new(pixel_format: gray_format, dither: :threshold) }

        it 'maps pure black to :black' do
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: black)
          expect(renderer.render(canvas).get_pixel(0, 0)).to eq(:black)
        end

        it 'maps pure white to :white' do
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: white)
          expect(renderer.render(canvas).get_pixel(0, 0)).to eq(:white)
        end

        it 'maps mid-gray to a gray shade' do
          mid_gray = ChromaWave::Color.new(r: 128, g: 128, b: 128)
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: mid_gray)
          result = renderer.render(canvas).get_pixel(0, 0)
          expect(result).to eq(:dark_gray).or eq(:light_gray)
        end
      end

      context 'with COLOR4 format' do
        let(:renderer) { described_class.new(pixel_format: tricolor, dither: :threshold) }

        it 'maps pure red to :red' do
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: red)
          expect(renderer.render(canvas).get_pixel(0, 0)).to eq(:red)
        end

        it 'maps pure yellow to :yellow' do
          yellow = ChromaWave::Color::YELLOW
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: yellow)
          expect(renderer.render(canvas).get_pixel(0, 0)).to eq(:yellow)
        end
      end

      context 'with COLOR7 format' do
        let(:renderer) { described_class.new(pixel_format: seven_color, dither: :threshold) }

        it 'maps pure green to :green' do
          green = ChromaWave::Color::GREEN
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: green)
          expect(renderer.render(canvas).get_pixel(0, 0)).to eq(:green)
        end

        it 'maps pure blue to :blue' do
          blue = ChromaWave::Color::BLUE
          canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: blue)
          expect(renderer.render(canvas).get_pixel(0, 0)).to eq(:blue)
        end
      end
    end

    context 'with floyd_steinberg dithering' do
      it 'produces at least as many transitions as threshold on a gradient' do
        canvas = build_gradient_canvas(width: 16, height: 1)

        threshold_fb = render_with(gray_format, :threshold, canvas)
        fs_fb = render_with(gray_format, :floyd_steinberg, canvas)

        expect(count_transitions(fs_fb, 16)).to be >= count_transitions(threshold_fb, 16)
      end

      it 'renders a solid black canvas identically to threshold' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
        framebuffer = described_class.new(pixel_format: mono_format, dither: :floyd_steinberg).render(canvas)
        8.times do |x|
          4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:black) }
        end
      end

      it 'renders a solid white canvas identically to threshold' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: white)
        framebuffer = described_class.new(pixel_format: mono_format, dither: :floyd_steinberg).render(canvas)
        8.times do |x|
          4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:white) }
        end
      end
    end

    context 'with ordered dithering' do
      it 'produces at least as many unique pixels as threshold on a gradient' do
        canvas = build_gradient_canvas(width: 16, height: 4)

        threshold_fb = render_with(gray_format, :threshold, canvas)
        ordered_fb = render_with(gray_format, :ordered, canvas)

        threshold_pixels = collect_pixels(threshold_fb, 16, 4)
        ordered_pixels = collect_pixels(ordered_fb, 16, 4)

        expect(ordered_pixels.uniq.size).to be >= threshold_pixels.uniq.size
      end

      it 'renders a solid black canvas to all-black' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
        framebuffer = described_class.new(pixel_format: mono_format, dither: :ordered).render(canvas)
        8.times do |x|
          4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:black) }
        end
      end

      it 'renders a solid white canvas to all-white' do
        canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: white)
        framebuffer = described_class.new(pixel_format: mono_format, dither: :ordered).render(canvas)
        8.times do |x|
          4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:white) }
        end
      end
    end

    context 'with into: parameter' do
      let(:renderer) { described_class.new(pixel_format: mono_format, dither: :threshold) }

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
      let(:renderer) { described_class.new(pixel_format: mono_format, dither: :threshold) }

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

  private

  # Builds a horizontal gradient canvas from black to white.
  def build_gradient_canvas(width:, height:)
    canvas = ChromaWave::Canvas.new(width: width, height: height, background: ChromaWave::Color::BLACK)
    width.times do |x|
      val = (x * 255.0 / (width - 1)).round
      color = ChromaWave::Color.new(r: val, g: val, b: val)
      height.times { |y| canvas.set_pixel(x, y, color) }
    end
    canvas
  end

  # Renders a canvas with the given format and dither strategy.
  def render_with(format, strategy, canvas)
    described_class.new(pixel_format: format, dither: strategy).render(canvas)
  end

  # Counts color transitions across a single-row framebuffer.
  def count_transitions(framebuffer, width)
    transitions = 0
    (1...width).each do |x|
      transitions += 1 if framebuffer.get_pixel(x, 0) != framebuffer.get_pixel(x - 1, 0)
    end
    transitions
  end

  # Collects all pixel values from a framebuffer into a flat array.
  def collect_pixels(framebuffer, width, height)
    height.times.flat_map do |y|
      width.times.map { |x| framebuffer.get_pixel(x, y) }
    end
  end
end
