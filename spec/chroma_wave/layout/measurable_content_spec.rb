# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::MeasurableContent do
  # Test through TextContent, the simplest concrete includer.
  subject(:node) { ChromaWave::Layout::TextContent.new(text: 'Test', font: font, color: color) }

  let(:font) { ChromaWave::Font.default(size: 12) }
  let(:color) { ChromaWave::Color::BLACK }

  describe '#font' do
    it 'returns the font passed at construction' do
      expect(node.font).to equal(font)
    end
  end

  describe '#color' do
    it 'returns the color passed at construction' do
      expect(node.color).to equal(color)
    end
  end

  describe '#metrics' do
    it 'returns a measurement object' do
      expect(node.metrics).to respond_to(:width).and respond_to(:height)
    end

    it 'memoizes the result' do
      first = node.metrics
      second = node.metrics
      expect(first).to equal(second)
    end
  end

  describe '#intrinsic_width' do
    it 'delegates to metrics.width' do
      expect(node.intrinsic_width).to eq(node.metrics.width)
    end
  end

  describe '#intrinsic_height' do
    it 'delegates to metrics.height' do
      expect(node.intrinsic_height).to eq(node.metrics.height)
    end
  end
end
