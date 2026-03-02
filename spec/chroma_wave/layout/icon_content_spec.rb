# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::IconContent do
  subject(:node) { described_class.new(name: :house, font: icon_font, color: color) }

  let(:icon_font) { ChromaWave::IconFont.lucide(size: 24) }
  let(:color) { ChromaWave::Color::BLACK }

  describe '#name' do
    it 'returns the icon name' do
      expect(node.name).to eq(:house)
    end
  end

  describe '#font' do
    it 'returns the icon font' do
      expect(node.font).to equal(icon_font)
    end
  end

  describe '#color' do
    it 'returns the color' do
      expect(node.color).to equal(color)
    end
  end

  describe 'intrinsic sizing' do
    it 'reports intrinsic width from icon measurement' do
      expected = icon_font.measure_icon(:house).width
      expect(node.intrinsic_width).to eq(expected)
    end

    it 'reports intrinsic height from icon measurement' do
      expected = icon_font.measure_icon(:house).height
      expect(node.intrinsic_height).to eq(expected)
    end

    it 'memoizes icon measurement' do
      node.intrinsic_width
      node.intrinsic_height
      expect(node.metrics).to equal(node.metrics)
    end
  end

  describe '#inspect' do
    it 'includes the icon name and dimensions' do
      expect(node.inspect).to include(':house')
      expect(node.inspect).to match(/\d+x\d+/)
    end
  end

  describe '#container?' do
    it 'returns false' do
      expect(node.container?).to be false
    end
  end

  it 'forwards Node kwargs' do
    node = described_class.new(name: :wifi, font: icon_font, color: color, flex: 3, align: :right)
    expect(node.flex).to eq(3)
    expect(node.align).to eq(:right)
  end
end
