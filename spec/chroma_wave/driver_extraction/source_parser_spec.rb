# frozen_string_literal: true

require 'pathname'
require 'tempfile'
require_relative '../../../lib/chroma_wave/driver_extraction'

RSpec.describe ChromaWave::DriverExtraction::SourceParser do
  let(:vendor_dir) { Pathname.new(__dir__).join('..', '..', '..', 'vendor', 'waveshare_epd', 'lib', 'e-Paper') }
  let(:seq_end) { ChromaWave::DriverExtraction::Opcodes::SEQ_END }
  let(:seq_sw_reset) { ChromaWave::DriverExtraction::Opcodes::SEQ_SW_RESET }

  def parse_vendor(name)
    described_class.new(vendor_dir.join("#{name}.h"), vendor_dir.join("#{name}.c")).parse
  end

  describe '#parse with real vendor fixtures' do
    context 'with EPD_2in13_V4 (SSD1680 baseline)' do
      subject(:config) { parse_vendor('EPD_2in13_V4') }

      it 'extracts width' do
        expect(config.width).to eq(122)
      end

      it 'extracts height' do
        expect(config.height).to eq(250)
      end

      it 'detects mono pixel format' do
        expect(config.pixel_format).to eq(:mono)
      end

      it 'detects active_high busy polarity' do
        expect(config.busy_polarity).to eq(:active_high)
      end

      it 'detects fast capability' do
        expect(config.capabilities).to include(:fast)
      end

      it 'detects partial capability' do
        expect(config.capabilities).to include(:partial)
      end

      it 'extracts init sequence terminated by SEQ_END' do
        expect(config.init_sequence&.last).to eq(seq_end)
      end

      it 'extracts fast init sequence' do
        expect(config.init_fast_sequence).not_to be_nil
      end

      it 'is not tier2' do
        expect(config.tier2_reason).to be_nil
      end
    end

    context 'with EPD_2in13b_V4 (color4 suffix)' do
      subject(:config) { parse_vendor('EPD_2in13b_V4') }

      it 'detects color4 pixel format from name suffix' do
        expect(config.pixel_format).to eq(:color4)
      end

      it 'extracts width' do
        expect(config.width).to eq(122)
      end

      it 'extracts height' do
        expect(config.height).to eq(250)
      end
    end

    context 'with EPD_5in65f (color7, tier2 explicit)' do
      subject(:config) { parse_vendor('EPD_5in65f') }

      it 'detects color7 pixel format' do
        expect(config.pixel_format).to eq(:color7)
      end

      it 'is tier2 with expected reason' do
        expect(config.tier2_reason).to eq('Power cycling per refresh, dual busy polarity')
      end

      it 'extracts width' do
        expect(config.width).to eq(600)
      end

      it 'extracts height' do
        expect(config.height).to eq(448)
      end
    end

    context 'with EPD_7in3f (color7 via name pattern)' do
      subject(:config) { parse_vendor('EPD_7in3f') }

      it 'detects color7 pixel format' do
        expect(config.pixel_format).to eq(:color7)
      end

      it 'has nonzero width' do
        expect(config.width).to be > 0
      end

      it 'has nonzero height' do
        expect(config.height).to be > 0
      end
    end

    context 'with EPD_4in2 (tier2 via TIER2_MODELS)' do
      subject(:config) { parse_vendor('EPD_4in2') }

      it 'is tier2 with LUT selection reason' do
        expect(config.tier2_reason).to eq('LUT selection in init')
      end

      it 'warns about missing init sequence' do
        expect(config.warnings).to include('Could not extract init sequence')
      end

      it 'detects grayscale capability' do
        expect(config.capabilities).to include(:grayscale)
      end
    end

    context 'with EPD_1in02d (tier2, unusual protocol)' do
      subject(:config) { parse_vendor('EPD_1in02d') }

      it 'is tier2 with unusual protocol reason' do
        expect(config.tier2_reason).to eq('Unusual protocol, LUT-based, non-standard busy')
      end

      it 'extracts init sequence despite complexity' do
        expect(config.init_sequence).not_to be_nil
      end
    end
  end

  describe 'synthetic C parsing' do
    subject(:config) { described_class.new(h_path, c_path).parse }

    let(:tmp_dir) { Pathname.new(Dir.tmpdir) }
    let(:h_path) { tmp_dir.join('EPD_test.h') }
    let(:c_path) { tmp_dir.join('EPD_test.c') }
    let(:h_content) { "#define EPD_TEST_WIDTH 100\n#define EPD_TEST_HEIGHT 200\n" }
    let(:busy_fn) { busy_body('DEV_Digital_Read(EPD_BUSY_PIN) == 0') }

    let(:c_content) do
      <<~C
        void EPD_TEST_ReadBusy(void) {
          #{busy_fn}
        }
        void EPD_TEST_Sleep(void) {
          SendCommand(0x10);
          SendData(0x01);
        }
      C
    end

    before do
      h_path.write(h_content)
      c_path.write(c_content)
    end

    after do
      h_path.delete if h_path.exist?
      c_path.delete if c_path.exist?
    end

    context 'with active_high busy pattern (== 0)' do
      let(:busy_fn) { busy_body('DEV_Digital_Read(EPD_BUSY_PIN) == 0') }

      it 'detects active_high busy polarity' do
        expect(config.busy_polarity).to eq(:active_high)
      end
    end

    context 'with active_low busy pattern (== 1)' do
      let(:busy_fn) { busy_body('DEV_Digital_Read(EPD_BUSY_PIN) == 1') }

      it 'detects active_low busy polarity' do
        expect(config.busy_polarity).to eq(:active_low)
      end
    end

    context 'with 3-delay reset timing' do
      let(:c_content) do
        <<~C
          void EPD_TEST_Reset(void) {
            DEV_Digital_Write(EPD_RST_PIN, 1);
            DEV_Delay_ms(20);
            DEV_Digital_Write(EPD_RST_PIN, 0);
            DEV_Delay_ms(2);
            DEV_Digital_Write(EPD_RST_PIN, 1);
            DEV_Delay_ms(20);
          }
          #{default_busy_and_sleep}
        C
      end

      it 'extracts three-delay reset timing' do
        expect(config.reset_ms).to eq([20, 2, 20])
      end
    end

    context 'with 2-delay reset timing' do
      let(:c_content) do
        <<~C
          void EPD_TEST_Reset(void) {
            DEV_Digital_Write(EPD_RST_PIN, 0);
            DEV_Delay_ms(10);
            DEV_Digital_Write(EPD_RST_PIN, 1);
            DEV_Delay_ms(10);
          }
          #{default_busy_and_sleep}
        C
      end

      it 'pads with leading zero' do
        expect(config.reset_ms).to eq([0, 10, 10])
      end
    end

    context 'with plain model name (no color suffix)' do
      it 'detects mono pixel format' do
        expect(config.pixel_format).to eq(:mono)
      end
    end

    context 'with 0x12 command followed by ReadBusy' do
      let(:c_content) do
        <<~C
          void EPD_TEST_Init(void) {
            SendCommand(0x12);
            EPD_TEST_ReadBusy();
            SendCommand(0x01);
            SendData(0x03);
          }
          #{default_busy_and_sleep}
        C
      end

      it 'encodes 0x12 as SEQ_SW_RESET' do
        expect(config.init_sequence).to include(seq_sw_reset)
      end
    end
  end

  private

  def busy_body(condition)
    "while(#{condition}) { DEV_Delay_ms(10); }"
  end

  def default_busy_and_sleep
    <<~C
      void EPD_TEST_ReadBusy(void) {
        while(DEV_Digital_Read(EPD_BUSY_PIN) == 0) {}
      }
      void EPD_TEST_Sleep(void) {
        SendCommand(0x10);
        SendData(0x01);
      }
    C
  end
end
