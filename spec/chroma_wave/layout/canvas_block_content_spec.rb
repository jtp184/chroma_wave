# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::CanvasBlockContent do
  subject(:node) { described_class.new(block: block) }

  let(:block) { -> {} }

  it 'has zero intrinsic width' do
    expect(node.intrinsic_width).to eq(0)
  end

  it 'has zero intrinsic height' do
    expect(node.intrinsic_height).to eq(0)
  end

  it 'stores the block' do
    expect(node.block).to equal(block)
  end

  describe '#container?' do
    it 'returns false' do
      expect(node.container?).to be false
    end
  end

  describe '#inspect' do
    it 'includes the class name' do
      expect(node.inspect).to include('CanvasBlockContent')
    end
  end

  it 'forwards Node kwargs' do
    node = described_class.new(block: block, flex: 1, width: 100, height: 50)
    expect(node.flex).to eq(1)
    expect(node.fixed_width).to eq(100)
    expect(node.fixed_height).to eq(50)
  end

  it 'block receives arguments when called' do
    received = nil
    drawing_block = ->(layer) { received = layer }
    node = described_class.new(block: drawing_block)
    node.block.call(:mock_layer)
    expect(received).to eq(:mock_layer)
  end
end
