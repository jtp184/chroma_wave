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
      display.display_fast(fb)
      init_op = display.operations(:init).first
      expect(init_op[:mode]).to eq(:fast)
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_fast(wrong_fb) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end

    it 'skips re-init when already in fast mode' do
      fb = make_framebuffer(display)
      display.display_fast(fb) # auto-inits fast
      display.clear_operations!
      display.display_fast(fb) # should not re-init

      expect(display.operations(:init)).to be_empty
    end
  end

  describe 'mode transition from full to fast' do
    it 'transitions from full to fast mode' do
      fb = make_framebuffer(display)
      canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
      display.show(canvas) # init full mode
      display.display_fast(fb)

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[full fast])
    end
  end

  describe 'mode transition from fast to full' do
    it 're-initializes full mode after fast via show' do
      fb = make_framebuffer(display)
      display.display_fast(fb)   # init fast
      display.deep_sleep         # reset mode
      canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
      display.show(canvas)       # re-init as full

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[fast full])
    end
  end
end
