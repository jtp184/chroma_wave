# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::DualBuffer do
  # epd_2in9b_v4: color4, has :partial, :fast, :dual_buf
  let(:model) { :epd_2in9b_v4 }
  let(:config) { ChromaWave::Native.model_config(model.to_s) }
  let(:display) { ChromaWave::MockDevice.new(model: model) }

  after { display.close }

  describe '#show with Canvas' do
    it 'renders via dual-buffer path and returns self' do
      canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
      expect(display.show(canvas)).to eq(display)
    end
  end

  describe '#show with Framebuffer' do
    it 'falls through to single-buffer Display#show' do
      fb = ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
      expect(display.show(fb)).to eq(display)
    end
  end

  describe '#show_raw' do
    it 'sends pre-rendered dual framebuffers and returns self' do
      black_fb = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
      red_fb   = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
      expect(display.show_raw(black_fb, red_fb)).to eq(display)
    end

    it 'raises TypeError when black_fb is not a Framebuffer' do
      red_fb = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
      expect { display.show_raw('not a framebuffer', red_fb) }
        .to raise_error(TypeError, /expected Framebuffer/)
    end

    it 'raises TypeError when red_fb is not a Framebuffer' do
      black_fb = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
      expect { display.show_raw(black_fb, 42) }
        .to raise_error(TypeError, /expected Framebuffer/)
    end

    it 'raises FormatMismatchError when black_fb is not MONO' do
      black_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      red_fb   = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
      expect { display.show_raw(black_fb, red_fb) }
        .to raise_error(ChromaWave::FormatMismatchError, /expected MONO/)
    end

    it 'raises FormatMismatchError when red_fb is not MONO' do
      black_fb = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
      red_fb   = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.show_raw(black_fb, red_fb) }
        .to raise_error(ChromaWave::FormatMismatchError, /expected MONO/)
    end

    it 'raises ArgumentError when dimensions do not match' do
      black_fb = ChromaWave::Framebuffer.new(10, 10, :mono)
      red_fb   = ChromaWave::Framebuffer.new(10, 10, :mono)
      expect { display.show_raw(black_fb, red_fb) }
        .to raise_error(ArgumentError, /dimensions must match/)
    end
  end

  describe '#show with non-Canvas non-Framebuffer' do
    it 'raises TypeError for invalid argument' do
      expect { display.show('not a canvas') }.to raise_error(TypeError)
    end
  end
end
