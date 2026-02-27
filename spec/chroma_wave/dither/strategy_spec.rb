# frozen_string_literal: true

RSpec.describe ChromaWave::Dither::Strategy do
  let(:mono_format) { ChromaWave::PixelFormat::MONO }

  describe '#call' do
    it 'raises NotImplementedError' do
      strategy = described_class.new(pixel_format: mono_format)
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: ChromaWave::Color::BLACK)
      framebuffer = ChromaWave::Framebuffer.new(1, 1, mono_format)
      expect { strategy.call(canvas, framebuffer) }.to raise_error(NotImplementedError)
    end
  end

  describe '.strategy_name' do
    it 'derives name from class name' do
      expect(described_class.strategy_name).to eq(:strategy)
    end
  end
end
