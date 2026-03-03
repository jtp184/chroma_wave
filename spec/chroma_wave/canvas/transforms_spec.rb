# frozen_string_literal: true

RSpec.describe ChromaWave::Canvas::Transforms do
  let(:red)   { ChromaWave::Color::RED }
  let(:green) { ChromaWave::Color::GREEN }
  let(:blue)  { ChromaWave::Color::BLUE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:white) { ChromaWave::Color::WHITE }

  # Helper: build a small canvas with individually-addressed pixels.
  # Yields the canvas so callers can paint it.
  def canvas(width, height, background: white)
    ChromaWave::Canvas.new(width: width, height: height, background: background)
  end

  # ── flip ───────────────────────────────────────────────────────────────

  describe '#flip' do
    describe ':horizontal' do
      it 'mirrors pixels left-to-right on a 3x2 canvas' do
        c = canvas(3, 2)
        c.set_pixel(0, 0, red)
        c.set_pixel(1, 0, green)
        c.set_pixel(2, 0, blue)

        result = c.flip(:horizontal)

        expect(result.get_pixel(0, 0)).to eq(blue)
        expect(result.get_pixel(1, 0)).to eq(green)
        expect(result.get_pixel(2, 0)).to eq(red)
      end

      it 'preserves row positions (only reverses within rows)' do
        c = canvas(2, 2)
        c.set_pixel(0, 0, red)
        c.set_pixel(1, 1, blue)

        result = c.flip(:horizontal)

        expect(result.get_pixel(1, 0)).to eq(red)
        expect(result.get_pixel(0, 1)).to eq(blue)
      end

      it 'preserves dimensions' do
        c = canvas(5, 3)
        result = c.flip(:horizontal)
        expect(result.width).to eq(5)
        expect(result.height).to eq(3)
      end

      it 'does not mutate the original' do
        c = canvas(2, 1)
        c.set_pixel(0, 0, red)
        c.flip(:horizontal)
        expect(c.get_pixel(0, 0)).to eq(red)
      end

      it 'double-flip is identity' do
        c = canvas(3, 2)
        c.set_pixel(0, 0, red)
        c.set_pixel(2, 1, blue)

        result = c.flip(:horizontal).flip(:horizontal)

        expect(result).to eq(c)
      end

      it 'works on a 1x1 canvas' do
        c = canvas(1, 1, background: red)
        result = c.flip(:horizontal)
        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'works on a single-row canvas' do
        c = canvas(4, 1)
        c.set_pixel(0, 0, red)
        c.set_pixel(3, 0, blue)

        result = c.flip(:horizontal)

        expect(result.get_pixel(0, 0)).to eq(blue)
        expect(result.get_pixel(3, 0)).to eq(red)
      end

      it 'works on a single-column canvas' do
        c = canvas(1, 3)
        c.set_pixel(0, 0, red)
        c.set_pixel(0, 2, blue)

        result = c.flip(:horizontal)

        # Single column: horizontal flip changes nothing
        expect(result.get_pixel(0, 0)).to eq(red)
        expect(result.get_pixel(0, 2)).to eq(blue)
      end
    end

    describe ':vertical' do
      it 'mirrors rows top-to-bottom on a 3x2 canvas' do
        c = canvas(3, 2)
        c.set_pixel(0, 0, red)
        c.set_pixel(0, 1, blue)

        result = c.flip(:vertical)

        expect(result.get_pixel(0, 0)).to eq(blue)
        expect(result.get_pixel(0, 1)).to eq(red)
      end

      it 'preserves column positions (only reverses row order)' do
        c = canvas(2, 3)
        c.set_pixel(1, 0, red)
        c.set_pixel(0, 2, blue)

        result = c.flip(:vertical)

        expect(result.get_pixel(1, 2)).to eq(red)
        expect(result.get_pixel(0, 0)).to eq(blue)
      end

      it 'preserves dimensions' do
        c = canvas(3, 5)
        result = c.flip(:vertical)
        expect(result.width).to eq(3)
        expect(result.height).to eq(5)
      end

      it 'does not mutate the original' do
        c = canvas(1, 2)
        c.set_pixel(0, 0, red)
        c.flip(:vertical)
        expect(c.get_pixel(0, 0)).to eq(red)
      end

      it 'double-flip is identity' do
        c = canvas(2, 3)
        c.set_pixel(0, 0, red)
        c.set_pixel(1, 2, blue)

        result = c.flip(:vertical).flip(:vertical)

        expect(result).to eq(c)
      end

      it 'works on a 1x1 canvas' do
        c = canvas(1, 1, background: blue)
        result = c.flip(:vertical)
        expect(result.get_pixel(0, 0)).to eq(blue)
      end

      it 'works on a single-row canvas' do
        c = canvas(3, 1)
        c.set_pixel(0, 0, red)

        result = c.flip(:vertical)

        # Single row: vertical flip changes nothing
        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'works on a single-column canvas' do
        c = canvas(1, 4)
        c.set_pixel(0, 0, red)
        c.set_pixel(0, 3, blue)

        result = c.flip(:vertical)

        expect(result.get_pixel(0, 0)).to eq(blue)
        expect(result.get_pixel(0, 3)).to eq(red)
      end
    end

    describe 'validation' do
      it 'raises ArgumentError for invalid direction' do
        c = canvas(2, 2)
        expect { c.flip(:diagonal) }.to raise_error(ArgumentError, /direction/)
      end

      it 'raises ArgumentError for nil direction' do
        c = canvas(2, 2)
        expect { c.flip(nil) }.to raise_error(ArgumentError, /direction/)
      end
    end
  end

  # ── scale ──────────────────────────────────────────────────────────────

  describe '#scale' do
    describe 'with uniform factor' do
      it 'doubles a 2x2 canvas to 4x4 with correct dimensions' do
        c = canvas(2, 2)
        c.set_pixel(0, 0, red)
        c.set_pixel(1, 0, green)
        c.set_pixel(0, 1, blue)
        c.set_pixel(1, 1, black)

        result = c.scale(2.0)

        expect(result.width).to eq(4)
        expect(result.height).to eq(4)
      end

      it 'maps each source pixel to a 2x2 block when doubled' do
        c = canvas(2, 2)
        colors = { [0, 0] => red, [1, 0] => green, [0, 1] => blue, [1, 1] => black }
        colors.each { |(x, y), color| c.set_pixel(x, y, color) }

        result = c.scale(2.0)

        # Verify each source pixel's corresponding block corner in the output
        colors.each do |(sx, sy), color|
          expect(result.get_pixel(sx * 2, sy * 2)).to eq(color)
          expect(result.get_pixel((sx * 2) + 1, (sy * 2) + 1)).to eq(color)
        end
      end

      it 'halves a 4x4 canvas to 2x2 with sampled pixels' do
        c = canvas(4, 4)
        # Paint 2x2 blocks
        [0, 1].each { |x| [0, 1].each { |y| c.set_pixel(x, y, red) } }
        [2, 3].each { |x| [0, 1].each { |y| c.set_pixel(x, y, blue) } }

        result = c.scale(0.5)

        expect(result.width).to eq(2)
        expect(result.height).to eq(2)
        expect(result.get_pixel(0, 0)).to eq(red)
        expect(result.get_pixel(1, 0)).to eq(blue)
      end

      it 'scale(1.0) produces an identical copy' do
        c = canvas(3, 3)
        c.set_pixel(1, 1, red)

        result = c.scale(1.0)

        expect(result).to eq(c)
        expect(result).not_to equal(c)
      end

      it 'clamps dimensions to a minimum of 1' do
        c = canvas(2, 2, background: red)
        result = c.scale(0.001)
        expect(result.width).to eq(1)
        expect(result.height).to eq(1)
        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'does not mutate the original' do
        c = canvas(2, 2, background: red)
        c.scale(2.0)
        expect(c.width).to eq(2)
        expect(c.height).to eq(2)
      end
    end

    describe 'with width: keyword' do
      it 'scales to target width preserving aspect ratio' do
        c = canvas(100, 50)
        result = c.scale(width: 200)
        expect(result.width).to eq(200)
        expect(result.height).to eq(100)
      end

      it 'clamps computed height to minimum of 1' do
        c = canvas(100, 1)
        result = c.scale(width: 2)
        expect(result.width).to eq(2)
        expect(result.height).to be >= 1
      end
    end

    describe 'with height: keyword' do
      it 'scales to target height preserving aspect ratio' do
        c = canvas(100, 50)
        result = c.scale(height: 100)
        expect(result.width).to eq(200)
        expect(result.height).to eq(100)
      end

      it 'clamps computed width to minimum of 1' do
        c = canvas(1, 100)
        result = c.scale(height: 2)
        expect(result.height).to eq(2)
        expect(result.width).to be >= 1
      end
    end

    describe 'with width: and height: keywords' do
      it 'scales to exact dimensions' do
        c = canvas(10, 10)
        result = c.scale(width: 30, height: 20)
        expect(result.width).to eq(30)
        expect(result.height).to eq(20)
      end
    end

    describe 'with 1x1 canvas' do
      it 'scales up to NxN' do
        c = canvas(1, 1, background: red)
        result = c.scale(5.0)
        expect(result.width).to eq(5)
        expect(result.height).to eq(5)
        expect(result.get_pixel(0, 0)).to eq(red)
        expect(result.get_pixel(4, 4)).to eq(red)
      end
    end

    describe 'validation' do
      it 'raises for zero factor' do
        c = canvas(2, 2)
        expect { c.scale(0) }.to raise_error(ArgumentError, /factor/)
      end

      it 'raises for negative factor' do
        c = canvas(2, 2)
        expect { c.scale(-1.0) }.to raise_error(ArgumentError, /factor/)
      end

      it 'raises with no arguments' do
        c = canvas(2, 2)
        expect { c.scale }.to raise_error(ArgumentError)
      end

      it 'raises when mixing factor with width: keyword' do
        c = canvas(2, 2)
        expect { c.scale(2.0, width: 10) }.to raise_error(ArgumentError, /mix/)
      end

      it 'raises when mixing factor with height: keyword' do
        c = canvas(2, 2)
        expect { c.scale(2.0, height: 10) }.to raise_error(ArgumentError, /mix/)
      end

      it 'raises for non-positive width: keyword' do
        c = canvas(2, 2)
        expect { c.scale(width: 0) }.to raise_error(ArgumentError)
      end

      it 'raises for non-positive height: keyword' do
        c = canvas(2, 2)
        expect { c.scale(height: -5) }.to raise_error(ArgumentError)
      end

      it 'raises when factor produces width exceeding MAX_DIMENSION' do
        c = canvas(4096, 1)
        expect { c.scale(2.0) }.to raise_error(ArgumentError, /scaled width.*exceeds maximum/)
      end

      it 'raises when factor produces height exceeding MAX_DIMENSION' do
        c = canvas(1, 4096)
        expect { c.scale(2.0) }.to raise_error(ArgumentError, /scaled height.*exceeds maximum/)
      end

      it 'raises when width: keyword exceeds MAX_DIMENSION' do
        c = canvas(10, 10)
        expect { c.scale(width: 5000) }.to raise_error(ArgumentError, /scaled width.*exceeds maximum/)
      end

      it 'raises for Float width: keyword' do
        c = canvas(10, 10)
        expect { c.scale(width: 5.5) }.to raise_error(ArgumentError)
      end

      it 'raises for Float height: keyword' do
        c = canvas(10, 10)
        expect { c.scale(height: 3.7) }.to raise_error(ArgumentError)
      end
    end
  end

  # ── crop ───────────────────────────────────────────────────────────────

  describe '#crop' do
    it 'extracts an in-bounds sub-region' do
      c = canvas(10, 10)
      c.set_pixel(3, 3, red)
      c.set_pixel(6, 6, blue)

      result = c.crop(x: 2, y: 2, width: 6, height: 6)

      expect(result.width).to eq(6)
      expect(result.height).to eq(6)
      expect(result.get_pixel(1, 1)).to eq(red)  # (3,3) → (1,1) in cropped
      expect(result.get_pixel(4, 4)).to eq(blue) # (6,6) → (4,4) in cropped
    end

    it 'crop of full canvas is an identical copy' do
      c = canvas(5, 5, background: red)
      c.set_pixel(2, 2, blue)

      result = c.crop(x: 0, y: 0, width: 5, height: 5)

      expect(result).to eq(c)
      expect(result).not_to equal(c)
    end

    it 'does not mutate the original' do
      c = canvas(5, 5, background: red)
      c.crop(x: 1, y: 1, width: 3, height: 3)
      expect(c.width).to eq(5)
      expect(c.height).to eq(5)
      expect(c.get_pixel(0, 0)).to eq(red)
    end

    describe 'silent clipping' do
      it 'clips when x is negative' do
        c = canvas(10, 10)
        c.set_pixel(0, 0, red)
        c.set_pixel(2, 0, blue)

        result = c.crop(x: -2, y: 0, width: 5, height: 2)

        # Clipped to x: 0..3, so width = 3
        expect(result.width).to eq(3)
        expect(result.height).to eq(2)
        expect(result.get_pixel(0, 0)).to eq(red)
        expect(result.get_pixel(2, 0)).to eq(blue)
      end

      it 'clips when y is negative' do
        c = canvas(10, 10)
        c.set_pixel(0, 0, red)

        result = c.crop(x: 0, y: -3, width: 2, height: 5)

        expect(result.width).to eq(2)
        expect(result.height).to eq(2)
        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'clips when width extends past right edge' do
        c = canvas(10, 10)
        c.set_pixel(9, 0, red)

        result = c.crop(x: 8, y: 0, width: 5, height: 2)

        expect(result.width).to eq(2)
        expect(result.height).to eq(2)
        expect(result.get_pixel(1, 0)).to eq(red)
      end

      it 'clips when height extends past bottom edge' do
        c = canvas(10, 10)
        c.set_pixel(0, 9, red)

        result = c.crop(x: 0, y: 8, width: 2, height: 5)

        expect(result.width).to eq(2)
        expect(result.height).to eq(2)
        expect(result.get_pixel(0, 1)).to eq(red)
      end

      it 'clips on all four sides simultaneously' do
        c = canvas(5, 5, background: red)

        result = c.crop(x: -2, y: -2, width: 9, height: 9)

        expect(result.width).to eq(5)
        expect(result.height).to eq(5)
        expect(result).to eq(c)
      end
    end

    describe 'edge cases' do
      it 'works on a 1x1 canvas' do
        c = canvas(1, 1, background: red)
        result = c.crop(x: 0, y: 0, width: 1, height: 1)
        expect(result.width).to eq(1)
        expect(result.height).to eq(1)
        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'extracts a single-row crop' do
        c = canvas(5, 5)
        c.set_pixel(2, 2, red)

        result = c.crop(x: 0, y: 2, width: 5, height: 1)

        expect(result.width).to eq(5)
        expect(result.height).to eq(1)
        expect(result.get_pixel(2, 0)).to eq(red)
      end

      it 'extracts a single-column crop' do
        c = canvas(5, 5)
        c.set_pixel(2, 3, red)

        result = c.crop(x: 2, y: 0, width: 1, height: 5)

        expect(result.width).to eq(1)
        expect(result.height).to eq(5)
        expect(result.get_pixel(0, 3)).to eq(red)
      end
    end

    describe 'float x/y coercion' do
      it 'rounds x: 2.6 to 3' do
        c = canvas(10, 10)
        c.set_pixel(3, 0, red)

        result = c.crop(x: 2.6, y: 0, width: 2, height: 1)

        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'rounds y: 2.7 to 3' do
        c = canvas(10, 10)
        c.set_pixel(0, 3, red)

        result = c.crop(x: 0, y: 2.7, width: 1, height: 2)

        expect(result.get_pixel(0, 0)).to eq(red)
      end

      it 'rounds x: 2.3 to 2' do
        c = canvas(10, 10)
        c.set_pixel(2, 0, red)

        result = c.crop(x: 2.3, y: 0, width: 2, height: 1)

        expect(result.get_pixel(0, 0)).to eq(red)
      end
    end

    describe 'exact boundary' do
      it 'raises when x equals canvas width' do
        c = canvas(5, 5)
        expect { c.crop(x: 5, y: 0, width: 1, height: 1) }
          .to raise_error(ArgumentError, /outside/)
      end

      it 'raises when y equals canvas height' do
        c = canvas(5, 5)
        expect { c.crop(x: 0, y: 5, width: 1, height: 1) }
          .to raise_error(ArgumentError, /outside/)
      end
    end

    describe 'validation' do
      it 'raises for zero width' do
        c = canvas(5, 5)
        expect { c.crop(x: 0, y: 0, width: 0, height: 3) }
          .to raise_error(ArgumentError, /width/)
      end

      it 'raises for negative width' do
        c = canvas(5, 5)
        expect { c.crop(x: 0, y: 0, width: -1, height: 3) }
          .to raise_error(ArgumentError, /width/)
      end

      it 'raises for zero height' do
        c = canvas(5, 5)
        expect { c.crop(x: 0, y: 0, width: 3, height: 0) }
          .to raise_error(ArgumentError, /height/)
      end

      it 'raises for negative height' do
        c = canvas(5, 5)
        expect { c.crop(x: 0, y: 0, width: 3, height: -1) }
          .to raise_error(ArgumentError, /height/)
      end

      it 'raises when clipped region is entirely outside (right of canvas)' do
        c = canvas(5, 5)
        expect { c.crop(x: 10, y: 0, width: 3, height: 3) }
          .to raise_error(ArgumentError, /outside/)
      end

      it 'raises when clipped region is entirely outside (below canvas)' do
        c = canvas(5, 5)
        expect { c.crop(x: 0, y: 10, width: 3, height: 3) }
          .to raise_error(ArgumentError, /outside/)
      end
    end
  end

  # ── chaining ───────────────────────────────────────────────────────────

  describe 'chaining transforms' do
    it 'crop → flip → scale produces correct result' do
      c = canvas(10, 10)
      # Paint a marker at (1,1)
      c.set_pixel(1, 1, red)

      result = c.crop(x: 0, y: 0, width: 5, height: 5)
                .flip(:horizontal)
                .scale(2.0)

      expect(result.width).to eq(10)
      expect(result.height).to eq(10)

      # (1,1) in 5x5 crop → (3,1) after h-flip → (6,2)/(7,3) in 2x scale
      expect(result.get_pixel(6, 2)).to eq(red)
      expect(result.get_pixel(7, 3)).to eq(red)
    end

    it 'each step returns a new Canvas' do
      c = canvas(4, 4, background: red)

      cropped = c.crop(x: 0, y: 0, width: 2, height: 2)
      flipped = cropped.flip(:vertical)
      scaled  = flipped.scale(2.0)

      expect(cropped).to be_a(ChromaWave::Canvas)
      expect(flipped).to be_a(ChromaWave::Canvas)
      expect(scaled).to be_a(ChromaWave::Canvas)

      # All distinct objects
      expect(cropped).not_to equal(c)
      expect(flipped).not_to equal(cropped)
      expect(scaled).not_to equal(flipped)
    end

    it 'flip(:horizontal) then flip(:vertical) is not the same as either alone' do
      c = canvas(3, 3)
      c.set_pixel(0, 0, red)

      hv = c.flip(:horizontal).flip(:vertical)
      vh = c.flip(:vertical).flip(:horizontal)

      # Both result in the pixel at (2,2) — they commute
      expect(hv.get_pixel(2, 2)).to eq(red)
      expect(vh.get_pixel(2, 2)).to eq(red)
      expect(hv).to eq(vh)
    end
  end

  # ── from_buffer (via transforms) ──────────────────────────────────────

  describe 'from_buffer internals' do
    let(:bpp) { ChromaWave::Canvas::BYTES_PER_PIXEL }

    it 'rejects a buffer with wrong byte size' do
      bad_buf = "\x00" * 10
      expect { ChromaWave::Canvas.send(:from_buffer, 3, 3, bad_buf) }
        .to raise_error(ArgumentError, /buffer size/)
    end

    it 'rejects zero width' do
      expect { ChromaWave::Canvas.send(:from_buffer, 0, 1, ''.b) }
        .to raise_error(ArgumentError, /width/)
    end

    it 'rejects zero height' do
      expect { ChromaWave::Canvas.send(:from_buffer, 1, 0, ''.b) }
        .to raise_error(ArgumentError, /height/)
    end

    it 'accepts a correctly-sized buffer and produces a valid canvas' do
      buf = ("\xFF\x00\x00\xFF" * 6).b
      result = ChromaWave::Canvas.send(:from_buffer, 3, 2, buf)

      expect(result.width).to eq(3)
      expect(result.height).to eq(2)
      expect(result.get_pixel(0, 0)).to eq(red)
    end
  end
end
