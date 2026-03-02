# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::SpacerContent do
  it 'has zero intrinsic width' do
    expect(described_class.new.intrinsic_width).to eq(0)
  end

  it 'has zero intrinsic height' do
    expect(described_class.new.intrinsic_height).to eq(0)
  end

  it 'defaults to flex: 1' do
    expect(described_class.new.flex).to eq(1)
  end

  it 'accepts a custom flex value' do
    expect(described_class.new(flex: 3).flex).to eq(3)
  end
end
