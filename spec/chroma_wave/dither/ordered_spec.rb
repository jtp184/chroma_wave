# frozen_string_literal: true

require_relative 'shared_examples'

RSpec.describe ChromaWave::Dither::Ordered do
  let(:gray_format) { ChromaWave::PixelFormat::GRAY4 }

  it_behaves_like 'a dither strategy'

  describe '#call' do
    it 'produces at least as many unique pixels as threshold on a gradient' do
      canvas = build_gradient_canvas(width: 16, height: 4)

      threshold_fb = render_with(ChromaWave::Dither::Threshold, gray_format, canvas)
      ordered_fb = render_with(described_class, gray_format, canvas)

      threshold_pixels = collect_pixels(threshold_fb, 16, 4)
      ordered_pixels = collect_pixels(ordered_fb, 16, 4)

      expect(ordered_pixels.uniq.size).to be >= threshold_pixels.uniq.size
    end
  end

  describe '.strategy_name' do
    it 'returns :ordered' do
      expect(described_class.strategy_name).to eq(:ordered)
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

  # Collects all pixel values from a framebuffer into a flat array.
  def collect_pixels(framebuffer, width, height)
    height.times.flat_map do |y|
      width.times.map { |x| framebuffer.get_pixel(x, y) }
    end
  end
end
