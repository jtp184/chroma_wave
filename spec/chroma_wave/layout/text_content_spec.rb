# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::TextContent do
  subject(:node) { described_class.new(text: 'Hello', font: font, color: color) }

  let(:font) { ChromaWave::Font.default(size: 12) }
  let(:color) { ChromaWave::Color::BLACK }

  describe '#text' do
    it 'returns the text' do
      expect(node.text).to eq('Hello')
    end
  end

  describe '#font' do
    it 'returns the font' do
      expect(node.font).to equal(font)
    end
  end

  describe '#color' do
    it 'returns the color' do
      expect(node.color).to equal(color)
    end
  end

  describe 'intrinsic sizing' do
    it 'reports intrinsic width from font measurement' do
      expected = font.measure('Hello').width
      expect(node.intrinsic_width).to eq(expected)
    end

    it 'reports intrinsic height from font measurement' do
      expected = font.measure('Hello').height
      expect(node.intrinsic_height).to eq(expected)
    end

    it 'memoizes font measurement' do
      node.intrinsic_width
      node.intrinsic_height
      expect(node.metrics).to equal(node.metrics)
    end
  end

  describe '#inspect' do
    it 'includes the text and dimensions' do
      expect(node.inspect).to include('Hello')
      expect(node.inspect).to match(/\d+x\d+/)
    end
  end

  describe '#container?' do
    it 'returns false' do
      expect(node.container?).to be false
    end
  end

  it 'forwards Node kwargs' do
    node = described_class.new(text: 'Hi', font: font, color: color, flex: 2, align: :center)
    expect(node.flex).to eq(2)
    expect(node.align).to eq(:center)
  end
end
