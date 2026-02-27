# frozen_string_literal: true

RSpec.describe ChromaWave::Display do
  # epd_2in13_v4: mono, 122x250, has :partial, :fast, :dual_buf
  let(:model) { :epd_2in13_v4 }
  let(:config) { ChromaWave::Native.model_config(model.to_s) }

  describe '.new' do
    it 'returns a Display subclass instance' do
      display = described_class.new(model: model)
      expect(display).to be_a(described_class)
      display.close
    end

    it 'sets the model as a symbol' do
      display = described_class.new(model: model)
      expect(display.model).to eq(:epd_2in13_v4)
      display.close
    end

    it 'sets the width from the config' do
      display = described_class.new(model: model)
      expect(display.width).to eq(config[:width])
      display.close
    end

    it 'sets the height from the config' do
      display = described_class.new(model: model)
      expect(display.height).to eq(config[:height])
      display.close
    end

    it 'sets the pixel_format from the config' do
      display = described_class.new(model: model)
      expect(display.pixel_format).to eq(ChromaWave::PixelFormat::MONO)
      display.close
    end

    it 'accepts a string model name' do
      display = described_class.new(model: 'epd_2in13_v4')
      expect(display.model).to eq(:epd_2in13_v4)
      display.close
    end

    it 'raises ModelNotFoundError for an unknown model' do
      expect { described_class.new(model: :nonexistent_model) }
        .to raise_error(ChromaWave::ModelNotFoundError, /unknown model/)
    end

    it 'raises ArgumentError when model is omitted' do
      expect { described_class.new }
        .to raise_error(ArgumentError, /missing keyword/)
    end
  end

  describe '.open' do
    context 'without a block' do
      it 'returns an open display' do
        display = described_class.open(model: model)
        expect(display).to be_a(described_class)
        display.close
      end
    end

    context 'with a block' do
      it 'yields the display' do
        yielded = nil
        described_class.open(model: model) { |d| yielded = d }
        expect(yielded).to be_a(described_class)
      end

      it 'returns the block value' do
        result = described_class.open(model: model, &:model)
        expect(result).to eq(:epd_2in13_v4)
      end

      it 'closes the display after the block' do
        display_ref = nil
        described_class.open(model: model) { |d| display_ref = d }
        # After close, the underlying device should be closed
        expect { display_ref.show(make_canvas) }.to raise_error(ChromaWave::DeviceError)
      end

      it 'closes the display even if the block raises' do
        display_ref = nil
        begin
          described_class.open(model: model) do |d|
            display_ref = d
            raise 'boom'
          end
        rescue RuntimeError
          nil
        end
        expect { display_ref.show(make_canvas) }.to raise_error(ChromaWave::DeviceError)
      end
    end
  end

  describe '.models' do
    it 'returns an array of symbols' do
      models = described_class.models
      expect(models).to be_an(Array)
      expect(models).to all(be_a(Symbol))
    end

    it 'includes epd_2in13_v4' do
      expect(described_class.models).to include(:epd_2in13_v4)
    end
  end

  describe '#show' do
    it 'accepts a Canvas' do
      described_class.open(model: model) do |display|
        canvas = make_canvas(display)
        expect(display.show(canvas)).to eq(display)
      end
    end

    it 'accepts a Framebuffer with matching format' do
      described_class.open(model: model) do |display|
        fb = ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format)
        expect(display.show(fb)).to eq(display)
      end
    end

    it 'raises FormatMismatchError for wrong pixel format' do
      described_class.open(model: model) do |display|
        wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
        expect { display.show(wrong_fb) }
          .to raise_error(ChromaWave::FormatMismatchError, /expected mono/)
      end
    end

    it 'lazily initializes the display on first show' do
      # Just verifying it works without explicit init
      described_class.open(model: model) do |display|
        canvas = make_canvas(display)
        expect { display.show(canvas) }.not_to raise_error
      end
    end
  end

  describe '#clear' do
    it 'returns self' do
      described_class.open(model: model) do |display|
        expect(display.clear).to eq(display)
      end
    end
  end

  describe '#deep_sleep' do
    it 'returns self' do
      described_class.open(model: model) do |display|
        display.show(make_canvas(display)) # force init
        expect(display.deep_sleep).to eq(display)
      end
    end

    it 're-initializes on next show after deep_sleep' do
      described_class.open(model: model) do |display|
        display.show(make_canvas(display))
        display.deep_sleep
        # Should re-init and work
        expect { display.show(make_canvas(display)) }.not_to raise_error
      end
    end
  end

  describe '#close' do
    it 'makes subsequent show calls raise' do
      display = described_class.new(model: model)
      display.close
      expect { display.show(make_canvas) }.to raise_error(ChromaWave::DeviceError)
    end
  end

  describe '#renderer' do
    it 'returns a Renderer with the correct pixel format' do
      described_class.open(model: model) do |display|
        expect(display.renderer).to be_a(ChromaWave::Renderer)
        expect(display.renderer.pixel_format).to eq(display.pixel_format)
      end
    end

    it 'memoizes the renderer' do
      described_class.open(model: model) do |display|
        expect(display.renderer).to equal(display.renderer)
      end
    end
  end

  describe '#inspect' do
    it 'includes model, dimensions, and format' do
      described_class.open(model: model) do |display|
        text = display.inspect
        expect(text).to include('epd_2in13_v4')
        expect(text).to include('122x250')
        expect(text).to include('mono')
      end
    end
  end

  private

  # Builds a Canvas sized for the given display (or default 122x250).
  def make_canvas(display = nil)
    w = display&.width || 122
    h = display&.height || 250
    ChromaWave::Canvas.new(width: w, height: h)
  end
end
