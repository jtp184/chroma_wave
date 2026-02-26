# frozen_string_literal: true

RSpec.describe ChromaWave::PixelFormat do
  describe 'constants' do
    it 'defines MONO' do
      fmt = described_class::MONO
      expect(fmt.name).to eq(:mono)
      expect(fmt.bits_per_pixel).to eq(1)
      expect(fmt.palette.to_a).to eq(%i[black white])
    end

    it 'defines GRAY4' do
      fmt = described_class::GRAY4
      expect(fmt.name).to eq(:gray4)
      expect(fmt.bits_per_pixel).to eq(2)
      expect(fmt.palette.to_a).to eq(%i[black dark_gray light_gray white])
    end

    it 'defines COLOR4' do
      fmt = described_class::COLOR4
      expect(fmt.name).to eq(:color4)
      expect(fmt.bits_per_pixel).to eq(4)
      expect(fmt.palette.to_a).to eq(%i[black white yellow red])
    end

    it 'defines COLOR7' do
      fmt = described_class::COLOR7
      expect(fmt.name).to eq(:color7)
      expect(fmt.bits_per_pixel).to eq(4)
      expect(fmt.palette.to_a).to eq(%i[black white green blue red yellow orange])
    end
  end

  describe '#pixels_per_byte' do
    it 'returns 8 for MONO (1bpp)' do
      expect(described_class::MONO.pixels_per_byte).to eq(8)
    end

    it 'returns 4 for GRAY4 (2bpp)' do
      expect(described_class::GRAY4.pixels_per_byte).to eq(4)
    end

    it 'returns 2 for COLOR4 (4bpp)' do
      expect(described_class::COLOR4.pixels_per_byte).to eq(2)
    end

    it 'returns 2 for COLOR7 (4bpp)' do
      expect(described_class::COLOR7.pixels_per_byte).to eq(2)
    end
  end

  describe '#buffer_size' do
    it 'matches C for MONO 122x250' do
      fb = ChromaWave::Framebuffer.new(122, 250, :mono)
      expect(described_class::MONO.buffer_size(122, 250)).to eq(fb.buffer_size)
    end

    it 'matches C for GRAY4 10x20' do
      fb = ChromaWave::Framebuffer.new(10, 20, :gray4)
      expect(described_class::GRAY4.buffer_size(10, 20)).to eq(fb.buffer_size)
    end

    it 'matches C for COLOR4 11x10' do
      fb = ChromaWave::Framebuffer.new(11, 10, :color4)
      expect(described_class::COLOR4.buffer_size(11, 10)).to eq(fb.buffer_size)
    end

    it 'matches C for COLOR7 15x5' do
      fb = ChromaWave::Framebuffer.new(15, 5, :color7)
      expect(described_class::COLOR7.buffer_size(15, 5)).to eq(fb.buffer_size)
    end

    it 'handles width of 1' do
      expect(described_class::MONO.buffer_size(1, 1)).to eq(1)
    end

    it 'handles byte-aligned widths' do
      expect(described_class::MONO.buffer_size(16, 10)).to eq(20)
    end
  end

  describe '#valid_color?' do
    it 'returns true for palette colors' do
      expect(described_class::MONO.valid_color?(:black)).to be true
    end

    it 'returns false for non-palette colors' do
      expect(described_class::MONO.valid_color?(:red)).to be false
    end
  end

  describe '.from_name' do
    it 'looks up :mono' do
      expect(described_class.from_name(:mono)).to equal(described_class::MONO)
    end

    it 'looks up :gray4' do
      expect(described_class.from_name(:gray4)).to equal(described_class::GRAY4)
    end

    it 'looks up :color4' do
      expect(described_class.from_name(:color4)).to equal(described_class::COLOR4)
    end

    it 'looks up :color7' do
      expect(described_class.from_name(:color7)).to equal(described_class::COLOR7)
    end

    it 'raises ArgumentError for unknown name' do
      expect { described_class.from_name(:rgb565) }
        .to raise_error(ArgumentError, /unknown pixel format/)
    end
  end

  describe 'immutability' do
    it 'REGISTRY is frozen' do
      expect(described_class::REGISTRY).to be_frozen
    end

    it 'constants are frozen (Data.define guarantee)' do
      expect(described_class::MONO).to be_frozen
    end
  end
end
