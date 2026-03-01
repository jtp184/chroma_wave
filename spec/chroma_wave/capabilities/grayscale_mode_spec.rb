# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::GrayscaleMode do
  # epd_2in7_v2: mono, 176x264, has :grayscale
  let(:model) { :epd_2in7_v2 }
  let(:display) { ChromaWave::MockDevice.new(model: model) }

  after { display.close }

  def make_framebuffer(display)
    ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
  end

  describe '#init_grayscale' do
    it 'returns self' do
      expect(display.init_grayscale).to eq(display)
    end
  end

  describe '#display_grayscale' do
    it 'displays a framebuffer and returns self' do
      fb = make_framebuffer(display)
      expect(display.display_grayscale(fb)).to eq(display)
    end

    it 'auto-initializes grayscale mode' do
      fb = make_framebuffer(display)
      expect { display.display_grayscale(fb) }.not_to raise_error
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_grayscale(wrong_fb) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end
  end
end
