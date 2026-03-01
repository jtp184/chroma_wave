# frozen_string_literal: true

# Helper to detect whether libvips is available at runtime.
VIPS_AVAILABLE = begin
  require 'vips'
  true
rescue LoadError
  false
end

RSpec.describe ChromaWave::Image do
  let(:fixture_path) { File.join(__dir__, '..', 'fixtures', 'images', '2x2_rgba.png') }

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

    context 'when ruby-vips is available', if: VIPS_AVAILABLE do
      it 'loads a PNG and reports correct dimensions' do
        image = described_class.load(fixture_path)
        expect(image.width).to eq(2)
        expect(image.height).to eq(2)
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

    context 'when ruby-vips is available', if: VIPS_AVAILABLE do
      it 'loads an image from raw buffer data' do
        data = File.binread(fixture_path)
        image = described_class.from_buffer(data)
        expect(image.width).to eq(2)
        expect(image.height).to eq(2)
      end
    end
  end

  describe '#resize' do
    it 'requires width or height' do
      vips_img = double(width: 100, height: 50)
      image = described_class.new(vips_img)
      expect { image.resize }.to raise_error(ArgumentError, /width or height required/)
    end

    context 'when ruby-vips is available', if: VIPS_AVAILABLE do
      let(:image) { described_class.load(fixture_path) }

      it 'resizes by width preserving aspect ratio' do
        resized = image.resize(width: 4)
        expect(resized.width).to eq(4)
        expect(resized.height).to eq(4)
      end

      it 'resizes by height preserving aspect ratio' do
        resized = image.resize(height: 4)
        expect(resized.width).to eq(4)
        expect(resized.height).to eq(4)
      end

      it 'resizes by both dimensions (may stretch)' do
        resized = image.resize(width: 6, height: 4)
        expect(resized.width).to eq(6)
        expect(resized.height).to eq(4)
      end
    end
  end

  describe '#crop', if: VIPS_AVAILABLE do
    it 'returns a cropped sub-region' do
      image = described_class.load(fixture_path)
      cropped = image.crop(x: 0, y: 0, width: 1, height: 1)
      expect(cropped.width).to eq(1)
      expect(cropped.height).to eq(1)
    end
  end

  describe '#to_rgba_bytes', if: VIPS_AVAILABLE do
    it 'returns raw RGBA bytes (4 bytes per pixel)' do
      image = described_class.load(fixture_path)
      bytes = image.to_rgba_bytes
      expect(bytes.bytesize).to eq(2 * 2 * 4) # 2x2 image, 4 bytes/pixel
      expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe '#draw_onto', if: VIPS_AVAILABLE do
    it 'transfers pixels onto a canvas' do
      image = described_class.load(fixture_path)
      canvas = ChromaWave::Canvas.new(width: 10, height: 10)
      image.draw_onto(canvas, x: 0, y: 0)

      # At least one pixel in the 2x2 region should differ from the default white
      drawn_pixels = (0...2).flat_map { |x| (0...2).map { |y| canvas.get_pixel(x, y) } }
      expect(drawn_pixels.any? { |p| p != ChromaWave::Color::WHITE }).to be(true)
    end
  end

  describe '#to_canvas', if: VIPS_AVAILABLE do
    it 'creates a canvas with the image dimensions' do
      image = described_class.load(fixture_path)
      canvas = image.to_canvas
      expect(canvas.width).to eq(2)
      expect(canvas.height).to eq(2)
    end
  end
end
