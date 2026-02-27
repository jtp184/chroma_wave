# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::RegionalRefresh do
  # No current model has :regional in its capabilities, so we test by
  # creating a display for a model that has other capabilities and manually
  # verifying the module's interface. We'll use a model that we can extend.

  # We test using a display that we manually extend with RegionalRefresh.
  let(:model) { :epd_2in13_v4 }
  let(:display) do
    d = ChromaWave::Display.new(model: model)
    d.singleton_class.include(described_class)
    d
  end
  let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

  after { display.close }

  describe '#display_region' do
    it 'succeeds with valid region bounds' do
      expect(display.display_region(fb, x: 0, y: 0, width: 50, height: 50)).to eq(display)
    end

    it 'raises ArgumentError for x out of bounds' do
      expect { display.display_region(fb, x: -1, y: 0, width: 10, height: 10) }
        .to raise_error(ArgumentError, /region x/)
    end

    it 'raises ArgumentError for y out of bounds' do
      expect { display.display_region(fb, x: 0, y: -1, width: 10, height: 10) }
        .to raise_error(ArgumentError, /region y/)
    end

    it 'raises ArgumentError for region exceeding display width' do
      expect { display.display_region(fb, x: 100, y: 0, width: 100, height: 10) }
        .to raise_error(ArgumentError, /region width/)
    end

    it 'raises ArgumentError for region exceeding display height' do
      expect { display.display_region(fb, x: 0, y: 200, width: 10, height: 100) }
        .to raise_error(ArgumentError, /region height/)
    end

    it 'raises ArgumentError for zero-width region' do
      expect { display.display_region(fb, x: 0, y: 0, width: 0, height: 10) }
        .to raise_error(ArgumentError, /region width must be positive/)
    end

    it 'raises ArgumentError for zero-height region' do
      expect { display.display_region(fb, x: 0, y: 0, width: 10, height: 0) }
        .to raise_error(ArgumentError, /region height must be positive/)
    end

    it 'raises FormatMismatchError for wrong format' do
      wrong_fb = ChromaWave::Framebuffer.new(display.width, display.height, :color4)
      expect { display.display_region(wrong_fb, x: 0, y: 0, width: 10, height: 10) }
        .to raise_error(ChromaWave::FormatMismatchError)
    end
  end
end
