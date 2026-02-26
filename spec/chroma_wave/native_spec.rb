# frozen_string_literal: true

RSpec.describe ChromaWave::Native do
  describe '.model_count' do
    it 'returns an Integer' do
      expect(described_class.model_count).to be_an(Integer)
    end

    it 'has at least 65 registered models' do
      expect(described_class.model_count).to be >= 65
    end
  end

  describe '.model_names' do
    subject(:names) { described_class.model_names }

    it 'returns an Array' do
      expect(names).to be_an(Array)
    end

    it 'contains only Strings' do
      expect(names).to all(be_a(String))
    end

    it 'includes epd_2in13_v4' do
      expect(names).to include('epd_2in13_v4')
    end

    it 'includes epd_2in7_v2' do
      expect(names).to include('epd_2in7_v2')
    end

    it 'includes epd_5in65f' do
      expect(names).to include('epd_5in65f')
    end

    it 'has the same length as model_count' do
      expect(names.length).to eq(described_class.model_count)
    end
  end

  describe '.model_config' do
    context 'with epd_2in13_v4' do
      subject(:config) { described_class.model_config('epd_2in13_v4') }

      it 'returns width 122' do
        expect(config[:width]).to eq(122)
      end

      it 'returns height 250' do
        expect(config[:height]).to eq(250)
      end

      it 'returns pixel_format :mono' do
        expect(config[:pixel_format]).to eq(:mono)
      end

      it 'includes :partial in capabilities' do
        expect(config[:capabilities]).to include(:partial)
      end

      it 'includes :fast in capabilities' do
        expect(config[:capabilities]).to include(:fast)
      end

      it 'is not a tier2 model' do
        expect(config[:tier2]).to be(false)
      end
    end

    context 'with epd_2in7_v2' do
      subject(:config) { described_class.model_config('epd_2in7_v2') }

      it 'returns width 176' do
        expect(config[:width]).to eq(176)
      end

      it 'returns height 264' do
        expect(config[:height]).to eq(264)
      end

      it 'returns pixel_format :mono' do
        expect(config[:pixel_format]).to eq(:mono)
      end

      it 'includes :partial in capabilities' do
        expect(config[:capabilities]).to include(:partial)
      end

      it 'includes :fast in capabilities' do
        expect(config[:capabilities]).to include(:fast)
      end

      it 'includes :grayscale in capabilities' do
        expect(config[:capabilities]).to include(:grayscale)
      end

      it 'is a tier2 model' do
        expect(config[:tier2]).to be(true)
      end
    end

    context 'with epd_5in65f' do
      subject(:config) { described_class.model_config('epd_5in65f') }

      it 'returns width 600' do
        expect(config[:width]).to eq(600)
      end

      it 'returns height 448' do
        expect(config[:height]).to eq(448)
      end

      it 'returns pixel_format :color7' do
        expect(config[:pixel_format]).to eq(:color7)
      end

      it 'is a tier2 model' do
        expect(config[:tier2]).to be(true)
      end
    end

    context 'with unknown model' do
      it 'returns nil' do
        expect(described_class.model_config('nonexistent')).to be_nil
      end
    end

    context 'with a valid config hash structure' do
      subject(:config) { described_class.model_config('epd_2in13_v4') }

      it 'contains the :name key' do
        expect(config).to have_key(:name)
      end

      it 'contains the :width key' do
        expect(config).to have_key(:width)
      end

      it 'contains the :height key' do
        expect(config).to have_key(:height)
      end

      it 'contains the :pixel_format key' do
        expect(config).to have_key(:pixel_format)
      end

      it 'contains the :busy_polarity key' do
        expect(config).to have_key(:busy_polarity)
      end

      it 'contains the :capabilities key' do
        expect(config).to have_key(:capabilities)
      end

      it 'contains the :display_cmd key' do
        expect(config).to have_key(:display_cmd)
      end

      it 'contains the :sleep_cmd key' do
        expect(config).to have_key(:sleep_cmd)
      end

      it 'contains the :tier2 key' do
        expect(config).to have_key(:tier2)
      end
    end

    context 'with capabilities as symbol arrays' do
      subject(:capabilities) { described_class.model_config('epd_2in7_v2')[:capabilities] }

      it 'is an Array' do
        expect(capabilities).to be_an(Array)
      end

      it 'contains only Symbols' do
        expect(capabilities).to all(be_a(Symbol))
      end
    end
  end
end
