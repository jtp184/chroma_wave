# frozen_string_literal: true

RSpec.describe ChromaWave::Pen do
  let(:black) { ChromaWave::Color::BLACK }
  let(:red)   { ChromaWave::Color::RED }

  describe 'construction' do
    it 'creates a stroke-only pen' do
      pen = described_class.new(stroke: black)
      expect(pen.stroke).to eq(black)
      expect(pen.fill).to be_nil
      expect(pen.stroke_width).to eq(1)
    end

    it 'creates a fill-only pen' do
      pen = described_class.new(fill: red)
      expect(pen.stroke).to be_nil
      expect(pen.fill).to eq(red)
    end

    it 'creates a pen with both stroke and fill' do
      pen = described_class.new(stroke: black, fill: red)
      expect(pen.stroke).to eq(black)
      expect(pen.fill).to eq(red)
    end

    it 'accepts a custom stroke_width' do
      pen = described_class.new(stroke: black, stroke_width: 3)
      expect(pen.stroke_width).to eq(3)
    end

    it 'raises when neither stroke nor fill provided' do
      expect { described_class.new }
        .to raise_error(ArgumentError, /at least one of stroke: or fill:/)
    end

    it 'raises when stroke_width is not a positive Integer' do
      expect { described_class.new(stroke: black, stroke_width: 0) }
        .to raise_error(ArgumentError, /stroke_width must be a positive Integer/)
    end

    it 'raises when stroke_width is negative' do
      expect { described_class.new(stroke: black, stroke_width: -1) }
        .to raise_error(ArgumentError, /stroke_width must be a positive Integer/)
    end

    it 'raises when stroke_width is a Float' do
      expect { described_class.new(stroke: black, stroke_width: 1.5) }
        .to raise_error(ArgumentError, /stroke_width must be a positive Integer/)
    end
  end

  describe 'predicates' do
    it '#stroke? returns true when stroke is present' do
      expect(described_class.new(stroke: black)).to be_stroke
    end

    it '#stroke? returns false when stroke is nil' do
      expect(described_class.new(fill: red)).not_to be_stroke
    end

    it '#fill? returns true when fill is present' do
      expect(described_class.new(fill: red)).to be_fill
    end

    it '#fill? returns false when fill is nil' do
      expect(described_class.new(stroke: black)).not_to be_fill
    end
  end

  describe '#stroke_only' do
    it 'returns a copy with fill stripped' do
      pen = described_class.new(stroke: black, fill: red, stroke_width: 2)
      result = pen.stroke_only
      expect(result.stroke).to eq(black)
      expect(result.fill).to be_nil
      expect(result.stroke_width).to eq(2)
    end

    it 'raises when pen has no stroke' do
      pen = described_class.new(fill: red)
      expect { pen.stroke_only }.to raise_error(ArgumentError)
    end
  end

  describe 'factory methods' do
    describe '.stroke' do
      it 'creates a stroke-only pen' do
        pen = described_class.stroke(black)
        expect(pen.stroke).to eq(black)
        expect(pen.fill).to be_nil
        expect(pen.stroke_width).to eq(1)
      end

      it 'accepts a width keyword' do
        pen = described_class.stroke(black, width: 3)
        expect(pen.stroke_width).to eq(3)
      end
    end

    describe '.fill' do
      it 'creates a fill-only pen' do
        pen = described_class.fill(red)
        expect(pen.fill).to eq(red)
        expect(pen.stroke).to be_nil
      end
    end
  end

  describe 'structural equality' do
    it 'considers equal pens as ==' do
      a = described_class.new(stroke: black, stroke_width: 2)
      b = described_class.new(stroke: black, stroke_width: 2)
      expect(a).to eq(b)
    end

    it 'considers different pens as not ==' do
      a = described_class.new(stroke: black)
      b = described_class.new(stroke: red)
      expect(a).not_to eq(b)
    end
  end

  describe 'immutability' do
    it 'is frozen' do
      pen = described_class.new(stroke: black)
      expect(pen).to be_frozen
    end
  end

  describe '#with' do
    it 'returns a modified copy' do
      pen = described_class.new(stroke: black)
      modified = pen.with(fill: red)
      expect(modified.stroke).to eq(black)
      expect(modified.fill).to eq(red)
    end
  end
end
