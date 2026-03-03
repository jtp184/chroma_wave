# frozen_string_literal: true

RSpec.describe ChromaWave::Barcode do
  describe '::SYMBOLOGIES' do
    it 'contains all supported symbology keys' do
      expect(described_class::SYMBOLOGIES.keys).to contain_exactly(:code128, :ean13, :ean8, :code39)
    end

    it 'is frozen' do
      expect(described_class::SYMBOLOGIES).to be_frozen
    end

    it 'has class_name and require_path for each symbology' do
      described_class::SYMBOLOGIES.each_value do |spec|
        expect(spec).to have_key(:class_name)
        expect(spec).to have_key(:require_path)
      end
    end
  end

  describe '::Metrics' do
    subject(:metrics) { described_class::Metrics.new(width: 200, height: 60, encoding_length: 100) }

    it 'is a frozen Data value object' do
      expect(metrics).to be_frozen
    end

    it 'exposes width, height, and encoding_length' do
      expect(metrics.width).to eq(200)
      expect(metrics.height).to eq(60)
      expect(metrics.encoding_length).to eq(100)
    end

    it 'supports structural equality' do
      other = described_class::Metrics.new(width: 200, height: 60, encoding_length: 100)
      expect(metrics).to eq(other)
    end
  end

  describe '.measure' do
    it 'returns a Metrics with correct dimensions' do
      metrics = described_class.measure('ABC123', symbology: :code128)
      expect(metrics.width).to eq(metrics.encoding_length * 2)
      expect(metrics.height).to eq(60)
    end

    it 'uses custom module_width' do
      metrics = described_class.measure('ABC123', symbology: :code128, module_width: 3)
      expect(metrics.width).to eq(metrics.encoding_length * 3)
    end

    it 'uses custom height' do
      metrics = described_class.measure('ABC123', symbology: :code128, height: 80)
      expect(metrics.height).to eq(80)
    end

    it 'includes text height when include_text is true' do
      font = ChromaWave::Font.default(size: 12)
      without_text = described_class.measure('ABC123', symbology: :code128, include_text: false)
      with_text = described_class.measure('ABC123', symbology: :code128,
                                                    include_text: true, text_font: font)
      expect(with_text.height).to be > without_text.height
    end

    it 'raises ArgumentError when include_text is true but text_font is nil' do
      expect { described_class.measure('ABC123', symbology: :code128, include_text: true) }
        .to raise_error(ArgumentError, /text_font:.*required.*include_text/)
    end

    it 'raises ArgumentError for unknown symbology' do
      expect { described_class.measure('test', symbology: :bad) }
        .to raise_error(ArgumentError, /unknown symbology: :bad/)
    end
  end

  describe '.build_barcode' do
    it 'returns a Barby barcode instance' do
      barcode = described_class.build_barcode(:code128, 'ABC123')
      expect(barcode).to be_a(Barby::Code128)
    end

    it 'raises ArgumentError for unknown symbology' do
      expect { described_class.build_barcode(:bad, 'test') }
        .to raise_error(ArgumentError, /unknown symbology: :bad/)
    end

    it 'wraps Barby errors with user-friendly message' do
      expect { described_class.build_barcode(:ean13, 'abc') }
        .to raise_error(ArgumentError, /invalid data for ean13/)
    end
  end

  describe 'dependency guard' do
    before do
      hide_const('Barby') if defined?(Barby)
      allow(described_class).to receive(:require).with('barby').and_raise(LoadError)
    end

    it 'raises DependencyError when barby is not installed' do
      expect { described_class.build_barcode(:code128, 'test') }
        .to raise_error(ChromaWave::DependencyError, /barby is required/)
    end
  end
end
