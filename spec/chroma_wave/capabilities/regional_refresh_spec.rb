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

  describe 'rotation support' do
    let(:model) { find_regional_model }
    let(:config) { ChromaWave::Native.model_config(model) }
    let(:nw) { config[:width] }
    let(:nh) { config[:height] }

    before { skip 'no regional model available' unless model }

    context 'with 0° rotation' do
      let(:display) { ChromaWave::MockDevice.new(model: model, rotation: 0) }
      let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

      after { display.close }

      it 'passes region coordinates unchanged' do
        expect(display.display_region(fb, x: 8, y: 4, width: 16, height: 10)).to eq(display)
      end
    end

    context 'with 90° rotation' do
      let(:display) { ChromaWave::MockDevice.new(model: model, rotation: 90) }
      let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

      after { display.close }

      it 'accepts a full-screen logical region' do
        expect(display.display_region(fb, x: 0, y: 0, width: display.width, height: display.height))
          .to eq(display)
      end

      it 'accepts a small sub-region' do
        expect(display.display_region(fb, x: 0, y: 0, width: 8, height: 8)).to eq(display)
      end
    end

    context 'with 180° rotation' do
      let(:display) { ChromaWave::MockDevice.new(model: model, rotation: 180) }
      let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

      after { display.close }

      it 'accepts a full-screen logical region' do
        expect(display.display_region(fb, x: 0, y: 0, width: display.width, height: display.height))
          .to eq(display)
      end
    end

    context 'with 270° rotation' do
      let(:display) { ChromaWave::MockDevice.new(model: model, rotation: 270) }
      let(:fb) { ChromaWave::Framebuffer.new(display.width, display.height, display.pixel_format) }

      after { display.close }

      it 'accepts a full-screen logical region' do
        expect(display.display_region(fb, x: 0, y: 0, width: display.width, height: display.height))
          .to eq(display)
      end
    end
  end

  describe '#transform_region_to_native' do
    # Use a manually extended display so we can test the private method directly
    # with known dimensions (native: 122x250).
    let(:model) { :epd_2in13_v4 }

    # Regions are logical (x, y, w, h) -> expected native (x, y, w, h).
    # Native display for epd_2in13_v4: 122x250.

    context 'with 0° rotation (122x250 logical)' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 0)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'returns coordinates unchanged' do
        result = display.send(:transform_region_to_native, 8, 4, 16, 10)
        expect(result).to eq([8, 4, 16, 10])
      end
    end

    context 'with 90° rotation (250x122 logical)' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 90)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'transforms a top-left region' do
        # Logical (0, 0, 16, 10) on 250x122 -> native on 122x250
        # native_x = nw - y - h = 122 - 0 - 10 = 112
        # native_y = x = 0
        # native_w = h = 10, native_h = w = 16
        result = display.send(:transform_region_to_native, 0, 0, 16, 10)
        expect(result).to eq([112, 0, 10, 16])
      end

      it 'transforms an interior region' do
        # Logical (20, 30, 16, 10) on 250x122
        # native_x = 122 - 30 - 10 = 82
        # native_y = 20
        # native_w = 10, native_h = 16
        result = display.send(:transform_region_to_native, 20, 30, 16, 10)
        expect(result).to eq([82, 20, 10, 16])
      end
    end

    context 'with 180° rotation (122x250 logical)' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 180)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'mirrors both axes' do
        # Logical (8, 4, 16, 10) on 122x250
        # native_x = 122 - 8 - 16 = 98
        # native_y = 250 - 4 - 10 = 236
        # native_w = 16, native_h = 10
        result = display.send(:transform_region_to_native, 8, 4, 16, 10)
        expect(result).to eq([98, 236, 16, 10])
      end
    end

    context 'with 270° rotation (250x122 logical)' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 270)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'transforms a top-left region' do
        # Logical (0, 0, 16, 10) on 250x122
        # native_x = y = 0
        # native_y = 250 - 0 - 16 = 234
        # native_w = 10, native_h = 16
        result = display.send(:transform_region_to_native, 0, 0, 16, 10)
        expect(result).to eq([0, 234, 10, 16])
      end
    end
  end

  describe '#transform_native_to_logical' do
    let(:model) { :epd_2in13_v4 }

    context 'with 0° rotation' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 0)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'returns coordinates unchanged' do
        result = display.send(:transform_native_to_logical, 8, 4, 16, 10)
        expect(result).to eq([8, 4, 16, 10])
      end
    end

    context 'with 90° rotation (250x122 logical)' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 90)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'is the inverse of transform_region_to_native' do
        logical = [20, 30, 16, 10]
        native = display.send(:transform_region_to_native, *logical)
        roundtrip = display.send(:transform_native_to_logical, *native)
        expect(roundtrip).to eq(logical)
      end
    end

    context 'with 180° rotation' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 180)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'is the inverse of transform_region_to_native' do
        logical = [8, 4, 16, 10]
        native = display.send(:transform_region_to_native, *logical)
        roundtrip = display.send(:transform_native_to_logical, *native)
        expect(roundtrip).to eq(logical)
      end
    end

    context 'with 270° rotation' do
      let(:display) do
        d = ChromaWave::MockDevice.new(model: model, rotation: 270)
        d.singleton_class.include(described_class)
        d
      end

      after { display.close }

      it 'is the inverse of transform_region_to_native' do
        logical = [10, 5, 20, 8]
        native = display.send(:transform_region_to_native, *logical)
        roundtrip = display.send(:transform_native_to_logical, *native)
        expect(roundtrip).to eq(logical)
      end
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
