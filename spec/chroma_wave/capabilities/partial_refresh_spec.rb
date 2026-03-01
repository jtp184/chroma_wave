# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::PartialRefresh do
  # epd_2in13_v4: mono, 122x250, has :partial
  let(:model) { :epd_2in13_v4 }
  let(:display) { ChromaWave::MockDevice.new(model: model) }

  after { display.close }

  def make_framebuffer(display)
    ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
  end

  describe '#init_partial' do
    it 'returns self' do
      expect(display.init_partial).to eq(display)
    end
  end

  describe '#display_partial' do
    it 'displays a framebuffer and returns self' do
      fb = make_framebuffer(display)
      expect(display.display_partial(fb)).to eq(display)
    end

    it 'auto-initializes partial mode' do
      fb = make_framebuffer(display)
      # Should not raise even without explicit init_partial
      expect { display.display_partial(fb) }.not_to raise_error
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_partial(wrong_fb) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end
  end

  describe '#display_base' do
    it 'displays a base framebuffer and returns self' do
      fb = make_framebuffer(display)
      expect(display.display_base(fb)).to eq(display)
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_base(wrong_fb) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end
  end
end
