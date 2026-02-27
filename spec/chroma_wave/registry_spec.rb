# frozen_string_literal: true

RSpec.describe ChromaWave::Registry do
  describe '.build' do
    it 'returns a Display instance for a valid model' do
      display = described_class.build(:epd_2in13_v4)
      expect(display).to be_a(ChromaWave::Display)
      display.close
    end

    it 'accepts a string model name' do
      display = described_class.build('epd_2in13_v4')
      expect(display).to be_a(ChromaWave::Display)
      display.close
    end

    it 'raises ModelNotFoundError for unknown model' do
      expect { described_class.build(:nonexistent) }
        .to raise_error(ChromaWave::ModelNotFoundError, /unknown model/)
    end

    it 'includes did-you-mean suggestions for similar models' do
      expect { described_class.build(:epd_2in13_v99) }
        .to raise_error(ChromaWave::ModelNotFoundError, /did you mean/)
    end

    it 'mixes in PartialRefresh for models with :partial capability' do
      display = described_class.build(:epd_2in13_v4)
      expect(display).to respond_to(:display_partial)
      display.close
    end

    it 'mixes in FastRefresh for models with :fast capability' do
      display = described_class.build(:epd_2in13_v4)
      expect(display).to respond_to(:display_fast)
      display.close
    end

    it 'mixes in GrayscaleMode for models with :grayscale capability' do
      display = described_class.build(:epd_2in7_v2)
      expect(display).to respond_to(:display_grayscale)
      display.close
    end

    it 'mixes in DualBuffer for models with :dual_buf capability' do
      display = described_class.build(:epd_2in13_v4)
      expect(display).to respond_to(:show_raw)
      display.close
    end

    it 'does not mix in capabilities the model lacks' do
      # epd_4in2 has partial, fast, grayscale but NOT dual_buf or regional
      display = described_class.build(:epd_4in2)
      expect(display).not_to respond_to(:show_raw)
      expect(display).not_to respond_to(:display_region)
      display.close
    end

    it 'caches the subclass for repeated builds of the same model' do
      d1 = described_class.build(:epd_2in13_v4)
      d2 = described_class.build(:epd_2in13_v4)
      expect(d1.class).to equal(d2.class)
      d1.close
      d2.close
    end
  end

  describe '.model_names' do
    it 'returns an array of symbols' do
      names = described_class.model_names
      expect(names).to be_an(Array)
      expect(names).to all(be_a(Symbol))
    end

    it 'includes known models' do
      names = described_class.model_names
      expect(names).to include(:epd_2in13_v4, :epd_2in7_v2)
    end
  end
end
