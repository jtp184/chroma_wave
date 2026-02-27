# frozen_string_literal: true

RSpec.describe ChromaWave::Canvas do
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red)   { ChromaWave::Color::RED }
  let(:transparent) { ChromaWave::Color::TRANSPARENT }

  describe '#initialize' do
    it 'creates a canvas with the given dimensions' do
      canvas = described_class.new(width: 10, height: 5)
      expect(canvas.width).to eq(10)
      expect(canvas.height).to eq(5)
    end

    it 'defaults background to white' do
      canvas = described_class.new(width: 2, height: 2)
      expect(canvas.get_pixel(0, 0)).to eq(white)
    end

    it 'accepts a custom background color' do
      canvas = described_class.new(width: 2, height: 2, background: red)
      expect(canvas.get_pixel(0, 0)).to eq(red)
    end

    it 'raises ArgumentError for zero width' do
      expect { described_class.new(width: 0, height: 5) }
        .to raise_error(ArgumentError, /width/)
    end

    it 'raises ArgumentError for negative width' do
      expect { described_class.new(width: -1, height: 5) }
        .to raise_error(ArgumentError, /width/)
    end

    it 'raises ArgumentError for zero height' do
      expect { described_class.new(width: 5, height: 0) }
        .to raise_error(ArgumentError, /height/)
    end

    it 'raises ArgumentError for negative height' do
      expect { described_class.new(width: 5, height: -1) }
        .to raise_error(ArgumentError, /height/)
    end
  end

  describe '#set_pixel / #get_pixel round-trip' do
    subject(:canvas) { described_class.new(width: 10, height: 8) }

    it 'stores and retrieves a color at origin' do
      canvas.set_pixel(0, 0, red)
      expect(canvas.get_pixel(0, 0)).to eq(red)
    end

    it 'stores and retrieves a color at max corner' do
      canvas.set_pixel(9, 7, black)
      expect(canvas.get_pixel(9, 7)).to eq(black)
    end

    it 'preserves all four RGBA channels' do
      semi = ChromaWave::Color.new(r: 100, g: 150, b: 200, a: 128)
      canvas.set_pixel(3, 4, semi)
      expect(canvas.get_pixel(3, 4)).to eq(semi)
    end
  end

  describe 'out-of-bounds behavior' do
    subject(:canvas) { described_class.new(width: 5, height: 5) }

    it 'silently ignores set_pixel with negative x' do
      expect(canvas.set_pixel(-1, 0, red)).to equal(canvas)
    end

    it 'silently ignores set_pixel with x >= width' do
      expect(canvas.set_pixel(5, 0, red)).to equal(canvas)
    end

    it 'returns nil for get_pixel with negative y' do
      expect(canvas.get_pixel(0, -1)).to be_nil
    end

    it 'returns nil for get_pixel with y >= height' do
      expect(canvas.get_pixel(0, 5)).to be_nil
    end
  end

  describe '#clear' do
    subject(:canvas) { described_class.new(width: 4, height: 3, background: white) }

    it 'fills the entire canvas with the given color' do
      canvas.clear(red)
      4.times do |x|
        3.times { |y| expect(canvas.get_pixel(x, y)).to eq(red) }
      end
    end

    it 'defaults to white' do
      canvas.clear(black)
      canvas.clear
      expect(canvas.get_pixel(0, 0)).to eq(white)
    end

    it 'returns self for chaining' do
      expect(canvas.clear(red)).to equal(canvas)
    end
  end

  describe '#rgba_bytes' do
    subject(:canvas) { described_class.new(width: 2, height: 2, background: red) }

    it 'returns a String' do
      expect(canvas.rgba_bytes).to be_a(String)
    end

    it 'returns a frozen String' do
      expect(canvas.rgba_bytes).to be_frozen
    end

    it 'returns ASCII-8BIT encoding' do
      expect(canvas.rgba_bytes.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'has correct byte length (width * height * 4)' do
      expect(canvas.rgba_bytes.bytesize).to eq(2 * 2 * 4)
    end

    it 'reflects pixel contents' do
      canvas.set_pixel(0, 0, black)
      bytes = canvas.rgba_bytes
      expect(bytes.getbyte(0)).to eq(0)   # R
      expect(bytes.getbyte(1)).to eq(0)   # G
      expect(bytes.getbyte(2)).to eq(0)   # B
      expect(bytes.getbyte(3)).to eq(255) # A
    end
  end

  describe '#blit with alpha compositing' do
    subject(:canvas) { described_class.new(width: 10, height: 10, background: white) }

    it 'copies opaque pixels directly' do
      src = described_class.new(width: 2, height: 2, background: red)
      canvas.blit(src, x: 0, y: 0)
      expect(canvas.get_pixel(0, 0)).to eq(red)
      expect(canvas.get_pixel(1, 1)).to eq(red)
    end

    it 'skips transparent pixels' do
      src = described_class.new(width: 2, height: 2, background: transparent)
      canvas.blit(src, x: 0, y: 0)
      expect(canvas.get_pixel(0, 0)).to eq(white)
    end

    it 'blends semi-transparent pixels' do
      semi_red = ChromaWave::Color.new(r: 255, g: 0, b: 0, a: 128)
      src = described_class.new(width: 1, height: 1, background: semi_red)
      canvas.blit(src, x: 0, y: 0)
      result = canvas.get_pixel(0, 0)
      # semi_red over white → pinkish
      expect(result.r).to be > 127
      expect(result.g).to be < 128
      expect(result.b).to be < 128
      expect(result.a).to eq(255)
    end

    it 'clips at destination boundary' do
      src = described_class.new(width: 5, height: 5, background: red)
      canvas.blit(src, x: 8, y: 8)
      expect(canvas.get_pixel(8, 8)).to eq(red)
      expect(canvas.get_pixel(9, 9)).to eq(red)
    end

    it 'clips with negative offset' do
      src = described_class.new(width: 5, height: 5, background: red)
      canvas.blit(src, x: -3, y: -3)
      expect(canvas.get_pixel(0, 0)).to eq(red)
      expect(canvas.get_pixel(1, 1)).to eq(red)
    end

    it 'returns self for chaining' do
      src = described_class.new(width: 1, height: 1, background: red)
      expect(canvas.blit(src, x: 0, y: 0)).to equal(canvas)
    end
  end

  describe '#load_rgba_bytes' do
    subject(:canvas) { described_class.new(width: 10, height: 10, background: white) }

    it 'loads raw RGBA data into a region' do
      # 2x2 red pixels
      data = (red.to_rgba_bytes * 4)
      canvas.load_rgba_bytes(data, width: 2, height: 2, x: 3, y: 4)
      expect(canvas.get_pixel(3, 4)).to eq(red)
      expect(canvas.get_pixel(4, 5)).to eq(red)
      expect(canvas.get_pixel(2, 4)).to eq(white) # not overwritten
    end

    it 'clips at destination boundary' do
      data = (black.to_rgba_bytes * 9)
      canvas.load_rgba_bytes(data, width: 3, height: 3, x: 9, y: 9)
      expect(canvas.get_pixel(9, 9)).to eq(black)
    end

    it 'returns self for chaining' do
      data = red.to_rgba_bytes
      expect(canvas.load_rgba_bytes(data, width: 1, height: 1, x: 0, y: 0)).to equal(canvas)
    end
  end

  describe '#layer' do
    subject(:canvas) { described_class.new(width: 20, height: 15) }

    it 'returns a Layer without a block' do
      layer = canvas.layer(x: 5, y: 5, width: 10, height: 5)
      expect(layer).to be_a(ChromaWave::Layer)
    end

    it 'yields the layer and returns self with a block' do
      yielded = nil
      result = canvas.layer(x: 0, y: 0, width: 10, height: 10) { |l| yielded = l }
      expect(yielded).to be_a(ChromaWave::Layer)
      expect(result).to equal(canvas)
    end
  end

  describe 'Surface protocol' do
    subject(:canvas) { described_class.new(width: 10, height: 10) }

    it 'includes Surface' do
      expect(canvas).to be_a(ChromaWave::Surface)
    end

    it 'responds to in_bounds?' do
      expect(canvas.in_bounds?(0, 0)).to be(true)
      expect(canvas.in_bounds?(10, 0)).to be(false)
    end
  end

  describe '#inspect' do
    it 'includes class name and dimensions' do
      canvas = described_class.new(width: 200, height: 100)
      expect(canvas.inspect).to eq('#<ChromaWave::Canvas 200x100>')
    end
  end

  describe '#==' do
    it 'returns true for canvases with identical content' do
      a = described_class.new(width: 5, height: 5, background: red)
      b = described_class.new(width: 5, height: 5, background: red)
      expect(a).to eq(b)
    end

    it 'returns false for different dimensions' do
      a = described_class.new(width: 5, height: 5)
      b = described_class.new(width: 5, height: 6)
      expect(a).not_to eq(b)
    end

    it 'returns false for different pixel content' do
      a = described_class.new(width: 5, height: 5)
      b = described_class.new(width: 5, height: 5)
      b.set_pixel(0, 0, red)
      expect(a).not_to eq(b)
    end

    it 'returns false for non-Canvas objects' do
      canvas = described_class.new(width: 5, height: 5)
      expect(canvas).not_to eq('not a canvas')
    end
  end

  describe 'memory efficiency' do
    it 'uses a single buffer String (minimal GC objects)' do
      # The key invariant: the buffer is a single String, not an array of pixels
      canvas = described_class.new(width: 100, height: 100)
      bytes = canvas.rgba_bytes
      expect(bytes.bytesize).to eq(100 * 100 * 4)
    end
  end
end
