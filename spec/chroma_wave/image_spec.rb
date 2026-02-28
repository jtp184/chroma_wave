# frozen_string_literal: true

RSpec.describe ChromaWave::Image do
  describe '.require_vips!' do
    context 'when ruby-vips is not installed' do
      before do
        hide_const('Vips') if defined?(Vips)
        allow(described_class).to receive(:require).with('vips').and_raise(LoadError)
      end

      it 'raises DependencyError with install hint' do
        expect { described_class.load('any.png') }.to raise_error(
          ChromaWave::DependencyError,
          /ruby-vips is required/
        )
      end
    end
  end

  describe '.load' do
    context 'when ruby-vips is not installed' do
      before do
        hide_const('Vips') if defined?(Vips)
        allow(described_class).to receive(:require).with('vips').and_raise(LoadError)
      end

      it 'raises DependencyError' do
        expect { described_class.load('test.png') }.to raise_error(ChromaWave::DependencyError)
      end
    end
  end

  describe '.from_buffer' do
    context 'when ruby-vips is not installed' do
      before do
        hide_const('Vips') if defined?(Vips)
        allow(described_class).to receive(:require).with('vips').and_raise(LoadError)
      end

      it 'raises DependencyError' do
        expect { described_class.from_buffer('data') }.to raise_error(ChromaWave::DependencyError)
      end
    end
  end

  describe '#resize' do
    let(:vips_img) { double(width: 100, height: 50) }
    let(:image) { described_class.send(:new, vips_img) }

    it 'requires width or height' do
      expect { image.resize }.to raise_error(ArgumentError, /width or height required/)
    end
  end
end
