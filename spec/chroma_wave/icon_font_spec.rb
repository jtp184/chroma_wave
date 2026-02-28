# frozen_string_literal: true

RSpec.describe ChromaWave::IconFont do
  describe '.lucide' do
    subject(:icons) { described_class.lucide(size: 24) }

    it 'loads the bundled Lucide icon font' do
      expect(icons).to be_a(described_class)
      expect(icons.path).to end_with('lucide.ttf')
      expect(icons.size).to eq(24)
    end

    it 'includes a large glyph map' do
      expect(icons.glyph_map.size).to be > 100
    end
  end

  describe '#icon_names' do
    subject(:icons) { described_class.lucide(size: 16) }

    it 'returns a sorted array of symbols' do
      names = icons.icon_names
      expect(names).to be_an(Array)
      expect(names.first).to be_a(Symbol)
      expect(names).to eq(names.sort)
    end

    it 'includes known icons' do
      expect(icons.icon_names).to include(:house, :activity)
    end
  end

  describe '#measure_icon' do
    subject(:icons) { described_class.lucide(size: 24) }

    it 'returns TextMetrics for a known icon' do
      metrics = icons.measure_icon(:house)
      expect(metrics).to be_a(ChromaWave::TextMetrics)
      expect(metrics.width).to be_positive
    end

    it 'raises KeyError for an unknown icon' do
      expect { icons.measure_icon(:nonexistent) }.to raise_error(KeyError)
    end
  end

  describe '#draw' do
    subject(:icons) { described_class.lucide(size: 24) }

    let(:canvas) { ChromaWave::Canvas.new(width: 50, height: 50) }

    it 'renders an icon onto the surface' do
      icons.draw(canvas, :house, x: 5, y: 5, color: ChromaWave::Color::BLACK)
      non_white = count_non_white(canvas)
      expect(non_white).to be_positive
    end

    it 'raises KeyError for an unknown icon name' do
      expect { icons.draw(canvas, :nonexistent, x: 0, y: 0, color: ChromaWave::Color::BLACK) }
        .to raise_error(KeyError)
    end
  end

  describe '#glyph_map' do
    subject(:icons) { described_class.lucide(size: 16) }

    it 'is frozen' do
      expect(icons.glyph_map).to be_frozen
    end

    it 'maps symbols to integer codepoints' do
      icons.glyph_map.each do |name, cp|
        expect(name).to be_a(Symbol)
        expect(cp).to be_a(Integer)
        break if name == :airplay # only check first few
      end
    end
  end
end
