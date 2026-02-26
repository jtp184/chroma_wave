# frozen_string_literal: true

RSpec.describe ChromaWave::Color do
  describe '.new' do
    it 'creates a color with RGBA channels' do
      color = described_class.new(r: 10, g: 20, b: 30, a: 40)
      expect([color.r, color.g, color.b, color.a]).to eq([10, 20, 30, 40])
    end

    it 'defaults alpha to 255' do
      color = described_class.new(r: 0, g: 0, b: 0)
      expect(color.a).to eq(255)
    end

    it 'accepts zero for all channels' do
      expect(described_class.new(r: 0, g: 0, b: 0, a: 0)).to be_a(described_class)
    end

    it 'accepts 255 for all channels' do
      expect(described_class.new(r: 255, g: 255, b: 255, a: 255)).to be_a(described_class)
    end

    context 'with invalid channels' do
      it 'raises ArgumentError for negative r' do
        expect { described_class.new(r: -1, g: 0, b: 0) }
          .to raise_error(ArgumentError, /r must be 0\.\.255/)
      end

      it 'raises ArgumentError for r > 255' do
        expect { described_class.new(r: 256, g: 0, b: 0) }
          .to raise_error(ArgumentError, /r must be 0\.\.255/)
      end

      it 'raises ArgumentError for negative g' do
        expect { described_class.new(r: 0, g: -1, b: 0) }
          .to raise_error(ArgumentError, /g must be 0\.\.255/)
      end

      it 'raises ArgumentError for b > 255' do
        expect { described_class.new(r: 0, g: 0, b: 256) }
          .to raise_error(ArgumentError, /b must be 0\.\.255/)
      end

      it 'raises ArgumentError for negative a' do
        expect { described_class.new(r: 0, g: 0, b: 0, a: -1) }
          .to raise_error(ArgumentError, /a must be 0\.\.255/)
      end

      it 'raises TypeError for a float channel' do
        expect { described_class.new(r: 1.5, g: 0, b: 0) }
          .to raise_error(TypeError, /r must be an Integer/)
      end

      it 'raises TypeError for a string channel' do
        expect { described_class.new(r: 0, g: 'ff', b: 0) }
          .to raise_error(TypeError, /g must be an Integer/)
      end
    end
  end

  describe 'immutability' do
    it 'is frozen' do
      expect(described_class.new(r: 0, g: 0, b: 0)).to be_frozen
    end
  end

  describe 'structural equality' do
    it 'is equal for same channels' do
      a = described_class.new(r: 10, g: 20, b: 30, a: 40)
      b = described_class.new(r: 10, g: 20, b: 30, a: 40)
      expect(a).to eq(b)
    end

    it 'is not equal for different channels' do
      a = described_class.new(r: 10, g: 20, b: 30)
      b = described_class.new(r: 10, g: 20, b: 31)
      expect(a).not_to eq(b)
    end
  end

  describe '.hex' do
    it 'parses 6-digit hex' do
      expect(described_class.hex('#FF8000')).to eq(described_class.new(r: 255, g: 128, b: 0))
    end

    it 'parses 3-digit shorthand' do
      expect(described_class.hex('#F80')).to eq(described_class.new(r: 255, g: 136, b: 0))
    end

    it 'is case insensitive' do
      expect(described_class.hex('#ff8000')).to eq(described_class.hex('#FF8000'))
    end

    it 'parses #000 as black' do
      expect(described_class.hex('#000')).to eq(described_class::BLACK)
    end

    it 'parses #FFF as white' do
      expect(described_class.hex('#FFF')).to eq(described_class::WHITE)
    end

    it 'returns opaque colors' do
      expect(described_class.hex('#FF0000').a).to eq(255)
    end

    it 'raises ArgumentError for missing hash' do
      expect { described_class.hex('FF0000') }.to raise_error(ArgumentError, /invalid hex color/)
    end

    it 'raises ArgumentError for wrong length' do
      expect { described_class.hex('#FFFF') }.to raise_error(ArgumentError, /invalid hex color/)
    end

    it 'raises ArgumentError for invalid characters' do
      expect { described_class.hex('#GGGGGG') }.to raise_error(ArgumentError, /invalid hex color/)
    end
  end

  describe '#opaque? / #transparent?' do
    it 'is opaque when alpha is 255' do
      expect(described_class.new(r: 0, g: 0, b: 0)).to be_opaque
    end

    it 'is not opaque when alpha is 0' do
      expect(described_class.new(r: 0, g: 0, b: 0, a: 0)).not_to be_opaque
    end

    it 'is transparent when alpha is 0' do
      expect(described_class.new(r: 0, g: 0, b: 0, a: 0)).to be_transparent
    end

    it 'is not transparent when alpha is 255' do
      expect(described_class.new(r: 0, g: 0, b: 0)).not_to be_transparent
    end

    it 'is neither opaque nor transparent at alpha 128' do
      color = described_class.new(r: 0, g: 0, b: 0, a: 128)
      expect(color).not_to be_opaque
      expect(color).not_to be_transparent
    end
  end

  describe '#to_rgba_bytes / .from_rgba_bytes round-trip' do
    it 'round-trips an opaque color' do
      color = described_class.new(r: 255, g: 128, b: 0)
      expect(described_class.from_rgba_bytes(color.to_rgba_bytes)).to eq(color)
    end

    it 'round-trips a transparent color' do
      color = described_class.new(r: 100, g: 200, b: 50, a: 0)
      expect(described_class.from_rgba_bytes(color.to_rgba_bytes)).to eq(color)
    end

    it 'round-trips all zeros' do
      color = described_class.new(r: 0, g: 0, b: 0, a: 0)
      expect(described_class.from_rgba_bytes(color.to_rgba_bytes)).to eq(color)
    end

    it 'round-trips all 255s' do
      color = described_class.new(r: 255, g: 255, b: 255, a: 255)
      expect(described_class.from_rgba_bytes(color.to_rgba_bytes)).to eq(color)
    end

    it 'raises ArgumentError for wrong byte count' do
      expect { described_class.from_rgba_bytes('abc') }.to raise_error(ArgumentError, /expected 4 bytes/)
    end
  end

  describe '#over (alpha compositing)' do
    let(:white) { described_class::WHITE }
    let(:black) { described_class::BLACK }

    it 'returns self when opaque (fast path)' do
      red = described_class::RED
      expect(red.over(white)).to equal(red)
    end

    it 'returns background when transparent (fast path)' do
      transparent = described_class::TRANSPARENT
      expect(transparent.over(white)).to equal(white)
    end

    it 'composites semi-transparent red over white' do
      semi_red = described_class.new(r: 255, g: 0, b: 0, a: 128)
      result = semi_red.over(white)
      expect(result.a).to eq(255)
      expect(result.r).to be > 128
      expect(result.g).to be > 0
      expect(result.b).to be > 0
    end

    it 'produces an opaque result from semi-transparent compositing' do
      semi = described_class.new(r: 100, g: 100, b: 100, a: 100)
      expect(semi.over(white).a).to eq(255)
    end

    it 'composites correctly at 50% alpha' do
      # 50% black over white should produce ~128 gray
      half_black = described_class.new(r: 0, g: 0, b: 0, a: 128)
      result = half_black.over(white)
      # 0 * (128/255) + 255 * (1 - 128/255) ≈ 127
      expect(result.r).to be_between(126, 128)
      expect(result.g).to be_between(126, 128)
      expect(result.b).to be_between(126, 128)
    end
  end

  describe 'named constants' do
    it 'defines BLACK as (0, 0, 0, 255)' do
      expect(described_class::BLACK).to eq(described_class.new(r: 0, g: 0, b: 0))
    end

    it 'defines WHITE as (255, 255, 255, 255)' do
      expect(described_class::WHITE).to eq(described_class.new(r: 255, g: 255, b: 255))
    end

    it 'defines RED as (255, 0, 0, 255)' do
      expect(described_class::RED).to eq(described_class.new(r: 255, g: 0, b: 0))
    end

    it 'defines YELLOW as (255, 255, 0, 255)' do
      expect(described_class::YELLOW).to eq(described_class.new(r: 255, g: 255, b: 0))
    end

    it 'defines GREEN as (0, 255, 0, 255)' do
      expect(described_class::GREEN).to eq(described_class.new(r: 0, g: 255, b: 0))
    end

    it 'defines BLUE as (0, 0, 255, 255)' do
      expect(described_class::BLUE).to eq(described_class.new(r: 0, g: 0, b: 255))
    end

    it 'defines ORANGE as (255, 128, 0, 255)' do
      expect(described_class::ORANGE).to eq(described_class.new(r: 255, g: 128, b: 0))
    end

    it 'defines DARK_GRAY as (85, 85, 85, 255)' do
      expect(described_class::DARK_GRAY).to eq(described_class.new(r: 85, g: 85, b: 85))
    end

    it 'defines LIGHT_GRAY as (170, 170, 170, 255)' do
      expect(described_class::LIGHT_GRAY).to eq(described_class.new(r: 170, g: 170, b: 170))
    end

    it 'defines TRANSPARENT as (0, 0, 0, 0)' do
      expect(described_class::TRANSPARENT).to eq(described_class.new(r: 0, g: 0, b: 0, a: 0))
    end
  end

  describe 'NAME_MAP' do
    it 'contains 10 entries' do
      expect(described_class::NAME_MAP.size).to eq(10)
    end

    it 'is frozen' do
      expect(described_class::NAME_MAP).to be_frozen
    end

    it 'maps :black to BLACK' do
      expect(described_class::NAME_MAP[:black]).to equal(described_class::BLACK)
    end

    it 'maps :white to WHITE' do
      expect(described_class::NAME_MAP[:white]).to equal(described_class::WHITE)
    end
  end

  describe '.from_name' do
    it 'looks up :red' do
      expect(described_class.from_name(:red)).to equal(described_class::RED)
    end

    it 'raises KeyError for unknown name' do
      expect { described_class.from_name(:magenta) }.to raise_error(KeyError)
    end
  end
end
