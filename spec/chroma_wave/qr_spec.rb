# frozen_string_literal: true

RSpec.describe ChromaWave::QR do
  describe '::LEVEL_MAP' do
    it 'maps all four correction levels' do
      expect(described_class::LEVEL_MAP).to eq(
        low: :l, medium: :m, quartile: :q, high: :h
      )
    end

    it 'is frozen' do
      expect(described_class::LEVEL_MAP).to be_frozen
    end
  end

  describe '::Metrics' do
    subject(:metrics) { described_class::Metrics.new(width: 84, height: 84, modules: 21) }

    it 'is a frozen Data value object' do
      expect(metrics).to be_frozen
    end

    it 'exposes width, height, and modules' do
      expect(metrics.width).to eq(84)
      expect(metrics.height).to eq(84)
      expect(metrics.modules).to eq(21)
    end

    it 'supports structural equality' do
      other = described_class::Metrics.new(width: 84, height: 84, modules: 21)
      expect(metrics).to eq(other)
    end
  end

  describe '.measure' do
    it 'returns a Metrics with correct pixel dimensions' do
      metrics = described_class.measure('hello', module_size: 4)
      qr = RQRCode::QRCode.new('hello', level: :m)
      n = qr.modules.length
      expect(metrics.width).to eq(n * 4)
      expect(metrics.height).to eq(n * 4)
      expect(metrics.modules).to eq(n)
    end

    it 'uses the specified error correction level' do
      low = described_class.measure('hello', module_size: 1, error_correction: :low)
      high = described_class.measure('hello', module_size: 1, error_correction: :high)
      # Higher correction -> more modules (for non-trivial data)
      expect(high.modules).to be >= low.modules
    end

    it 'raises ArgumentError for an unknown error_correction level' do
      expect { described_class.measure('hello', module_size: 4, error_correction: :bad) }
        .to raise_error(ArgumentError, /unknown error_correction: :bad/)
    end
  end

  describe '.resolve_level' do
    %i[low medium quartile high].each do |level|
      it "resolves :#{level}" do
        expect(described_class.resolve_level(level)).to eq(described_class::LEVEL_MAP[level])
      end
    end

    it 'raises ArgumentError for unknown level' do
      expect { described_class.resolve_level(:extreme) }
        .to raise_error(ArgumentError, /unknown error_correction/)
    end
  end

  describe 'dependency guard' do
    before do
      hide_const('RQRCode') if defined?(RQRCode)
      # Stub the private require_rqrcode! to simulate missing gem
      allow(described_class).to receive(:require).with('rqrcode').and_raise(LoadError)
    end

    it 'raises DependencyError when rqrcode is not installed' do
      expect { described_class.measure('test', module_size: 4) }
        .to raise_error(ChromaWave::DependencyError, /rqrcode is required/)
    end
  end
end
