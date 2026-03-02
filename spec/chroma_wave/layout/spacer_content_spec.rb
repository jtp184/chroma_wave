# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::SpacerContent do
  subject(:node) { described_class.new }

  it 'has zero intrinsic width' do
    expect(node.intrinsic_width).to eq(0)
  end

  it 'has zero intrinsic height' do
    expect(node.intrinsic_height).to eq(0)
  end

  it 'defaults to flex: 1' do
    expect(node.flex).to eq(1)
  end

  it 'accepts a custom flex value' do
    expect(described_class.new(flex: 3).flex).to eq(3)
  end

  describe '#container?' do
    it 'returns false' do
      expect(node.container?).to be false
    end
  end

  describe '#inspect' do
    it 'shows the flex value' do
      expect(node.inspect).to include('flex=1')
    end
  end

  describe '#flex?' do
    it 'returns true' do
      expect(node.flex?).to be true
    end
  end

  it 'inherits Node sizing properties' do
    node = described_class.new(flex: 2, width: 50, min_width: 10)
    expect(node.fixed_width).to eq(50)
    expect(node.constraints.min_width).to eq(10)
  end
end
