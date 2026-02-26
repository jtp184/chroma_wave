# frozen_string_literal: true

require 'pathname'
require 'tempfile'
require 'stringio'
require_relative '../../../lib/chroma_wave/driver_extraction'

RSpec.describe ChromaWave::DriverExtraction::Runner do
  let(:vendor_dir) do
    Pathname.new(__dir__).join('..', '..', '..', 'vendor', 'waveshare_epd', 'lib', 'e-Paper')
  end

  let(:committed_output) do
    Pathname.new(__dir__).join('..', '..', '..', 'ext', 'chroma_wave', 'driver_configs_generated.h')
  end

  describe 'golden-file integration test' do
    it 'produces output identical to the committed header' do
      Tempfile.create(['driver_configs_test', '.h']) do |tmpfile|
        tmp_path = Pathname.new(tmpfile.path)
        run_silently(vendor_dir:, output_path: tmp_path)

        expect(tmp_path.read).to eq(committed_output.read)
      end
    end
  end

  describe '#call' do
    it 'writes a valid C header to the specified path' do
      Tempfile.create(['driver_configs_test', '.h']) do |tmpfile|
        tmp_path = Pathname.new(tmpfile.path)
        run_silently(vendor_dir:, output_path: tmp_path)

        expect(tmp_path.read).to include('#ifndef DRIVER_CONFIGS_GENERATED_H')
      end
    end

    it 'includes the config table' do
      Tempfile.create(['driver_configs_test', '.h']) do |tmpfile|
        tmp_path = Pathname.new(tmpfile.path)
        run_silently(vendor_dir:, output_path: tmp_path)

        expect(tmp_path.read).to include('epd_model_configs')
      end
    end
  end

  private

  def run_silently(vendor_dir:, output_path:)
    described_class.new(vendor_dir:, output_path:).then do |runner|
      capture_stdout { runner.call }
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
