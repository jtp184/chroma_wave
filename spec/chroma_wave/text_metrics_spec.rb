# frozen_string_literal: true

RSpec.describe ChromaWave::TextMetrics do
  subject(:metrics) { described_class.new(width: 100, height: 20, ascent: 16, descent: 4) }

  it 'stores width, height, ascent, and descent' do
    expect(metrics.width).to eq(100)
    expect(metrics.height).to eq(20)
    expect(metrics.ascent).to eq(16)
    expect(metrics.descent).to eq(4)
  end

  it 'is frozen' do
    expect(metrics).to be_frozen
  end

  it 'supports structural equality' do
    other = described_class.new(width: 100, height: 20, ascent: 16, descent: 4)
    expect(metrics).to eq(other)
  end
end
