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

    it 'auto-initializes full mode before displaying base' do
      fb = make_framebuffer(display)
      display.display_base(fb)
      # display_base calls ensure_initialized! which inits full mode
      init_ops = display.operations(:init)
      expect(init_ops.first[:mode]).to eq(:full)
    end
  end

  describe 'mode transition from full to partial' do
    it 'transitions from full to partial mode' do
      fb = make_framebuffer(display)
      display.show(make_canvas(display)) # init full mode
      display.display_partial(fb)

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[full partial])
    end

    it 'skips re-init when already in partial mode' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # auto-inits partial
      display.clear_operations!
      display.display_partial(fb) # should not re-init

      expect(display.operations(:init)).to be_empty
    end
  end

  describe 'mode transition from partial to full' do
    it 're-initializes full mode after partial via show' do
      fb = make_framebuffer(display)
      display.display_partial(fb)  # init partial
      display.deep_sleep           # reset mode
      display.show(make_canvas(display)) # re-init as full

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[partial full])
    end
  end

  describe 'mode transition from partial to fast' do
    it 'transitions from partial to fast mode' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # init partial
      display.display_fast(fb)    # switch to fast

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[partial fast])
    end
  end

  describe 'mode transition from fast to partial' do
    it 'transitions from fast to partial mode' do
      fb = make_framebuffer(display)
      display.display_fast(fb)    # init fast
      display.display_partial(fb) # switch to partial

      init_ops = display.operations(:init)
      expect(init_ops.map { |o| o[:mode] }).to eq(%i[fast partial])
    end
  end

  private

  def make_canvas(display)
    ChromaWave::Canvas.new(width: display.width, height: display.height)
  end
end
