# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Node do
  describe '#initialize' do
    it 'defaults to no flex, no fixed dimensions, unconstrained' do
      node = described_class.new
      expect(node.flex).to be_nil
      expect(node.fixed_width).to be_nil
      expect(node.fixed_height).to be_nil
      expect(node.constraints).to be_unconstrained
      expect(node.align).to be_nil
      expect(node.valign).to be_nil
    end

    context 'with all sizing parameters' do
      subject(:node) do
        described_class.new(
          flex: 2, width: 100, height: 50,
          min_width: 10, max_width: 200,
          min_height: 5, max_height: 100,
          align: :center, valign: :bottom
        )
      end

      it 'stores flex and fixed dimensions' do
        expect(node).to have_attributes(flex: 2, fixed_width: 100, fixed_height: 50)
      end

      it 'stores constraints' do
        expect(node.constraints).to have_attributes(min_width: 10, max_width: 200)
      end

      it 'stores alignment' do
        expect(node).to have_attributes(align: :center, valign: :bottom)
      end
    end
  end

  describe '#flex?' do
    it 'returns false when flex is nil' do
      expect(described_class.new).not_to be_flex
    end

    it 'returns true when flex is positive' do
      expect(described_class.new(flex: 1)).to be_flex
    end
  end

  describe '#fixed_width?' do
    it 'returns false when width is nil' do
      expect(described_class.new).not_to be_fixed_width
    end

    it 'returns true when width is set' do
      expect(described_class.new(width: 100)).to be_fixed_width
    end
  end

  describe '#fixed_height?' do
    it 'returns false when height is nil' do
      expect(described_class.new).not_to be_fixed_height
    end

    it 'returns true when height is set' do
      expect(described_class.new(height: 50)).to be_fixed_height
    end
  end

  describe '#container?' do
    it 'returns false' do
      expect(described_class.new).not_to be_container
    end
  end

  describe '#intrinsic_width' do
    it 'returns 0' do
      expect(described_class.new.intrinsic_width).to eq(0)
    end
  end

  describe '#intrinsic_height' do
    it 'returns 0' do
      expect(described_class.new.intrinsic_height).to eq(0)
    end
  end

  describe '#inspect' do
    it 'shows dimensions with ? for unset' do
      expect(described_class.new.inspect).to include('?x?')
    end

    it 'shows fixed dimensions when set' do
      expect(described_class.new(width: 100, height: 50).inspect).to include('100x50')
    end

    it 'includes flex when set' do
      expect(described_class.new(flex: 2).inspect).to include('flex=2')
    end

    it 'omits flex when nil' do
      expect(described_class.new.inspect).not_to include('flex')
    end
  end

  describe 'validation' do
    it 'raises ArgumentError for negative width' do
      expect { described_class.new(width: -10) }.to raise_error(ArgumentError, /width must be non-negative/)
    end

    it 'raises ArgumentError for negative height' do
      expect { described_class.new(height: -5) }.to raise_error(ArgumentError, /height must be non-negative/)
    end

    it 'accepts zero width and height' do
      expect { described_class.new(width: 0, height: 0) }.not_to raise_error
    end

    it 'raises ArgumentError for negative flex' do
      expect { described_class.new(flex: -1) }.to raise_error(ArgumentError, /flex must be positive/)
    end

    it 'raises ArgumentError for zero flex' do
      expect { described_class.new(flex: 0) }.to raise_error(ArgumentError, /flex must be positive/)
    end

    it 'raises ArgumentError for invalid align' do
      expect { described_class.new(align: :middle) }.to raise_error(ArgumentError, /align must be one of/)
    end

    it 'raises ArgumentError for invalid valign' do
      expect { described_class.new(valign: :middle) }.to raise_error(ArgumentError, /valign must be one of/)
    end

    it 'accepts all valid align values' do
      %i[left center right].each do |a|
        expect { described_class.new(align: a) }.not_to raise_error
      end
    end

    it 'accepts all valid valign values' do
      %i[top center bottom].each do |v|
        expect { described_class.new(valign: v) }.not_to raise_error
      end
    end
  end
end
