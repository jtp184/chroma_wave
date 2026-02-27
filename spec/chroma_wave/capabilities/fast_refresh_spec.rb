# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::FastRefresh do
  # epd_2in13_v4: mono, 122x250, has :fast
  let(:model) { :epd_2in13_v4 }

  def make_framebuffer(display)
    ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
  end

  describe '#init_fast' do
    it 'returns self' do
      ChromaWave::Display.open(model: model) do |display|
        expect(display.init_fast).to eq(display)
      end
    end
  end

  describe '#display_fast' do
    it 'displays a framebuffer and returns self' do
      ChromaWave::Display.open(model: model) do |display|
        fb = make_framebuffer(display)
        expect(display.display_fast(fb)).to eq(display)
      end
    end

    it 'auto-initializes fast mode' do
      ChromaWave::Display.open(model: model) do |display|
        fb = make_framebuffer(display)
        expect { display.display_fast(fb) }.not_to raise_error
      end
    end

    it 'raises FormatMismatchError for wrong format' do
      ChromaWave::Display.open(model: model) do |display|
        wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
        expect { display.display_fast(wrong_fb) }
          .to raise_error(ChromaWave::FormatMismatchError)
      end
    end
  end
end
