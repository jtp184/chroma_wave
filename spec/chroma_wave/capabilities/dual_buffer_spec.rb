# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::DualBuffer do
  # epd_2in9b_v4: color4, has :partial, :fast, :dual_buf
  let(:model) { :epd_2in9b_v4 }
  let(:config) { ChromaWave::Native.model_config(model.to_s) }

  describe '#show with Canvas' do
    it 'renders via dual-buffer path and returns self' do
      ChromaWave::Display.open(model: model) do |display|
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        expect(display.show(canvas)).to eq(display)
      end
    end
  end

  describe '#show with Framebuffer' do
    it 'falls through to single-buffer Display#show' do
      ChromaWave::Display.open(model: model) do |display|
        fb = ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
        expect(display.show(fb)).to eq(display)
      end
    end
  end

  describe '#show_raw' do
    it 'sends pre-rendered dual framebuffers and returns self' do
      ChromaWave::Display.open(model: model) do |display|
        black_fb = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
        red_fb   = ChromaWave::Framebuffer.new(display.width, display.height, :mono)
        expect(display.show_raw(black_fb, red_fb)).to eq(display)
      end
    end
  end
end
