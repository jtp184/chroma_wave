# frozen_string_literal: true

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
