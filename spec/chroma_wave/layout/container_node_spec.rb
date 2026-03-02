# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::ContainerNode do
  describe 'direction validation' do
    it 'accepts :horizontal' do
      expect { described_class.new(direction: :horizontal) }.not_to raise_error
    end

    it 'accepts :vertical' do
      expect { described_class.new(direction: :vertical) }.not_to raise_error
    end

    it 'rejects invalid direction' do
      expect do
        described_class.new(direction: :diagonal)
      end.to raise_error(ArgumentError, /direction must be :horizontal or :vertical/)
    end
  end

  describe 'border_width validation' do
    it 'accepts zero border_width' do
      expect do
        described_class.new(direction: :horizontal, border_width: 0)
      end.not_to raise_error
    end

    it 'accepts positive border_width' do
      expect do
        described_class.new(direction: :horizontal, border_width: 2)
      end.not_to raise_error
    end

    it 'rejects negative border_width' do
      expect do
        described_class.new(direction: :horizontal, border_width: -1)
      end.to raise_error(ArgumentError, /border_width must be non-negative/)
    end
  end
end
