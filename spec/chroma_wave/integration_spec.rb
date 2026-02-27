# frozen_string_literal: true

RSpec.describe ChromaWave::Display do # rubocop:disable RSpec/SpecFilePathFormat -- cross-cutting integration spec
  describe 'Canvas -> Renderer -> Display pipeline' do
    let(:model_names) { ChromaWave::Native.model_names }

    context 'with a mono display' do
      let(:model) { model_names.find { |n| ChromaWave::Native.model_config(n)[:pixel_format] == :mono } }
      let(:config) { ChromaWave::Native.model_config(model) }

      it 'renders a black canvas onto a mono display' do
        display = described_class.new(model: model)
        canvas = ChromaWave::Canvas.new(width: config[:width], height: config[:height],
                                        background: ChromaWave::Color::BLACK)
        expect { display.show(canvas) }.not_to raise_error
        display.close
      end

      it 'renders a white canvas onto a mono display' do
        described_class.open(model: model) do |display|
          canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
          expect { display.show(canvas) }.not_to raise_error
        end
      end

      it 'clears the display' do
        described_class.open(model: model) do |display|
          expect { display.clear }.not_to raise_error
        end
      end

      it 'sleeps the display' do
        described_class.open(model: model) do |display|
          display.clear
          expect { display.deep_sleep }.not_to raise_error
        end
      end
    end

    context 'with a 7-color display' do
      let(:model) { model_names.find { |n| ChromaWave::Native.model_config(n)[:pixel_format] == :color7 } }

      it 'renders a colorful canvas' do
        skip 'no color7 model available' unless model

        config = ChromaWave::Native.model_config(model)
        described_class.open(model: model) do |display|
          canvas = ChromaWave::Canvas.new(width: config[:width], height: config[:height])
          # Draw a few colored pixels
          canvas.set_pixel(0, 0, ChromaWave::Color::RED)
          canvas.set_pixel(1, 0, ChromaWave::Color::GREEN)
          canvas.set_pixel(2, 0, ChromaWave::Color::BLUE)
          expect { display.show(canvas) }.not_to raise_error
        end
      end
    end

    context 'with a dual-buffer display' do
      let(:model) do
        model_names.find do |n|
          cfg = ChromaWave::Native.model_config(n)
          cfg[:pixel_format] == :color4 && cfg[:capabilities].include?(:dual_buf)
        end
      end

      it 'renders using dual-buffer split' do
        skip 'no dual_buf color4 model available' unless model

        config = ChromaWave::Native.model_config(model)
        described_class.open(model: model) do |display|
          canvas = ChromaWave::Canvas.new(width: config[:width], height: config[:height])
          canvas.set_pixel(0, 0, ChromaWave::Color::RED)
          canvas.set_pixel(1, 0, ChromaWave::Color::BLACK)
          canvas.set_pixel(2, 0, ChromaWave::Color::WHITE)
          expect { display.show(canvas) }.not_to raise_error
        end
      end
    end

    context 'with a display supporting partial refresh' do
      let(:model) do
        model_names.find do |n|
          ChromaWave::Native.model_config(n)[:capabilities].include?(:partial)
        end
      end

      it 'supports partial refresh capability' do
        skip 'no partial-refresh model available' unless model

        config = ChromaWave::Native.model_config(model)
        display = described_class.new(model: model)
        fb = ChromaWave::Framebuffer.new(config[:width], config[:height], config[:pixel_format])

        expect(display).to respond_to(:display_partial)
        expect { display.display_partial(fb) }.not_to raise_error
        display.close
      end
    end
  end

  describe 'lazy initialization' do
    let(:model) { ChromaWave::Native.model_names.first }

    it 'does not init until first show' do
      display = described_class.new(model: model)
      # No error just from construction -- init happens lazily
      expect(display).to be_a(described_class)
      display.close
    end
  end

  describe 'format mismatch' do
    it 'raises FormatMismatchError for wrong framebuffer format' do
      mono_model = ChromaWave::Native.model_names.find do |n|
        ChromaWave::Native.model_config(n)[:pixel_format] == :mono
      end
      skip 'no mono model available' unless mono_model

      display = described_class.new(model: mono_model)
      wrong_fb = ChromaWave::Framebuffer.new(10, 10, :gray4)

      expect { display.show(wrong_fb) }.to raise_error(ChromaWave::FormatMismatchError)
      display.close
    end
  end

  describe 'Registry coverage' do
    it 'registers all models from the C config' do
      expect(described_class.models.size).to eq(ChromaWave::Native.model_count)
    end

    it 'all models are constructible' do
      described_class.models.each do |model|
        display = described_class.new(model: model)
        expect(display).to be_a(described_class)
        expect(display.width).to be_positive
        expect(display.height).to be_positive
        display.close
      end
    end
  end

  describe 'Renderer standalone' do
    ChromaWave::PixelFormat::REGISTRY.each_value do |fmt|
      context "with #{fmt.name} format" do
        it 'renders a gradient canvas' do
          canvas = ChromaWave::Canvas.new(width: 16, height: 16)
          16.times do |x|
            gray = (x * 255) / 15
            canvas.set_pixel(x, 0, ChromaWave::Color.new(r: gray, g: gray, b: gray))
          end

          renderer = ChromaWave::Renderer.new(pixel_format: fmt)
          fb = renderer.render(canvas)

          expect(fb.width).to eq(16)
          expect(fb.height).to eq(16)
          expect(fb.pixel_format).to eq(fmt)
        end
      end
    end
  end
end
