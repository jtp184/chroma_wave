# frozen_string_literal: true

RSpec.describe ChromaWave::Drawing::Codes do
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red)   { ChromaWave::Color::RED }
  let(:canvas) { ChromaWave::Canvas.new(width: 300, height: 300, background: white) }

  describe 'module inclusion' do
    it 'is included in Canvas' do
      expect(canvas).to respond_to(:draw_qr)
      expect(canvas).to respond_to(:draw_barcode)
    end

    it 'is included in Layer' do
      layer = canvas.layer(x: 0, y: 0, width: 100, height: 100)
      expect(layer).to respond_to(:draw_qr)
      expect(layer).to respond_to(:draw_barcode)
    end

    it 'is included in Framebuffer' do
      fb = ChromaWave::Framebuffer.new(100, 100, :mono)
      expect(fb).to respond_to(:draw_qr)
      expect(fb).to respond_to(:draw_barcode)
    end
  end

  describe '#draw_qr' do
    it 'renders dark pixels onto the canvas' do
      canvas.draw_qr('hello', x: 0, y: 0, module_size: 4)
      expect(count_non_white(canvas)).to be_positive
    end

    it 'returns self for chaining' do
      result = canvas.draw_qr('hello', x: 0, y: 0, module_size: 4)
      expect(result).to be(canvas)
    end

    it 'renders with a custom color' do
      canvas.draw_qr('hello', x: 0, y: 0, module_size: 4, color: red)
      has_red = false
      canvas.width.times do |x|
        canvas.height.times do |y|
          has_red = true if canvas.get_pixel(x, y) == red
        end
      end
      expect(has_red).to be(true)
    end

    it 'renders a background when specified' do
      bg = ChromaWave::Color.new(r: 200, g: 200, b: 200)
      canvas.draw_qr('hello', x: 0, y: 0, module_size: 4, background: bg)
      # Some pixels should be the background color (light modules)
      has_bg = false
      canvas.width.times do |x|
        canvas.height.times do |y|
          has_bg = true if canvas.get_pixel(x, y) == bg
        end
      end
      expect(has_bg).to be(true)
    end

    context 'with auto-fit sizing' do
      it 'auto-fits with max_width' do
        canvas.draw_qr('hello', x: 0, y: 0, max_width: 100)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'auto-fits with max_height' do
        canvas.draw_qr('hello', x: 0, y: 0, max_height: 100)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'auto-fits with both max_width and max_height' do
        canvas.draw_qr('hello', x: 0, y: 0, max_width: 100, max_height: 80)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'clamps module_size to 1 when constraints are very small' do
        # Even with tiny max, it should still render something
        canvas.draw_qr('hello', x: 0, y: 0, max_width: 1)
        expect(count_non_white(canvas)).to be_positive
      end
    end

    context 'with error correction levels' do
      %i[low medium quartile high].each do |level|
        it "renders with #{level} error correction" do
          canvas.draw_qr('hello', x: 0, y: 0, module_size: 2, error_correction: level)
          expect(count_non_white(canvas)).to be_positive
        end
      end
    end

    context 'with quiet_zone' do
      it 'renders with default quiet zone (4)' do
        canvas.draw_qr('hello', x: 0, y: 0, module_size: 2)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'renders with quiet_zone: 0' do
        canvas.draw_qr('hello', x: 0, y: 0, module_size: 2, quiet_zone: 0)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'accounts for quiet zone in auto-fit sizing' do
        # With quiet_zone: 0, auto-fit should produce a larger module size
        # since there are fewer total modules to fit in the same space
        canvas_no_qz = ChromaWave::Canvas.new(width: 300, height: 300, background: white)
        canvas_no_qz.draw_qr('hello', x: 0, y: 0, max_width: 100, quiet_zone: 0)
        dark_no_qz = count_non_white(canvas_no_qz)

        canvas_with_qz = ChromaWave::Canvas.new(width: 300, height: 300, background: white)
        canvas_with_qz.draw_qr('hello', x: 0, y: 0, max_width: 100, quiet_zone: 4)
        dark_with_qz = count_non_white(canvas_with_qz)

        # Larger modules with no quiet zone -> more dark pixels per module
        expect(dark_no_qz).to be > dark_with_qz
      end
    end

    context 'with invalid arguments' do
      it 'raises ArgumentError when no sizing info is provided' do
        expect { canvas.draw_qr('hello', x: 0, y: 0) }
          .to raise_error(ArgumentError, /module_size.*max_width.*max_height/)
      end

      it 'raises ArgumentError for module_size < 1' do
        expect { canvas.draw_qr('hello', x: 0, y: 0, module_size: 0) }
          .to raise_error(ArgumentError, /module_size must be a positive Integer/)
      end

      it 'raises ArgumentError for non-integer module_size' do
        expect { canvas.draw_qr('hello', x: 0, y: 0, module_size: 2.5) }
          .to raise_error(ArgumentError, /module_size must be a positive Integer/)
      end

      it 'raises ArgumentError for unknown error_correction' do
        expect { canvas.draw_qr('hello', x: 0, y: 0, module_size: 4, error_correction: :bad) }
          .to raise_error(ArgumentError, /unknown error_correction/)
      end

      it 'raises ArgumentError for negative quiet_zone' do
        expect { canvas.draw_qr('hello', x: 0, y: 0, module_size: 4, quiet_zone: -1) }
          .to raise_error(ArgumentError, /quiet_zone must be a non-negative Integer/)
      end

      it 'raises ArgumentError for non-integer quiet_zone' do
        expect { canvas.draw_qr('hello', x: 0, y: 0, module_size: 4, quiet_zone: 2.5) }
          .to raise_error(ArgumentError, /quiet_zone must be a non-negative Integer/)
      end
    end

    context 'with matching measure and render dimensions' do
      let(:bg) { ChromaWave::Color.new(r: 200, g: 200, b: 200) }
      let(:metrics) { ChromaWave::QR.measure('hello', module_size: 4) }
      let(:big) do
        ChromaWave::Canvas.new(width: 500, height: 500, background: white).tap do |c|
          c.draw_qr('hello', x: 0, y: 0, module_size: 4, background: bg)
        end
      end

      it 'renders pixels within the measured bounding box' do
        w, h = non_white_extent(big)
        expect(w).to eq(metrics.width)
        expect(h).to eq(metrics.height)
      end
    end

    context 'without required dependency' do
      before do
        hide_const('RQRCode') if defined?(RQRCode)
        allow(ChromaWave::QR).to receive(:require).with('rqrcode').and_raise(LoadError)
      end

      it 'raises DependencyError when rqrcode is not installed' do
        expect { canvas.draw_qr('hello', x: 0, y: 0, module_size: 4) }
          .to raise_error(ChromaWave::DependencyError, /rqrcode is required/)
      end
    end
  end

  describe '#draw_barcode' do
    let(:font) { ChromaWave::Font.default(size: 12) }

    it 'renders bars onto the canvas' do
      canvas.draw_barcode('ABC123', x: 10, y: 10, symbology: :code128, text_font: font)
      expect(count_non_white(canvas)).to be_positive
    end

    it 'returns self for chaining' do
      result = canvas.draw_barcode('ABC123', x: 10, y: 10, symbology: :code128, text_font: font)
      expect(result).to be(canvas)
    end

    context 'with supported symbologies' do
      it 'renders Code 128' do
        canvas.draw_barcode('Hello', x: 0, y: 0, symbology: :code128, text_font: font)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'renders EAN-13' do
        canvas.draw_barcode('123456789012', x: 0, y: 0, symbology: :ean13, text_font: font)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'renders EAN-8' do
        canvas.draw_barcode('1234567', x: 0, y: 0, symbology: :ean8, text_font: font)
        expect(count_non_white(canvas)).to be_positive
      end

      it 'renders Code 39' do
        canvas.draw_barcode('HELLO', x: 0, y: 0, symbology: :code39, text_font: font)
        expect(count_non_white(canvas)).to be_positive
      end
    end

    context 'with include_text: false' do
      it 'renders without text' do
        canvas.draw_barcode('ABC123', x: 10, y: 10, symbology: :code128, include_text: false)
        expect(count_non_white(canvas)).to be_positive
      end
    end

    context 'with background' do
      it 'renders a background behind bars' do
        bg = ChromaWave::Color.new(r: 200, g: 200, b: 200)
        canvas.draw_barcode('ABC123', x: 10, y: 10, symbology: :code128,
                                      include_text: false, background: bg)
        has_bg = false
        canvas.width.times do |x|
          canvas.height.times do |y|
            has_bg = true if canvas.get_pixel(x, y) == bg
          end
        end
        expect(has_bg).to be(true)
      end

      it 'extends background below bars to cover text area' do
        bg = ChromaWave::Color.new(r: 200, g: 200, b: 200)
        canvas.draw_barcode('ABC', x: 10, y: 10, symbology: :code128,
                                   include_text: true, text_font: font,
                                   background: bg, height: 60)
        # Background should extend into the text region below the bars
        text_area_y = 10 + 60 + 2
        has_bg = (0...canvas.width).any? { |px| canvas.get_pixel(px, text_area_y) == bg }
        expect(has_bg).to be(true)
      end
    end

    context 'with invalid arguments' do
      it 'raises ArgumentError for unknown symbology' do
        expect { canvas.draw_barcode('test', x: 0, y: 0, symbology: :bad, include_text: false) }
          .to raise_error(ArgumentError, /unknown symbology: :bad/)
      end

      it 'raises ArgumentError when include_text is true but text_font is nil' do
        expect { canvas.draw_barcode('ABC', x: 0, y: 0, symbology: :code128, include_text: true) }
          .to raise_error(ArgumentError, /text_font:.*required.*include_text/)
      end
    end

    context 'with Framebuffer surface' do
      let(:fb) { ChromaWave::Framebuffer.new(200, 100, :mono) }

      it 'raises ArgumentError for include_text: true on Framebuffer' do
        expect { fb.draw_barcode('ABC', x: 0, y: 0, symbology: :code128, include_text: true) }
          .to raise_error(ArgumentError, /include_text.*draw_text/)
      end

      it 'works with include_text: false on Framebuffer' do
        expect do
          fb.draw_barcode('ABC', x: 0, y: 0, symbology: :code128,
                                 include_text: false, color: :black)
        end.not_to raise_error
      end
    end

    context 'with invalid barcode data' do
      it 'raises ArgumentError with user-friendly message for invalid EAN data' do
        expect { canvas.draw_barcode('abc', x: 0, y: 0, symbology: :ean13, include_text: false) }
          .to raise_error(ArgumentError, /invalid data for ean13/)
      end
    end

    context 'with matching measure and render dimensions' do
      let(:bg) { ChromaWave::Color.new(r: 200, g: 200, b: 200) }
      let(:metrics) { ChromaWave::Barcode.measure('ABC123', symbology: :code128) }
      let(:big) do
        ChromaWave::Canvas.new(width: 500, height: 500, background: white).tap do |c|
          c.draw_barcode('ABC123', x: 0, y: 0, symbology: :code128,
                                   include_text: false, background: bg)
        end
      end

      it 'renders pixels within the measured bounding box' do
        w, h = non_white_extent(big)
        expect(w).to eq(metrics.width)
        expect(h).to eq(metrics.height)
      end
    end

    context 'without required dependency' do
      before do
        hide_const('Barby') if defined?(Barby)
        allow(ChromaWave::Barcode).to receive(:require).with('barby').and_raise(LoadError)
      end

      it 'raises DependencyError when barby is not installed' do
        expect { canvas.draw_barcode('test', x: 0, y: 0, symbology: :code128, include_text: false) }
          .to raise_error(ChromaWave::DependencyError, /barby is required/)
      end
    end
  end
end
