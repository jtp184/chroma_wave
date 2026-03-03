# frozen_string_literal: true

RSpec.describe ChromaWave::Rect do
  describe '.new' do
    it 'creates a rect with the given attributes' do
      rect = described_class.new(x: 1, y: 2, width: 10, height: 20)
      expect(rect.x).to eq(1)
      expect(rect.y).to eq(2)
      expect(rect.width).to eq(10)
      expect(rect.height).to eq(20)
    end

    it 'is frozen' do
      rect = described_class.new(x: 0, y: 0, width: 5, height: 5)
      expect(rect).to be_frozen
    end
  end

  describe 'equality' do
    it 'considers rects with the same attributes equal' do
      a = described_class.new(x: 1, y: 2, width: 3, height: 4)
      b = described_class.new(x: 1, y: 2, width: 3, height: 4)
      expect(a).to eq(b)
    end

    it 'considers rects with different attributes not equal' do
      a = described_class.new(x: 1, y: 2, width: 3, height: 4)
      b = described_class.new(x: 1, y: 2, width: 3, height: 5)
      expect(a).not_to eq(b)
    end
  end

  describe '#union' do
    context 'with overlapping rects' do
      it 'returns the bounding rect' do
        a = described_class.new(x: 0, y: 0, width: 10, height: 10)
        b = described_class.new(x: 5, y: 5, width: 10, height: 10)
        result = a.union(b)
        expect(result).to eq(described_class.new(x: 0, y: 0, width: 15, height: 15))
      end
    end

    context 'with non-overlapping rects' do
      it 'returns the bounding rect spanning the gap' do
        a = described_class.new(x: 0, y: 0, width: 5, height: 5)
        b = described_class.new(x: 10, y: 10, width: 5, height: 5)
        result = a.union(b)
        expect(result).to eq(described_class.new(x: 0, y: 0, width: 15, height: 15))
      end
    end

    context 'when one rect contains the other' do
      it 'returns the larger rect' do
        outer = described_class.new(x: 0, y: 0, width: 20, height: 20)
        inner = described_class.new(x: 5, y: 5, width: 5, height: 5)
        expect(outer.union(inner)).to eq(outer)
      end
    end

    context 'with positional arguments' do
      it 'accepts four positional args' do
        a = described_class.new(x: 0, y: 0, width: 10, height: 10)
        result = a.union(5, 5, 10, 10)
        expect(result).to eq(described_class.new(x: 0, y: 0, width: 15, height: 15))
      end
    end

    context 'with missing positional arguments' do
      it 'raises ArgumentError when y is missing' do
        a = described_class.new(x: 0, y: 0, width: 10, height: 10)
        expect { a.union(5) }.to raise_error(ArgumentError, /four positional arguments/)
      end

      it 'raises ArgumentError when width and height are missing' do
        a = described_class.new(x: 0, y: 0, width: 10, height: 10)
        expect { a.union(5, 5) }.to raise_error(ArgumentError, /four positional arguments/)
      end

      it 'raises ArgumentError when height is missing' do
        a = described_class.new(x: 0, y: 0, width: 10, height: 10)
        expect { a.union(5, 5, 10) }.to raise_error(ArgumentError, /four positional arguments/)
      end
    end
  end

  describe '#deconstruct' do
    it 'supports array destructuring' do
      rect = described_class.new(x: 1, y: 2, width: 3, height: 4)
      x, y, w, h = rect.deconstruct
      expect([x, y, w, h]).to eq([1, 2, 3, 4])
    end
  end

  describe '#deconstruct_keys' do
    it 'supports pattern matching' do
      rect = described_class.new(x: 1, y: 2, width: 3, height: 4)
      case rect
      in { x: Integer => x, width: Integer => w }
        expect(x).to eq(1)
        expect(w).to eq(3)
      end
    end
  end
end
