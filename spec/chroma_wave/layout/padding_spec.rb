# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Padding do
  describe '.parse' do
    context 'with nil' do
      it 'returns zero padding' do
        padding = described_class.parse(nil)
        expect(padding).to eq(described_class.new(top: 0, right: 0, bottom: 0, left: 0))
      end
    end

    context 'with zero' do
      it 'returns zero padding' do
        padding = described_class.parse(0)
        expect(padding).to eq(described_class.new(top: 0, right: 0, bottom: 0, left: 0))
      end
    end

    context 'with an Integer' do
      it 'returns uniform padding' do
        padding = described_class.parse(10)
        expect(padding).to eq(described_class.new(top: 10, right: 10, bottom: 10, left: 10))
      end
    end

    context 'with a 4-element Array' do
      it 'returns explicit edge padding' do
        padding = described_class.parse([5, 10, 15, 20])
        expect(padding).to eq(described_class.new(top: 5, right: 10, bottom: 15, left: 20))
      end
    end

    context 'with a 2-element Array' do
      it 'returns vertical/horizontal padding' do
        padding = described_class.parse([5, 10])
        expect(padding).to eq(described_class.new(top: 5, right: 10, bottom: 5, left: 10))
      end
    end

    context 'with a 1-element Array' do
      it 'returns uniform padding' do
        padding = described_class.parse([8])
        expect(padding).to eq(described_class.new(top: 8, right: 8, bottom: 8, left: 8))
      end
    end

    context 'with a Padding instance' do
      it 'returns the same instance' do
        original = described_class.new(top: 1, right: 2, bottom: 3, left: 4)
        expect(described_class.parse(original)).to equal(original)
      end
    end

    context 'with an invalid Array length' do
      it 'raises ArgumentError' do
        expect { described_class.parse([1, 2, 3]) }.to raise_error(ArgumentError, /expected 1, 2, or 4/)
      end
    end

    context 'with an unsupported type' do
      it 'raises ArgumentError' do
        expect { described_class.parse('10') }.to raise_error(ArgumentError, /cannot parse/)
      end
    end
  end

  describe 'negative value validation' do
    it 'raises ArgumentError for negative uniform padding' do
      expect { described_class.parse(-5) }.to raise_error(ArgumentError, /non-negative/)
    end

    it 'raises ArgumentError for negative values in array' do
      expect { described_class.parse([1, -2, 3, 4]) }.to raise_error(ArgumentError, /non-negative/)
    end

    it 'raises ArgumentError for negative values via constructor' do
      expect do
        described_class.new(top: 0, right: 0, bottom: -1, left: 0)
      end.to raise_error(ArgumentError, /non-negative/)
    end
  end

  describe '::ZERO' do
    it 'is accessible as Padding::ZERO' do
      expect(described_class::ZERO).to eq(described_class.new(top: 0, right: 0, bottom: 0, left: 0))
    end

    it 'is frozen' do
      expect(described_class::ZERO).to be_frozen
    end
  end

  describe '#horizontal' do
    it 'returns left + right' do
      padding = described_class.new(top: 1, right: 10, bottom: 3, left: 5)
      expect(padding.horizontal).to eq(15)
    end
  end

  describe '#vertical' do
    it 'returns top + bottom' do
      padding = described_class.new(top: 8, right: 1, bottom: 12, left: 1)
      expect(padding.vertical).to eq(20)
    end
  end
end
