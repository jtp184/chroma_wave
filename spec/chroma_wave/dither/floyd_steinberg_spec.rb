# frozen_string_literal: true

require_relative 'shared_examples'

RSpec.describe ChromaWave::Dither::FloydSteinberg do
  let(:gray_format) { ChromaWave::PixelFormat::GRAY4 }

  it_behaves_like 'a dither strategy'

  describe '#call' do
    it 'produces at least as many transitions as threshold on a gradient' do
      canvas = build_gradient_canvas(width: 16, height: 1)

      threshold_fb = render_with(ChromaWave::Dither::Threshold, gray_format, canvas)
      fs_fb = render_with(described_class, gray_format, canvas)

      expect(count_transitions(fs_fb, 16)).to be >= count_transitions(threshold_fb, 16)
    end
  end

  describe '.strategy_name' do
    it 'returns :floyd_steinberg' do
      expect(described_class.strategy_name).to eq(:floyd_steinberg)
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
end
