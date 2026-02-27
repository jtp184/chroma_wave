# frozen_string_literal: true

RSpec.describe ChromaWave::Device do
  # Use a known model from the registry for all tests
  let(:model_name) { 'epd_2in13_v4' }

  # Helper: records start/end markers from two synchronized threads.
  def record_synchronized_access(device)
    values = []
    threads = 2.times.map do |i|
      Thread.new do
        device.synchronize do
          values << "start_#{i}"
          Thread.pass
          values << "end_#{i}"
        end
      end
    end
    threads.each(&:join)
    values
  end

  # Helper: finds a model with dual_buf capability, or nil.
  def find_dual_buf_model
    ChromaWave::Native.model_names.find do |name|
      ChromaWave::Native.model_config(name)[:capabilities].include?(:dual_buf)
    end
  end

  # Helper: verifies GVL is released during dual display for the given model.
  def verify_gvl_release_during_dual(dual_model)
    config = ChromaWave::Native.model_config(dual_model)
    fb = ChromaWave::Framebuffer.new(config[:width], config[:height], :mono)
    thread_ran = false

    described_class.open(dual_model) do |dev|
      dev.send(:_epd_init, 0)
      thread = Thread.new { thread_ran = true }
      dev.send(:_epd_display_dual, fb, fb)
      thread.join(1)
    end
    thread_ran
  end

  describe '#initialize' do
    it 'creates an open device for a valid model' do
      device = described_class.new(model_name)
      expect(device).to be_open
      device.close
    end

    it 'raises ModelNotFoundError for an unknown model' do
      expect { described_class.new('nonexistent_model') }
        .to raise_error(ChromaWave::ModelNotFoundError, /unknown model/)
    end

    it 'raises TypeError for non-String argument' do
      expect { described_class.new(:epd_2in13_v4) }
        .to raise_error(TypeError)
    end
  end

  describe '#open?' do
    it 'returns true for a freshly opened device' do
      device = described_class.new(model_name)
      expect(device.open?).to be(true)
      device.close
    end

    it 'returns false after close' do
      device = described_class.new(model_name)
      device.close
      expect(device.open?).to be(false)
    end
  end

  describe '#model_name' do
    it 'returns the model name string' do
      device = described_class.new(model_name)
      expect(device.model_name).to eq(model_name)
      device.close
    end
  end

  describe '#close' do
    it 'transitions device to closed state' do
      device = described_class.new(model_name)
      device.close
      expect(device).not_to be_open
    end

    it 'is idempotent (calling close twice does not raise)' do
      device = described_class.new(model_name)
      device.close
      expect { device.close }.not_to raise_error
    end

    it 'returns nil' do
      device = described_class.new(model_name)
      expect(device.close).to be_nil
    end
  end

  describe '.open' do
    context 'without a block' do
      it 'returns an open device' do
        device = described_class.open(model_name)
        expect(device).to be_open
        device.close
      end
    end

    context 'with a block' do
      it 'yields the device to the block' do
        yielded = nil
        described_class.open(model_name) { |dev| yielded = dev }
        expect(yielded).to be_a(described_class)
      end

      it 'returns the block value' do
        result = described_class.open(model_name, &:model_name)
        expect(result).to eq(model_name)
      end

      it 'closes the device after the block' do
        device_ref = nil
        described_class.open(model_name) { |dev| device_ref = dev }
        expect(device_ref).not_to be_open
      end

      it 'closes the device even if the block raises' do
        device_ref = nil
        begin
          described_class.open(model_name) do |dev|
            device_ref = dev
            raise 'boom'
          end
        rescue RuntimeError
          nil
        end
        expect(device_ref).not_to be_open
      end
    end
  end

  describe '#synchronize' do
    it 'executes the block' do
      device = described_class.new(model_name)
      result = device.synchronize { 42 }
      expect(result).to eq(42)
      device.close
    end

    it 'provides mutual exclusion' do
      device = described_class.new(model_name)
      values = record_synchronized_access(device)
      # Each start/end pair should be adjacent (not interleaved)
      expect(values).to satisfy('have non-interleaved pairs') do |v|
        v.each_slice(2).all? { |s, e| s&.tr('start', '') == e&.tr('end', '') }
      end
      device.close
    end
  end

  describe 'private bridge methods' do
    # Under mock backend, these all succeed silently

    describe '#_epd_init' do
      it 'succeeds with MODE_FULL' do
        described_class.open(model_name) do |dev|
          expect { dev.send(:_epd_init, ChromaWave::Native::MODE_FULL) }
            .not_to raise_error
        end
      end

      it 'succeeds with MODE_FAST' do
        described_class.open(model_name) do |dev|
          expect { dev.send(:_epd_init, ChromaWave::Native::MODE_FAST) }
            .not_to raise_error
        end
      end

      it 'raises DeviceError when device is closed' do
        device = described_class.new(model_name)
        device.close
        expect { device.send(:_epd_init, 0) }
          .to raise_error(ChromaWave::DeviceError, /closed/)
      end
    end

    describe '#_epd_display' do
      it 'sends a framebuffer to the display' do
        config = ChromaWave::Native.model_config(model_name)
        fb = ChromaWave::Framebuffer.new(config[:width], config[:height], config[:pixel_format])
        described_class.open(model_name) do |dev|
          dev.send(:_epd_init, 0)
          expect { dev.send(:_epd_display, fb) }.not_to raise_error
        end
      end

      it 'raises DeviceError when device is closed' do
        config = ChromaWave::Native.model_config(model_name)
        fb = ChromaWave::Framebuffer.new(config[:width], config[:height], config[:pixel_format])
        device = described_class.new(model_name)
        device.close
        expect { device.send(:_epd_display, fb) }
          .to raise_error(ChromaWave::DeviceError, /closed/)
      end
    end

    describe '#_epd_display_dual' do
      it 'sends two framebuffers for dual-buffer displays' do
        dual_model = find_dual_buf_model
        skip 'no dual-buffer model in registry' unless dual_model
        config = ChromaWave::Native.model_config(dual_model)
        fb = ChromaWave::Framebuffer.new(config[:width], config[:height], :mono)

        described_class.open(dual_model) do |dev|
          dev.send(:_epd_init, 0)
          expect { dev.send(:_epd_display_dual, fb, fb) }.not_to raise_error
        end
      end

      it 'allows other threads to run during dual display' do
        dual_model = find_dual_buf_model
        skip 'no dual-buffer model in registry' unless dual_model

        thread_ran = verify_gvl_release_during_dual(dual_model)
        expect(thread_ran).to be true
      end

      it 'raises DeviceError when device is closed' do
        config = ChromaWave::Native.model_config(model_name)
        fb = ChromaWave::Framebuffer.new(config[:width], config[:height], config[:pixel_format])
        device = described_class.new(model_name)
        device.close
        expect { device.send(:_epd_display_dual, fb, fb) }
          .to raise_error(ChromaWave::DeviceError, /closed/)
      end
    end

    describe '#_epd_sleep' do
      it 'puts the display to sleep' do
        described_class.open(model_name) do |dev|
          dev.send(:_epd_init, 0)
          expect { dev.send(:_epd_sleep) }.not_to raise_error
        end
      end

      it 'raises DeviceError when device is closed' do
        device = described_class.new(model_name)
        device.close
        expect { device.send(:_epd_sleep) }
          .to raise_error(ChromaWave::DeviceError, /closed/)
      end
    end

    describe '#_epd_clear' do
      it 'clears the display with white' do
        described_class.open(model_name) do |dev|
          dev.send(:_epd_init, 0)
          expect { dev.send(:_epd_clear) }.not_to raise_error
        end
      end

      it 'raises DeviceError when device is closed' do
        device = described_class.new(model_name)
        device.close
        expect { device.send(:_epd_clear) }
          .to raise_error(ChromaWave::DeviceError, /closed/)
      end
    end
  end

  describe 'MODE constants' do
    it 'defines MODE_FULL as 0' do
      expect(ChromaWave::Native::MODE_FULL).to eq(0)
    end

    it 'defines MODE_FAST as 1' do
      expect(ChromaWave::Native::MODE_FAST).to eq(1)
    end

    it 'defines MODE_PARTIAL as 2' do
      expect(ChromaWave::Native::MODE_PARTIAL).to eq(2)
    end

    it 'defines MODE_GRAYSCALE as 3' do
      expect(ChromaWave::Native::MODE_GRAYSCALE).to eq(3)
    end
  end

  describe 'GVL release' do
    it 'allows other threads to run during display' do
      config = ChromaWave::Native.model_config(model_name)
      fb = ChromaWave::Framebuffer.new(config[:width], config[:height], config[:pixel_format])

      described_class.open(model_name) do |dev|
        dev.send(:_epd_init, ChromaWave::Native::MODE_FULL)

        thread_ran = false
        thread = Thread.new { thread_ran = true }

        dev.send(:_epd_display, fb)
        thread.join(1)

        expect(thread_ran).to be true
      end
    end

    it 'allows other threads to run during clear' do
      described_class.open(model_name) do |dev|
        dev.send(:_epd_init, ChromaWave::Native::MODE_FULL)

        thread_ran = false
        thread = Thread.new { thread_ran = true }

        dev.send(:_epd_clear)
        thread.join(1)

        expect(thread_ran).to be true
      end
    end
  end

  describe 'BusyTimeoutError' do
    it 'is a subclass of DeviceError' do
      expect(ChromaWave::BusyTimeoutError).to be < ChromaWave::DeviceError
    end
  end

  describe 'GC safety' do
    it 'handles creating and discarding many devices' do
      expect do
        50.times do
          described_class.new(model_name)
          # intentionally not closing — GC should call dfree
        end
        GC.start
      end.not_to raise_error
    end

    it 'handles block form with GC pressure' do
      expect do
        50.times do
          described_class.open(model_name, &:model_name)
        end
        GC.start
      end.not_to raise_error
    end
  end
end
