# frozen_string_literal: true

RSpec.describe ChromaWave::Layout do # rubocop:disable RSpec/SpecFilePathFormat
  describe ChromaWave::Layout::TextContent do
    let(:font) { ChromaWave::Font.default(size: 12) }
    let(:color) { ChromaWave::Color::BLACK }

    describe 'intrinsic sizing' do
      subject(:node) { described_class.new(text: 'Hello', font: font, color: color) }

      it 'reports intrinsic width from font measurement' do
        expected = font.measure('Hello').width
        expect(node.intrinsic_width).to eq(expected)
      end

      it 'reports intrinsic height from font measurement' do
        expected = font.measure('Hello').height
        expect(node.intrinsic_height).to eq(expected)
      end

      it 'memoizes font measurement' do
        node.intrinsic_width
        node.intrinsic_height

        expect(node.metrics).to equal(node.metrics)
      end
    end
  end

  describe ChromaWave::Layout::IconContent do
    let(:icon_font) { ChromaWave::IconFont.lucide(size: 24) }
    let(:color) { ChromaWave::Color::BLACK }

    describe 'intrinsic sizing' do
      subject(:node) { described_class.new(name: :house, font: icon_font, color: color) }

      it 'reports intrinsic width from icon measurement' do
        expected = icon_font.measure_icon(:house).width
        expect(node.intrinsic_width).to eq(expected)
      end

      it 'reports intrinsic height from icon measurement' do
        expected = icon_font.measure_icon(:house).height
        expect(node.intrinsic_height).to eq(expected)
      end

      it 'memoizes icon measurement' do
        node.intrinsic_width
        node.intrinsic_height

        expect(node.metrics).to equal(node.metrics)
      end
    end
  end

  describe ChromaWave::Layout::ImageContent do
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

  describe ChromaWave::Layout::SpacerContent do
    it 'has zero intrinsic width' do
      expect(described_class.new.intrinsic_width).to eq(0)
    end

    it 'has zero intrinsic height' do
      expect(described_class.new.intrinsic_height).to eq(0)
    end
  end

  describe ChromaWave::Layout::CanvasBlockContent do
    it 'has zero intrinsic width' do
      node = described_class.new(block: -> {})
      expect(node.intrinsic_width).to eq(0)
    end

    it 'has zero intrinsic height' do
      node = described_class.new(block: -> {})
      expect(node.intrinsic_height).to eq(0)
    end
  end
end
