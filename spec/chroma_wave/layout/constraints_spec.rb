# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Constraints do
  describe '#initialize' do
    it 'defaults to unconstrained' do
      c = described_class.new
      expect(c.min_width).to eq(0)
      expect(c.min_height).to eq(0)
      expect(c.max_width).to be_nil
      expect(c.max_height).to be_nil
    end
  end

  describe 'bounds validation' do
    it 'raises when max_width < min_width' do
      expect do
        described_class.new(min_width: 200, max_width: 100)
      end.to raise_error(ArgumentError, /max_width.*must be >= min_width/)
    end

    it 'raises when max_height < min_height' do
      expect do
        described_class.new(min_height: 80, max_height: 40)
      end.to raise_error(ArgumentError, /max_height.*must be >= min_height/)
    end

    it 'accepts max equal to min' do
      expect { described_class.new(min_width: 100, max_width: 100) }.not_to raise_error
    end

    it 'raises when min_width is negative' do
      expect do
        described_class.new(min_width: -5)
      end.to raise_error(ArgumentError, /min_width must be non-negative/)
    end

    it 'raises when min_height is negative' do
      expect do
        described_class.new(min_height: -3)
      end.to raise_error(ArgumentError, /min_height must be non-negative/)
    end
  end

  describe '#clamp_width' do
    context 'with min constraint' do
      it 'clamps up to minimum' do
        c = described_class.new(min_width: 50)
        expect(c.clamp_width(30)).to eq(50)
      end
    end

    context 'with max constraint' do
      it 'clamps down to maximum' do
        c = described_class.new(max_width: 100)
        expect(c.clamp_width(150)).to eq(100)
      end
    end

    context 'with both constraints' do
      it 'clamps within range' do
        c = described_class.new(min_width: 50, max_width: 200)
        expect(c.clamp_width(100)).to eq(100)
      end
    end

    context 'with no constraints' do
      it 'passes through unchanged' do
        c = described_class.new
        expect(c.clamp_width(42)).to eq(42)
      end
    end
  end

  describe '#clamp_height' do
    it 'clamps to min' do
      c = described_class.new(min_height: 20)
      expect(c.clamp_height(10)).to eq(20)
    end

    it 'clamps to max' do
      c = described_class.new(max_height: 80)
      expect(c.clamp_height(100)).to eq(80)
    end
  end

  describe '#unconstrained?' do
    it 'returns true for default constraints' do
      expect(described_class.new).to be_unconstrained
    end

    it 'returns false when min_width is set' do
      expect(described_class.new(min_width: 10)).not_to be_unconstrained
    end

    it 'returns false when max_width is set' do
      expect(described_class.new(max_width: 100)).not_to be_unconstrained
    end
  end

  describe 'NONE' do
    it 'is an unconstrained singleton' do
      expect(described_class::NONE).to be_unconstrained
    end
  end
end
