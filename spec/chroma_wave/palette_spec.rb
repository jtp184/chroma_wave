# frozen_string_literal: true

RSpec.describe ChromaWave::Palette do
  describe '.new / .[]' do
    it 'creates a palette from an array of color names' do
      palette = described_class.new(%i[black white])
      expect(palette.size).to eq(2)
    end

    it 'creates a palette with bracket constructor' do
      palette = described_class[:black, :white, :red]
      expect(palette.size).to eq(3)
    end

    it 'raises ArgumentError for unknown color names' do
      expect { described_class[:black, :magenta] }
        .to raise_error(ArgumentError, /unknown color name: :magenta/)
    end
  end

  describe 'Enumerable' do
    subject(:palette) { described_class[:black, :white, :red] }

    it 'iterates in order' do
      expect(palette.to_a).to eq(%i[black white red])
    end

    it 'supports map' do
      expect(palette.map(&:to_s)).to eq(%w[black white red])
    end

    it 'supports size' do
      expect(palette.size).to eq(3)
    end
  end

  describe '#include?' do
    subject(:palette) { described_class[:black, :white] }

    it 'returns true for entries in the palette' do
      expect(palette.include?(:black)).to be true
    end

    it 'returns false for entries not in the palette' do
      expect(palette.include?(:red)).to be false
    end
  end

  describe '#index_of' do
    subject(:palette) { described_class[:black, :white, :red, :yellow] }

    it 'returns 0 for the first entry' do
      expect(palette.index_of(:black)).to eq(0)
    end

    it 'returns 1 for the second entry' do
      expect(palette.index_of(:white)).to eq(1)
    end

    it 'returns the correct index for later entries' do
      expect(palette.index_of(:yellow)).to eq(3)
    end

    it 'raises KeyError for entries not in the palette' do
      expect { palette.index_of(:blue) }.to raise_error(KeyError)
    end
  end

  describe '#color_at' do
    subject(:palette) { described_class[:black, :white, :red] }

    it 'returns the first entry at index 0' do
      expect(palette.color_at(0)).to eq(:black)
    end

    it 'returns the last entry' do
      expect(palette.color_at(2)).to eq(:red)
    end

    it 'raises IndexError for out-of-range index' do
      expect { palette.color_at(5) }.to raise_error(IndexError)
    end
  end

  describe '#nearest_color' do
    subject(:palette) { described_class[:black, :white, :red, :blue] }

    it 'returns exact match for black' do
      expect(palette.nearest_color(ChromaWave::Color::BLACK)).to eq(:black)
    end

    it 'returns exact match for white' do
      expect(palette.nearest_color(ChromaWave::Color::WHITE)).to eq(:white)
    end

    it 'returns exact match for red' do
      expect(palette.nearest_color(ChromaWave::Color::RED)).to eq(:red)
    end

    it 'maps near-red to :red' do
      near_red = ChromaWave::Color.new(r: 240, g: 10, b: 10)
      expect(palette.nearest_color(near_red)).to eq(:red)
    end

    it 'maps dark blue to :blue not :black (redmean accuracy)' do
      dark_blue = ChromaWave::Color.new(r: 0, g: 0, b: 180)
      expect(palette.nearest_color(dark_blue)).to eq(:blue)
    end

    it 'memoizes results' do
      color = ChromaWave::Color.new(r: 200, g: 10, b: 10)
      result1 = palette.nearest_color(color)
      result2 = palette.nearest_color(color)
      expect(result1).to equal(result2)
    end
  end

  describe '#inspect' do
    it 'includes class name and entries' do
      palette = described_class[:black, :white]
      expect(palette.inspect).to eq('#<ChromaWave::Palette [black, white]>')
    end
  end

  describe 'hardware palette ordering' do
    it 'orders MONO as [black(0), white(1)]' do
      palette = described_class[:black, :white]
      expect(palette.index_of(:black)).to eq(0)
      expect(palette.index_of(:white)).to eq(1)
    end

    it 'orders GRAY4 as [black(0), dark_gray(1), light_gray(2), white(3)]' do
      palette = described_class[:black, :dark_gray, :light_gray, :white]
      expect(palette.index_of(:black)).to eq(0)
      expect(palette.index_of(:dark_gray)).to eq(1)
      expect(palette.index_of(:light_gray)).to eq(2)
      expect(palette.index_of(:white)).to eq(3)
    end

    it 'orders COLOR4 as [black(0), white(1), yellow(2), red(3)]' do
      palette = described_class[:black, :white, :yellow, :red]
      expect(palette.index_of(:black)).to eq(0)
      expect(palette.index_of(:white)).to eq(1)
      expect(palette.index_of(:yellow)).to eq(2)
      expect(palette.index_of(:red)).to eq(3)
    end

    it 'orders COLOR7 as [black(0)..orange(6)]' do
      palette = described_class[:black, :white, :green, :blue, :red, :yellow, :orange]
      expect(palette.index_of(:black)).to eq(0)
      expect(palette.index_of(:white)).to eq(1)
      expect(palette.index_of(:green)).to eq(2)
      expect(palette.index_of(:blue)).to eq(3)
      expect(palette.index_of(:red)).to eq(4)
      expect(palette.index_of(:yellow)).to eq(5)
      expect(palette.index_of(:orange)).to eq(6)
    end
  end
end
