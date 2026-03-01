# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::FastRefresh do
  # epd_2in13_v4: mono, 122x250, has :fast
  let(:model) { :epd_2in13_v4 }
  let(:display) { ChromaWave::MockDevice.new(model: model) }

  after { display.close }

  def make_framebuffer(display)
    ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
  end

  describe '#init_fast' do
    it 'returns self' do
      expect(display.init_fast).to eq(display)
    end
  end

  describe '#display_fast' do
    it 'displays a framebuffer and returns self' do
      fb = make_framebuffer(display)
      expect(display.display_fast(fb)).to eq(display)
    end

    it 'auto-initializes fast mode' do
      fb = make_framebuffer(display)
      expect { display.display_fast(fb) }.not_to raise_error
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_fast(wrong_fb) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end
  end
end
