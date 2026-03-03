# frozen_string_literal: true

require_relative 'shared_examples'

RSpec.describe ChromaWave::Dither::Atkinson do
  include DitherSpecHelpers

  let(:mono_format)  { ChromaWave::PixelFormat::MONO }
  let(:gray_format)  { ChromaWave::PixelFormat::GRAY4 }
  let(:color4_format) { ChromaWave::PixelFormat::COLOR4 }
  let(:color7_format) { ChromaWave::PixelFormat::COLOR7 }

  it_behaves_like 'a dither strategy'

  describe '.strategy_name' do
    it 'returns :atkinson' do
      expect(described_class.strategy_name).to eq(:atkinson)
    end
  end

  describe '#call' do
    it 'produces at least as many transitions as threshold on a gradient' do
      canvas = build_gradient_canvas(width: 16, height: 1)

      threshold_fb = render_with(ChromaWave::Dither::Threshold, gray_format, canvas)
      atkinson_fb = render_with(described_class, gray_format, canvas)

      expect(count_transitions(atkinson_fb, 16)).to be >= count_transitions(threshold_fb, 16)
    end

    it 'distributes exactly 75% of quantization error (6/8)' do
      # The defining characteristic of Atkinson dithering is that it distributes
      # only 6/8 of the error to 6 neighbors at 1/8 each, discarding 25%.
      # We verify this structurally via the ATK_WEIGHT constant.
      expect(described_class::ATK_WEIGHT).to eq(1.0 / 8)

      # 6 neighbors * 1/8 each = 6/8 = 75% total error distributed
      expect(described_class::ATK_WEIGHT * 6).to eq(0.75)
    end

    it 'produces a different dithering pattern than Floyd-Steinberg' do
      canvas = build_gradient_canvas(width: 16, height: 4)

      fs_fb = render_with(ChromaWave::Dither::FloydSteinberg, gray_format, canvas)
      atk_fb = render_with(described_class, gray_format, canvas)

      # With GRAY4 (4 shades), the different error distribution kernels produce
      # distinguishable patterns. Collect all pixels and compare.
      fs_pixels = collect_pixels(fs_fb, 16, 4)
      atk_pixels = collect_pixels(atk_fb, 16, 4)

      expect(atk_pixels).not_to eq(fs_pixels)
    end

    it 'works with all pixel formats without error' do
      canvas = ChromaWave::Canvas.new(width: 8, height: 8, background: ChromaWave::Color::WHITE)
      mid = ChromaWave::Color.new(r: 128, g: 128, b: 128)
      4.times { |x| 4.times { |y| canvas.set_pixel(x, y, mid) } }

      [mono_format, gray_format, color4_format, color7_format].each do |fmt|
        framebuffer = ChromaWave::Framebuffer.new(8, 8, fmt)
        strategy = described_class.new(pixel_format: fmt)
        expect { strategy.call(canvas, framebuffer) }.not_to raise_error
      end
    end

    it 'handles a 1x1 canvas without error' do
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: ChromaWave::Color::WHITE)
      framebuffer = ChromaWave::Framebuffer.new(1, 1, mono_format)
      strategy = described_class.new(pixel_format: mono_format)
      expect { strategy.call(canvas, framebuffer) }.not_to raise_error
      expect(framebuffer.get_pixel(0, 0)).to eq(:white)
    end

    it 'handles a 3x3 canvas without out-of-bounds errors' do
      mid = ChromaWave::Color.new(r: 128, g: 128, b: 128)
      canvas = ChromaWave::Canvas.new(width: 3, height: 3, background: mid)
      framebuffer = ChromaWave::Framebuffer.new(3, 3, mono_format)
      strategy = described_class.new(pixel_format: mono_format)
      expect { strategy.call(canvas, framebuffer) }.not_to raise_error
    end
  end
end
