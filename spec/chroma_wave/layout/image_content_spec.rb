# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::ImageContent do
  let(:source) { instance_double(ChromaWave::Image, width: 100, height: 80) }

  describe 'intrinsic sizing' do
    subject(:node) { described_class.new(source: source) }

    it 'reports intrinsic width from source image' do
      expect(node.intrinsic_width).to eq(100)
    end

    it 'reports intrinsic height from source image' do
      expect(node.intrinsic_height).to eq(80)
    end
  end

  describe '#fit' do
    it 'defaults to :contain' do
      node = described_class.new(source: source)
      expect(node.fit).to eq(:contain)
    end

    it 'accepts a custom fit mode' do
      node = described_class.new(source: source, fit: :cover)
      expect(node.fit).to eq(:cover)
    end

    it 'rejects an invalid fit mode' do
      expect do
        described_class.new(source: source, fit: :banana)
      end.to raise_error(ArgumentError, /fit must be one of/)
    end
  end
end
