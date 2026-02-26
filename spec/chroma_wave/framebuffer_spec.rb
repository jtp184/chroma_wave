# frozen_string_literal: true

RSpec.describe ChromaWave::Framebuffer do
  describe '#initialize' do
    context 'with valid arguments' do
      %i[mono gray4 color4 color7].each do |fmt|
        it "creates a framebuffer with format #{fmt}" do
          expect(described_class.new(100, 50, fmt).pixel_format).to eq(fmt)
        end
      end
    end

    context 'with invalid format' do
      it 'raises ArgumentError for an unknown symbol' do
        expect { described_class.new(10, 10, :rgb565) }
          .to raise_error(ArgumentError, /unknown pixel format/)
      end

      it 'raises TypeError for a non-symbol' do
        expect { described_class.new(10, 10, 'mono') }
          .to raise_error(TypeError)
      end
    end

    context 'with invalid dimensions' do
      it 'raises ArgumentError for zero width' do
        expect { described_class.new(0, 10, :mono) }
          .to raise_error(ArgumentError, /width/)
      end

      it 'raises ArgumentError for negative width' do
        expect { described_class.new(-1, 10, :mono) }
          .to raise_error(ArgumentError, /width/)
      end

      it 'raises ArgumentError for zero height' do
        expect { described_class.new(10, 0, :mono) }
          .to raise_error(ArgumentError, /height/)
      end

      it 'raises ArgumentError for negative height' do
        expect { described_class.new(10, -1, :mono) }
          .to raise_error(ArgumentError, /height/)
      end
    end
  end

  describe 'accessors' do
    subject(:fb) { described_class.new(200, 100, :mono) }

    it 'reports correct width' do
      expect(fb.width).to eq(200)
    end

    it 'reports correct height' do
      expect(fb.height).to eq(100)
    end

    it 'reports correct pixel_format' do
      expect(fb.pixel_format).to eq(:mono)
    end
  end

  describe '#buffer_size' do
    context 'with MONO format (1bpp, ceil(width/8) bytes/row)' do
      it 'calculates byte-aligned width' do
        expect(described_class.new(16, 10, :mono).buffer_size).to eq(2 * 10)
      end

      it 'calculates non-byte-aligned width (rounds up)' do
        expect(described_class.new(122, 250, :mono).buffer_size).to eq(16 * 250)
      end

      it 'handles width of 1' do
        expect(described_class.new(1, 1, :mono).buffer_size).to eq(1)
      end
    end

    context 'with GRAY4 format (2bpp, ceil(width/4) bytes/row)' do
      it 'calculates byte-aligned width' do
        expect(described_class.new(8, 10, :gray4).buffer_size).to eq(2 * 10)
      end

      it 'calculates non-byte-aligned width' do
        expect(described_class.new(10, 20, :gray4).buffer_size).to eq(3 * 20)
      end
    end

    context 'with COLOR4 format (4bpp, ceil(width/2) bytes/row)' do
      it 'calculates byte-aligned width' do
        expect(described_class.new(10, 10, :color4).buffer_size).to eq(5 * 10)
      end

      it 'calculates non-byte-aligned width' do
        expect(described_class.new(11, 10, :color4).buffer_size).to eq(6 * 10)
      end
    end

    context 'with COLOR7 format (4bpp, ceil(width/2) bytes/row)' do
      it 'calculates same as COLOR4' do
        expect(described_class.new(15, 5, :color7).buffer_size).to eq(8 * 5)
      end
    end
  end

  describe '#set_pixel / #get_pixel round-trip' do
    context 'with MONO format' do
      subject(:fb) { described_class.new(16, 4, :mono) }

      it 'stores and retrieves BLACK (0)' do
        expect(fb.set_pixel(0, 0, 0).get_pixel(0, 0)).to eq(0)
      end

      it 'stores and retrieves WHITE (1)' do
        expect(fb.clear(0).set_pixel(5, 2, 1).get_pixel(5, 2)).to eq(1)
      end

      it 'defaults to WHITE (1) at origin' do
        expect(fb.get_pixel(0, 0)).to eq(1)
      end

      it 'defaults to WHITE (1) at far corner' do
        expect(fb.get_pixel(15, 3)).to eq(1)
      end

      8.times do |x|
        it "correctly packs bit position #{x} within a byte" do
          expect(fb.clear(0).set_pixel(x, 0, 1).get_pixel(x, 0)).to eq(1)
        end
      end

      it 'handles boundary pixel (0,0)' do
        fb.clear(0)
        expect(fb.set_pixel(0, 0, 1).get_pixel(0, 0)).to eq(1)
      end

      it 'handles boundary pixel (width-1,0)' do
        expect(fb.clear(0).set_pixel(15, 0, 1).get_pixel(15, 0)).to eq(1)
      end

      it 'handles boundary pixel (0,height-1)' do
        expect(fb.clear(0).set_pixel(0, 3, 1).get_pixel(0, 3)).to eq(1)
      end

      it 'handles boundary pixel (width-1,height-1)' do
        expect(fb.clear(0).set_pixel(15, 3, 1).get_pixel(15, 3)).to eq(1)
      end

      it 'does not affect the pixel before' do
        expect(fb.clear(0).set_pixel(3, 0, 1).get_pixel(2, 0)).to eq(0)
      end

      it 'does not affect the pixel after' do
        expect(fb.clear(0).set_pixel(3, 0, 1).get_pixel(4, 0)).to eq(0)
      end
    end

    context 'with GRAY4 format' do
      subject(:fb) { described_class.new(8, 4, :gray4) }

      (0..3).each do |color|
        it "round-trips color value #{color}" do
          expect(fb.set_pixel(0, 0, color).get_pixel(0, 0)).to eq(color)
        end
      end

      4.times do |x|
        it "correctly packs pixel position #{x} within a byte" do
          expect(fb.clear(0).set_pixel(x, 0, x).get_pixel(x, 0)).to eq(x)
        end
      end

      it 'defaults to 0 at origin' do
        expect(fb.get_pixel(0, 0)).to eq(0)
      end

      it 'defaults to 0 at far corner' do
        expect(fb.get_pixel(7, 3)).to eq(0)
      end

      it 'handles boundary pixel (7,3)' do
        expect(fb.set_pixel(7, 3, 3).get_pixel(7, 3)).to eq(3)
      end

      it 'masks to 2-bit range' do
        expect(fb.set_pixel(0, 0, 7).get_pixel(0, 0)).to eq(3)
      end
    end

    context 'with COLOR4 format' do
      subject(:fb) { described_class.new(10, 4, :color4) }

      (0..5).each do |color|
        it "round-trips color value #{color}" do
          expect(fb.set_pixel(color, 0, color).get_pixel(color, 0)).to eq(color)
        end
      end

      it 'packs even X in high nibble' do
        expect(fb.set_pixel(0, 0, 5).get_pixel(0, 0)).to eq(5)
      end

      it 'packs odd X in low nibble' do
        expect(fb.set_pixel(1, 0, 3).get_pixel(1, 0)).to eq(3)
      end

      it 'defaults to 0 at origin' do
        expect(fb.get_pixel(0, 0)).to eq(0)
      end

      it 'defaults to 0 at far corner' do
        expect(fb.get_pixel(9, 3)).to eq(0)
      end

      it 'handles boundary pixel (9,3)' do
        expect(fb.set_pixel(9, 3, 5).get_pixel(9, 3)).to eq(5)
      end

      it 'masks to 4-bit range' do
        expect(fb.set_pixel(0, 0, 0x1F).get_pixel(0, 0)).to eq(0x0F)
      end
    end

    context 'with COLOR7 format' do
      subject(:fb) { described_class.new(10, 4, :color7) }

      (0..6).each do |color|
        it "round-trips color value #{color}" do
          expect(fb.set_pixel(color, 0, color).get_pixel(color, 0)).to eq(color)
        end
      end

      it 'packs even X correctly' do
        expect(fb.set_pixel(0, 0, 6).get_pixel(0, 0)).to eq(6)
      end

      it 'packs odd X correctly' do
        expect(fb.set_pixel(1, 0, 4).get_pixel(1, 0)).to eq(4)
      end

      it 'defaults to 0 at origin' do
        expect(fb.get_pixel(0, 0)).to eq(0)
      end

      it 'defaults to 0 at far corner' do
        expect(fb.get_pixel(9, 3)).to eq(0)
      end
    end
  end

  describe 'non-byte-aligned width edge case' do
    context 'with MONO width=122 (ceil(122/8)=16 bytes/row)' do
      subject(:fb) { described_class.new(122, 10, :mono) }

      it 'has correct buffer_size' do
        expect(fb.buffer_size).to eq(16 * 10)
      end

      it 'packs pixel at x=120 correctly' do
        expect(fb.clear(0).set_pixel(120, 0, 1).get_pixel(120, 0)).to eq(1)
      end

      it 'packs pixel at x=121 correctly' do
        expect(fb.clear(0).set_pixel(121, 0, 1).get_pixel(121, 0)).to eq(1)
      end

      it 'does not corrupt adjacent pixel when setting x=121' do
        expect(fb.clear(0).set_pixel(121, 0, 1).get_pixel(120, 0)).to eq(0)
      end
    end
  end

  describe 'out-of-bounds behavior' do
    subject(:fb) { described_class.new(10, 10, :mono) }

    context 'with #set_pixel' do
      it 'is a silent no-op for negative x' do
        expect { fb.set_pixel(-1, 0, 1) }.not_to raise_error
      end

      it 'is a silent no-op for negative y' do
        expect { fb.set_pixel(0, -1, 1) }.not_to raise_error
      end

      it 'is a silent no-op for x >= width' do
        expect { fb.set_pixel(10, 0, 1) }.not_to raise_error
      end

      it 'is a silent no-op for y >= height' do
        expect { fb.set_pixel(0, 10, 1) }.not_to raise_error
      end

      it 'returns self for out-of-bounds coordinates' do
        expect(fb.set_pixel(-1, 0, 1)).to equal(fb)
      end

      it 'returns self for in-bounds coordinates' do
        expect(fb.set_pixel(0, 0, 1)).to equal(fb)
      end
    end

    context 'with #get_pixel' do
      it 'returns nil for negative x' do
        expect(fb.get_pixel(-1, 0)).to be_nil
      end

      it 'returns nil for negative y' do
        expect(fb.get_pixel(0, -1)).to be_nil
      end

      it 'returns nil for x >= width' do
        expect(fb.get_pixel(10, 0)).to be_nil
      end

      it 'returns nil for y >= height' do
        expect(fb.get_pixel(0, 10)).to be_nil
      end
    end
  end

  describe '#clear' do
    it 'fills MONO with BLACK (0x00) when color is 0' do
      fb = described_class.new(8, 2, :mono)
      expect(fb.clear(0).bytes.bytes).to all(eq(0x00))
    end

    it 'fills MONO with WHITE (0xFF) when color is 1' do
      fb = described_class.new(8, 2, :mono)
      expect(fb.clear(0).clear(1).bytes.bytes).to all(eq(0xFF))
    end

    it 'fills GRAY4 with correct byte pattern for color 2' do
      fb = described_class.new(4, 2, :gray4)
      expect(fb.clear(2).bytes.bytes).to all(eq(0xAA))
    end

    it 'fills COLOR7 with correct byte pattern for color 5' do
      fb = described_class.new(4, 2, :color7)
      expect(fb.clear(5).bytes.bytes).to all(eq(0x55))
    end

    it 'makes all pixels read back the cleared value (GRAY4)' do
      fb = described_class.new(4, 2, :gray4)
      fb.clear(3)
      pixels = (0...4).flat_map { |x| (0...2).map { |y| fb.get_pixel(x, y) } }
      expect(pixels).to all(eq(3))
    end

    it 'returns self for chaining' do
      fb = described_class.new(8, 2, :mono)
      expect(fb.clear(0)).to equal(fb)
    end
  end

  describe '#bytes' do
    subject(:fb) { described_class.new(8, 2, :mono) }

    it 'returns a String' do
      expect(fb.bytes).to be_a(String)
    end

    it 'returns a frozen String' do
      expect(fb.bytes).to be_frozen
    end

    it 'returns a String with ASCII-8BIT encoding' do
      expect(fb.bytes.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'returns a String whose length equals buffer_size' do
      expect(fb.bytes.length).to eq(fb.buffer_size)
    end

    it 'reflects clear operations' do
      expect(fb.clear(0).bytes.bytes).to all(eq(0x00))
    end

    it 'reflects set_pixel operations' do
      expect(fb.clear(0).set_pixel(0, 0, 1).bytes.getbyte(0)).to eq(0x80)
    end
  end

  describe 'GC stress test' do
    it 'handles creating and discarding many framebuffers' do
      expect do
        1000.times { described_class.new(64, 64, :mono) }
        GC.start
      end.not_to raise_error
    end
  end
end
