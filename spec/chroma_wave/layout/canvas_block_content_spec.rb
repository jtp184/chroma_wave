# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::CanvasBlockContent do
  let(:block) { -> {} }

  it 'has zero intrinsic width' do
    expect(described_class.new(block: block).intrinsic_width).to eq(0)
  end

  it 'has zero intrinsic height' do
    expect(described_class.new(block: block).intrinsic_height).to eq(0)
  end

  it 'stores the block' do
    node = described_class.new(block: block)
    expect(node.block).to equal(block)
  end
end
