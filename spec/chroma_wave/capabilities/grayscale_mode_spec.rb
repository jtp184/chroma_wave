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
      display.display_grayscale(fb)
      init_op = display.operations(:init).first
      expect(init_op[:mode]).to eq(:grayscale)
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_grayscale(wrong_fb) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end

    it 'skips re-init when already in grayscale mode' do
      fb = make_framebuffer(display)
      display.display_grayscale(fb) # auto-inits grayscale
      display.clear_operations!
      display.display_grayscale(fb) # should not re-init

      expect(display.operations(:init)).to be_empty
    end
  end

  describe 'mode transition from full to grayscale' do
    it 'transitions from full to grayscale mode' do
      fb = make_framebuffer(display)
      canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
      display.show(canvas) # init full mode
      display.display_grayscale(fb)

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[full grayscale])
    end
  end

  describe 'mode transition from grayscale to full' do
    it 're-initializes full mode after grayscale via show' do
      fb = make_framebuffer(display)
      display.display_grayscale(fb)  # init grayscale
      display.deep_sleep             # reset mode
      canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
      display.show(canvas)           # re-init as full

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[grayscale full])
    end
  end
end
