# frozen_string_literal: true

RSpec.describe ChromaWave::Dither do
  let(:mono_format) { ChromaWave::PixelFormat::MONO }

  describe '.strategies' do
    it 'returns all registered strategy names' do
      expect(described_class.strategies).to contain_exactly(:floyd_steinberg, :ordered, :threshold)
    end

    it 'returns a sorted array' do
      expect(described_class.strategies).to eq(described_class.strategies.sort)
    end
  end

  describe '.resolve' do
    it 'returns a Threshold instance for :threshold' do
      strategy = described_class.resolve(:threshold, pixel_format: mono_format)
      expect(strategy).to be_a(ChromaWave::Dither::Threshold)
    end

    it 'returns a FloydSteinberg instance for :floyd_steinberg' do
      strategy = described_class.resolve(:floyd_steinberg, pixel_format: mono_format)
      expect(strategy).to be_a(ChromaWave::Dither::FloydSteinberg)
    end

    it 'returns an Ordered instance for :ordered' do
      strategy = described_class.resolve(:ordered, pixel_format: mono_format)
      expect(strategy).to be_a(ChromaWave::Dither::Ordered)
    end

    it 'passes pixel_format to the strategy' do
      strategy = described_class.resolve(:threshold, pixel_format: mono_format)
      expect(strategy.pixel_format).to equal(mono_format)
    end

    it 'raises ArgumentError for unknown strategy' do
      expect { described_class.resolve(:halftone, pixel_format: mono_format) }
        .to raise_error(ArgumentError, /unknown dither strategy/)
    end
  end
end
