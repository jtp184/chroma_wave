# frozen_string_literal: true

# Shared test helpers for dither strategy specs.
module DitherSpecHelpers
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

  # Renders a canvas using a strategy class and format.
  def render_with(strategy_class, format, canvas)
    framebuffer = ChromaWave::Framebuffer.new(canvas.width, canvas.height, format)
    strategy_class.new(pixel_format: format).call(canvas, framebuffer)
    framebuffer
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
    pixels = []
    height.times do |y|
      width.times { |x| pixels << framebuffer.get_pixel(x, y) }
    end
    pixels
  end
end

RSpec.shared_examples 'a dither strategy' do
  let(:mono_format) { ChromaWave::PixelFormat::MONO }
  let(:gray_format) { ChromaWave::PixelFormat::GRAY4 }
  let(:tricolor)    { ChromaWave::PixelFormat::COLOR4 }

  let(:black) { ChromaWave::Color::BLACK }
  let(:white) { ChromaWave::Color::WHITE }

  describe '#call' do
    it 'renders a solid black canvas to an all-black framebuffer' do
      canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: black)
      framebuffer = ChromaWave::Framebuffer.new(8, 4, mono_format)
      strategy = described_class.new(pixel_format: mono_format)
      strategy.call(canvas, framebuffer)
      8.times do |x|
        4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:black) }
      end
    end

    it 'renders a solid white canvas to an all-white framebuffer' do
      canvas = ChromaWave::Canvas.new(width: 8, height: 4, background: white)
      framebuffer = ChromaWave::Framebuffer.new(8, 4, mono_format)
      strategy = described_class.new(pixel_format: mono_format)
      strategy.call(canvas, framebuffer)
      8.times do |x|
        4.times { |y| expect(framebuffer.get_pixel(x, y)).to eq(:white) }
      end
    end
  end

  describe '.strategy_name' do
    it 'returns a Symbol' do
      expect(described_class.strategy_name).to be_a(Symbol)
    end

    it 'is registered in Dither::REGISTRY' do
      expect(ChromaWave::Dither::REGISTRY[described_class.strategy_name]).to eq(described_class)
    end
  end
end
