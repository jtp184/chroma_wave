# frozen_string_literal: true

RSpec.describe ChromaWave::Font do
  let(:font_path) { File.join(described_class::DATA_DIR, 'fonts', 'dejavu-sans.ttf') }

  describe '.new' do
    context 'with an absolute path' do
      subject(:font) { described_class.new(font_path, size: 16) }

      it 'loads the font file' do
        expect(font.path).to eq(font_path)
        expect(font.size).to eq(16)
      end
    end

    context 'with a font name' do
      subject(:font) { described_class.new('dejavu-sans', size: 16) }

      it 'discovers the font from bundled data dir' do
        expect(font.path).to end_with('dejavu-sans.ttf')
      end
    end

    context 'with an unknown font name' do
      it 'raises ArgumentError' do
        expect { described_class.new('NonexistentFont12345', size: 16) }
          .to raise_error(ArgumentError, /font not found/i)
      end
    end

    context 'with zero size' do
      it 'raises ArgumentError' do
        expect { described_class.new(font_path, size: 0) }
          .to raise_error(ArgumentError, /positive/)
      end
    end

    context 'with negative size' do
      it 'raises ArgumentError' do
        expect { described_class.new(font_path, size: -1) }
          .to raise_error(ArgumentError, /positive/)
      end
    end

    context 'without FreeType' do
      before do
        allow_any_instance_of(described_class) # rubocop:disable RSpec/AnyInstance
          .to receive(:respond_to?).and_call_original
        allow_any_instance_of(described_class) # rubocop:disable RSpec/AnyInstance
          .to receive(:respond_to?).with(:_ft_load_face, true).and_return(false)
      end

      it 'raises DependencyError' do
        expect { described_class.new(font_path, size: 16) }
          .to raise_error(ChromaWave::DependencyError, /FreeType/)
      end
    end
  end

  describe 'font discovery cache immutability' do
    before { described_class.clear_font_cache! }

    it 'freezes the outer candidates array' do
      described_class.new('dejavu-sans', size: 16)
      cache = described_class.instance_variable_get(:@font_cache)
      expect(cache).to be_frozen
    end

    it 'freezes each inner [stem, path] pair' do
      described_class.new('dejavu-sans', size: 16)
      cache = described_class.instance_variable_get(:@font_cache)
      expect(cache).to all be_frozen
    end
  end

  describe '.clear_font_cache!' do
    it 'clears the cached font candidates' do
      # Warm the cache by discovering a font by name
      described_class.new('dejavu-sans', size: 16)
      expect(described_class.instance_variable_get(:@font_cache)).not_to be_nil

      described_class.clear_font_cache!
      expect(described_class.instance_variable_get(:@font_cache)).to be_nil
    end
  end

  describe '.default' do
    subject(:font) { described_class.default(size: 20) }

    it 'loads the bundled DejaVu Sans' do
      expect(font.path).to end_with('dejavu-sans.ttf')
      expect(font.size).to eq(20)
    end
  end

  describe '#line_height' do
    subject(:font) { described_class.new(font_path, size: 16) }

    it 'returns a positive integer' do
      expect(font.line_height).to be_a(Integer)
      expect(font.line_height).to be_positive
    end
  end

  describe '#ascent' do
    subject(:font) { described_class.new(font_path, size: 16) }

    it 'returns a positive integer' do
      expect(font.ascent).to be_a(Integer)
      expect(font.ascent).to be_positive
    end
  end

  describe '#descent' do
    subject(:font) { described_class.new(font_path, size: 16) }

    it 'returns a non-negative integer' do
      expect(font.descent).to be_a(Integer)
      expect(font.descent).to be >= 0
    end
  end

  describe '#measure' do
    subject(:font) { described_class.new(font_path, size: 16) }

    it 'returns TextMetrics with positive width for non-empty text' do
      metrics = font.measure('Hello')
      expect(metrics).to be_a(ChromaWave::TextMetrics)
      expect(metrics.width).to be_positive
      expect(metrics.height).to eq(font.line_height)
    end

    it 'returns zero width for empty text' do
      metrics = font.measure('')
      expect(metrics.width).to eq(0)
    end

    it 'returns wider metrics for longer text' do
      short = font.measure('Hi')
      long = font.measure('Hello World')
      expect(long.width).to be > short.width
    end

    it 'returns the widest line width for multi-line text' do
      single = font.measure('Hello World')
      multi = font.measure("Hi\nHello World")
      expect(multi.width).to eq(single.width)
    end

    it 'returns multi-line height for text with newlines' do
      multi = font.measure("A\nB\nC")
      expect(multi.height).to eq(font.line_height * 3)
    end

    it 'counts a trailing newline as an extra line' do
      trailing = font.measure("Hello\n")
      expect(trailing.height).to eq(font.line_height * 2)
    end
  end

  describe '#each_glyph' do
    subject(:font) { described_class.new(font_path, size: 16) }

    it 'yields glyph data for each character' do
      glyphs = font.each_glyph('AB').to_a
      expect(glyphs.length).to eq(2)

      glyph = glyphs.first
      expect(glyph).to include(:bitmap, :x, :y, :width, :height)
      expect(glyph[:bitmap]).to be_a(String)
      expect(glyph[:bitmap].encoding).to eq(Encoding::ASCII_8BIT)
      expect(glyph[:width]).to be_positive
      expect(glyph[:height]).to be_positive
    end

    it 'returns an enumerator without a block' do
      expect(font.each_glyph('A')).to be_a(Enumerator)
    end

    it 'advances x position across glyphs' do
      glyphs = font.each_glyph('AB').to_a
      expect(glyphs[1][:x]).to be > glyphs[0][:x]
    end

    it 'returns bitmap bytesize equal to width * height for all glyphs' do
      # Verifies the pitch-aware copy produces a tightly packed bitmap
      # (stride == width) regardless of FreeType internal representation.
      font.each_glyph('ABCDEFabcdefgxyz0123') do |glyph|
        expected = glyph[:width] * glyph[:height]
        expect(glyph[:bitmap].bytesize).to eq(expected),
                                           "glyph bitmap bytesize #{glyph[:bitmap].bytesize} != #{expected} " \
                                           "(#{glyph[:width]}x#{glyph[:height]})"
      end
    end
  end

  describe '#inspect' do
    subject(:font) { described_class.new(font_path, size: 16) }

    it 'includes the font basename and size' do
      expect(font.inspect).to match(/dejavu-sans\.ttf @16px/)
    end
  end
end
