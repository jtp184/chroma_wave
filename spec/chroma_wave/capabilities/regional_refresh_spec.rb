# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::RegionalRefresh do
  # Helper: find a model with :regional capability
  def find_regional_model
    ChromaWave::Native.model_names.find do |name|
      ChromaWave::Native.model_config(name)[:capabilities].include?(:regional)
    end
  end

  # Helper: find a model without :regional capability
  def find_non_regional_model
    ChromaWave::Native.model_names.find do |name|
      !ChromaWave::Native.model_config(name)[:capabilities].include?(:regional)
    end
  end

  context 'with a real regional model' do
    let(:model) { find_regional_model }
    let(:display) { ChromaWave::MockDevice.new(model: model) }
    let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

    before { skip 'no regional model available' unless model }
    after { display.close }

    it 'responds to display_region' do
      expect(display).to respond_to(:display_region)
    end

    it 'succeeds with a byte-aligned region' do
      expect(display.display_region(fb, x: 0, y: 0, width: 16, height: 16)).to eq(display)
    end

    it 'succeeds with a full-screen region' do
      expect(display.display_region(fb, x: 0, y: 0, width: display.width, height: display.height))
        .to eq(display)
    end

    it 'auto-aligns non-byte-aligned X to 8px boundary' do
      # x=3 should be floored to 0, width=10 from x=3 ends at 13, ceil to 16
      expect(display.display_region(fb, x: 3, y: 0, width: 10, height: 10)).to eq(display)
    end
  end

  context 'with a manually extended display' do
    # For models without :regional, we manually extend to test validation logic
    let(:model) { :epd_2in13_v4 }
    let(:display) do
      d = ChromaWave::MockDevice.new(model: model)
      d.singleton_class.include(described_class)
      d
    end
    let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

    after { display.close }

    describe 'validation' do
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

  describe '#align_x_to_byte_boundary (via display_region)' do
    let(:model) { find_regional_model }
    let(:display) { ChromaWave::MockDevice.new(model: model) }
    let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

    before { skip 'no regional model available' unless model }
    after { display.close }

    it 'handles x=0 (already aligned)' do
      expect { display.display_region(fb, x: 0, y: 0, width: 8, height: 1) }.not_to raise_error
    end

    it 'handles x at an 8px boundary' do
      expect { display.display_region(fb, x: 8, y: 0, width: 8, height: 1) }.not_to raise_error
    end

    it 'handles region at the display edge' do
      w = display.width
      # Last 8 pixels
      x = (w - 8) & ~7
      expect { display.display_region(fb, x: x, y: 0, width: w - x, height: 1) }.not_to raise_error
    end
  end

  describe 'capability inclusion' do
    it 'is not included on models without :regional' do
      non_regional = find_non_regional_model
      skip 'all models are regional' unless non_regional
      display = ChromaWave::MockDevice.new(model: non_regional)
      expect(display).not_to respond_to(:display_region)
      display.close
    end

    it 'is included on models with :regional' do
      regional = find_regional_model
      skip 'no regional model available' unless regional
      display = ChromaWave::MockDevice.new(model: regional)
      expect(display).to respond_to(:display_region)
      expect(display).to be_a(described_class)
      display.close
    end

    it 'at least 5 models have regional capability' do
      regional_models = ChromaWave::Native.model_names.select do |name|
        ChromaWave::Native.model_config(name)[:capabilities].include?(:regional)
      end
      expect(regional_models.size).to be >= 5
    end
  end
end
