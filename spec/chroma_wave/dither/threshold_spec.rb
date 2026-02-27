# frozen_string_literal: true

require_relative 'shared_examples'

RSpec.describe ChromaWave::Dither::Threshold do
  let(:mono_format)  { ChromaWave::PixelFormat::MONO }
  let(:gray_format)  { ChromaWave::PixelFormat::GRAY4 }
  let(:tricolor)     { ChromaWave::PixelFormat::COLOR4 }
  let(:seven_color)  { ChromaWave::PixelFormat::COLOR7 }

  let(:black) { ChromaWave::Color::BLACK }
  let(:white) { ChromaWave::Color::WHITE }
  let(:red)   { ChromaWave::Color::RED }

  it_behaves_like 'a dither strategy'

  describe '#call' do
    it 'renders red to the nearest MONO palette color (black)' do
      canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: red)
      framebuffer = ChromaWave::Framebuffer.new(1, 1, mono_format)
      described_class.new(pixel_format: mono_format).call(canvas, framebuffer)
      expect(framebuffer.get_pixel(0, 0)).to eq(:black)
    end

    context 'with GRAY4 format' do
      let(:strategy) { described_class.new(pixel_format: gray_format) }

      it 'maps pure black to :black' do
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: black)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, gray_format)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:black)
      end

      it 'maps pure white to :white' do
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: white)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, gray_format)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:white)
      end

      it 'maps mid-gray to a gray shade' do
        mid_gray = ChromaWave::Color.new(r: 128, g: 128, b: 128)
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: mid_gray)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, gray_format)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:dark_gray).or eq(:light_gray)
      end
    end

    context 'with COLOR4 format' do
      let(:strategy) { described_class.new(pixel_format: tricolor) }

      it 'maps pure red to :red' do
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: red)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, tricolor)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:red)
      end

      it 'maps pure yellow to :yellow' do
        yellow = ChromaWave::Color::YELLOW
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: yellow)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, tricolor)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:yellow)
      end
    end

    context 'with COLOR7 format' do
      let(:strategy) { described_class.new(pixel_format: seven_color) }

      it 'maps pure green to :green' do
        green = ChromaWave::Color::GREEN
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: green)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, seven_color)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:green)
      end

      it 'maps pure blue to :blue' do
        blue = ChromaWave::Color::BLUE
        canvas = ChromaWave::Canvas.new(width: 1, height: 1, background: blue)
        framebuffer = ChromaWave::Framebuffer.new(1, 1, seven_color)
        strategy.call(canvas, framebuffer)
        expect(framebuffer.get_pixel(0, 0)).to eq(:blue)
      end
    end
  end

  describe '.strategy_name' do
    it 'returns :threshold' do
      expect(described_class.strategy_name).to eq(:threshold)
    end
  end
end
