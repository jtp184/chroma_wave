# frozen_string_literal: true

RSpec.describe ChromaWave::Capabilities::ManagedRefresh do
  # epd_2in13_v4: mono, 122x250, has :partial, :fast, :dual_buf
  let(:model) { :epd_2in13_v4 }

  # epd_2in7_v2: mono, 176x264, has :partial, :fast, :grayscale, :regional
  let(:regional_model) { :epd_2in7_v2 }

  after { display&.close }

  def make_framebuffer(disp)
    ChromaWave::Framebuffer.new(disp.native_width, disp.native_height, disp.pixel_format)
  end

  def make_canvas(disp)
    ChromaWave::Canvas.new(width: disp.width, height: disp.height)
  end

  describe 'opt-in behavior' do
    context 'when managed_refresh is not set' do
      let(:display) { ChromaWave::MockDevice.new(model: model) }

      it 'does not have a refresh_scheduler' do
        expect(display).not_to respond_to(:refresh_scheduler)
      end

      it 'is not extended with ManagedRefresh' do
        expect(display).not_to be_a(described_class)
      end
    end

    context 'when managed_refresh: true' do
      let(:display) { ChromaWave::MockDevice.new(model: model, managed_refresh: true) }

      it 'has a refresh_scheduler' do
        expect(display.refresh_scheduler).to be_a(ChromaWave::RefreshScheduler)
      end

      it 'is extended with ManagedRefresh' do
        expect(display).to be_a(described_class)
      end

      it 'uses default scheduler options' do
        expect(display.refresh_scheduler.partial_limit).to eq(5)
        expect(display.refresh_scheduler.min_interval).to eq(180)
        expect(display.refresh_scheduler.auto_full_refresh?).to be true
      end
    end

    context 'when managed_refresh: { ... } with custom options' do
      let(:display) do
        ChromaWave::MockDevice.new(
          model: model,
          managed_refresh: { partial_limit: 10, min_interval: 60, auto_full_refresh: false }
        )
      end

      it 'uses custom scheduler options' do
        expect(display.refresh_scheduler.partial_limit).to eq(10)
        expect(display.refresh_scheduler.min_interval).to eq(60)
        expect(display.refresh_scheduler.auto_full_refresh?).to be false
      end
    end

    context 'when managed_refresh: is an invalid truthy value' do
      it 'raises ArgumentError for a Symbol' do
        expect { ChromaWave::MockDevice.new(model: model, managed_refresh: :defaults) }
          .to raise_error(ArgumentError, /managed_refresh must be true or a Hash/)
      end

      it 'raises ArgumentError for a String' do
        expect { ChromaWave::MockDevice.new(model: model, managed_refresh: 'yes') }
          .to raise_error(ArgumentError, /managed_refresh must be true or a Hash/)
      end
    end

    context 'when managed_refresh is set on a COLOR4 display' do
      it 'raises ArgumentError' do
        expect { ChromaWave::MockDevice.new(model: :epd_2in9b_v4, managed_refresh: true) }
          .to raise_error(ArgumentError, /COLOR4/)
      end
    end
  end

  describe 'partial tracking' do
    let(:display) do
      ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 0 })
    end

    it 'increments counter on display_partial' do
      fb = make_framebuffer(display)
      display.display_partial(fb)
      expect(display.refresh_scheduler.partial_count).to eq(1)
    end

    it 'increments counter on display_fast' do
      fb = make_framebuffer(display)
      display.display_fast(fb)
      expect(display.refresh_scheduler.partial_count).to eq(1)
    end

    it 'accumulates across multiple partial calls' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }
      expect(display.refresh_scheduler.partial_count).to eq(3)
    end

    it 'accumulates mixed partial and fast calls' do
      fb = make_framebuffer(display)
      display.display_partial(fb)
      display.display_fast(fb)
      display.display_partial(fb)
      expect(display.refresh_scheduler.partial_count).to eq(3)
    end
  end

  describe 'full refresh tracking' do
    let(:display) do
      ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 0 })
    end

    it 'resets counter on show' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }
      display.show(fb)
      expect(display.refresh_scheduler.partial_count).to eq(0)
    end

    it 'resets counter on clear' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }
      display.clear
      expect(display.refresh_scheduler.partial_count).to eq(0)
    end

    it 'resets counter on display_base' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }
      display.display_base(fb)
      expect(display.refresh_scheduler.partial_count).to eq(0)
    end
  end

  describe 'grayscale tracking' do
    let(:display) do
      ChromaWave::MockDevice.new(model: regional_model, managed_refresh: { min_interval: 0 })
    end

    it 'resets counter on display_grayscale' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }
      display.display_grayscale(fb)
      expect(display.refresh_scheduler.partial_count).to eq(0)
    end

    it 'resumes accumulating partials after grayscale reset' do
      fb = make_framebuffer(display)
      2.times { display.display_partial(fb) }
      display.display_grayscale(fb)
      expect(display.refresh_scheduler.partial_count).to eq(0)

      2.times { display.display_partial(fb) }
      expect(display.refresh_scheduler.partial_count).to eq(2)
    end
  end

  describe 'regional refresh tracking' do
    let(:display) do
      ChromaWave::MockDevice.new(model: regional_model, managed_refresh: { min_interval: 0 })
    end

    it 'increments counter on display_region' do
      fb = make_framebuffer(display)
      display.display_region(fb, x: 0, y: 0, width: 8, height: 8)
      expect(display.refresh_scheduler.partial_count).to eq(1)
    end

    context 'when past partial_limit' do
      let(:display) do
        ChromaWave::MockDevice.new(
          model: regional_model,
          managed_refresh: { partial_limit: 2, min_interval: 0 }
        )
      end

      before do
        fb = make_framebuffer(display)
        display.display_region(fb, x: 0, y: 0, width: 8, height: 8)
        display.clear_operations!
        2.times { display.display_region(fb, x: 0, y: 0, width: 8, height: 8) }
      end

      it 'does not trigger auto-full-refresh' do
        expect(display.operations(:init)).to be_empty
      end

      it 'still increments partial count' do
        expect(display.refresh_scheduler.partial_count).to eq(3)
      end
    end
  end

  describe 'auto-full-refresh' do
    let(:display) do
      ChromaWave::MockDevice.new(
        model: model,
        managed_refresh: { partial_limit: 3, min_interval: 0 }
      )
    end

    it 'triggers a full refresh when partial limit is reached' do
      fb = make_framebuffer(display)

      # First 2 partials — no auto-refresh (count goes 1, 2)
      2.times { display.display_partial(fb) }
      expect(display.refresh_scheduler.partial_count).to eq(2)

      # 3rd partial: track_partial! → count=3, needs_full? → true, auto-refresh fires
      display.clear_operations!
      display.display_partial(fb)

      init_ops = display.operations(:init)
      init_modes = init_ops.map { |o| o[:mode] }
      expect(init_modes).to include(:full)
    end

    it 'resets counter after auto-full-refresh' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }

      # 3rd call: super, track_partial!(count=3), auto-refresh(track_full! → count=0)
      expect(display.refresh_scheduler.partial_count).to eq(0)
    end

    it 'shows partial init then full init in operation log' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }

      init_ops = display.operations(:init)
      init_modes = init_ops.map { |o| o[:mode] }

      # 1st partial inits partial mode, 2nd reuses it (no re-init),
      # 3rd displays partial then auto-full-refresh triggers full init
      expect(init_modes).to eq(%i[partial full])
    end

    context 'when auto_full_refresh is disabled' do
      let(:display) do
        ChromaWave::MockDevice.new(
          model: model,
          managed_refresh: { partial_limit: 3, min_interval: 0, auto_full_refresh: false }
        )
      end

      it 'does not trigger a full refresh at the limit' do
        fb = make_framebuffer(display)
        5.times { display.display_partial(fb) }

        init_ops = display.operations(:init)
        init_modes = init_ops.map { |o| o[:mode] }
        expect(init_modes).to eq([:partial])
      end

      it 'continues incrementing the partial count past the limit' do
        fb = make_framebuffer(display)
        5.times { display.display_partial(fb) }
        expect(display.refresh_scheduler.partial_count).to eq(5)
      end
    end
  end

  describe 'auto-full-refresh with display_fast' do
    let(:display) do
      ChromaWave::MockDevice.new(
        model: model,
        managed_refresh: { partial_limit: 2, min_interval: 0 }
      )
    end

    it 'triggers a full refresh when fast refresh hits the limit' do
      fb = make_framebuffer(display)
      display.display_fast(fb) # count=1
      display.clear_operations!
      display.display_fast(fb) # count=2 → triggers auto-refresh

      init_ops = display.operations(:init)
      init_modes = init_ops.map { |o| o[:mode] }
      expect(init_modes).to include(:full)
    end
  end

  describe 'auto-full-refresh failure resilience' do
    let(:display) do
      ChromaWave::MockDevice.new(
        model: model,
        managed_refresh: { partial_limit: 2, min_interval: 0 }
      )
    end

    it 'warns and resets counter when force_full_refresh! fails' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # count=1

      # Stub force_full_refresh! to simulate hardware failure during auto-refresh
      allow(display).to receive(:force_full_refresh!)
        .and_raise(ChromaWave::DeviceError, 'hardware fault')

      expect { display.display_partial(fb) } # count=2 → triggers auto-refresh → fails
        .to output(/Auto-full-refresh failed/).to_stderr
      expect(display.refresh_scheduler.partial_count).to eq(0)
    end

    it 'does not raise to the caller when auto-refresh fails' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # count=1

      allow(display).to receive(:force_full_refresh!)
        .and_raise(ChromaWave::DeviceError, 'hardware fault')

      expect { display.display_partial(fb) }.not_to raise_error
    end
  end

  describe 'interval warning' do
    let(:display) do
      ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 9999 })
    end

    it 'warns when refreshing too fast' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # sets last_refresh_at

      expect { display.display_partial(fb) }
        .to output(/Refresh interval too short/).to_stderr
    end

    it 'warns on show after a recent refresh' do
      fb = make_framebuffer(display)
      display.show(fb)

      expect { display.show(fb) }
        .to output(/Refresh interval too short/).to_stderr
    end

    it 'does not warn on the first refresh' do
      fb = make_framebuffer(display)

      expect { display.display_partial(fb) }
        .not_to output.to_stderr
    end

    context 'with min_interval: 0' do
      let(:display) do
        ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 0 })
      end

      it 'never warns' do
        fb = make_framebuffer(display)
        display.display_partial(fb)

        expect { display.display_partial(fb) }
          .not_to output.to_stderr
      end
    end
  end

  describe 'return values' do
    let(:display) do
      ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 0 })
    end

    it 'display_partial returns self' do
      fb = make_framebuffer(display)
      expect(display.display_partial(fb)).to eq(display)
    end

    it 'display_fast returns self' do
      fb = make_framebuffer(display)
      expect(display.display_fast(fb)).to eq(display)
    end

    it 'show returns self' do
      canvas = make_canvas(display)
      expect(display.show(canvas)).to eq(display)
    end

    it 'clear returns self' do
      expect(display.clear).to eq(display)
    end

    it 'display_base returns self' do
      fb = make_framebuffer(display)
      expect(display.display_base(fb)).to eq(display)
    end

    it 'display_grayscale returns self' do
      disp = ChromaWave::MockDevice.new(model: regional_model, managed_refresh: { min_interval: 0 })
      fb = make_framebuffer(disp)
      expect(disp.display_grayscale(fb)).to eq(disp)
    ensure
      disp&.close
    end

    it 'display_region returns self' do
      disp = ChromaWave::MockDevice.new(model: regional_model, managed_refresh: { min_interval: 0 })
      fb = make_framebuffer(disp)
      expect(disp.display_region(fb, x: 0, y: 0, width: 8, height: 8)).to eq(disp)
    ensure
      disp&.close
    end
  end

  describe 'thread safety' do
    let(:display) do
      ChromaWave::MockDevice.new(
        model: model,
        managed_refresh: { partial_limit: 1000, min_interval: 0 }
      )
    end

    it 'handles concurrent display_partial calls without corrupting the counter' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # warm up

      threads = 10.times.map do
        Thread.new { 10.times { display.display_partial(fb) } }
      end
      threads.each(&:join)

      # 10 threads * 10 calls + 1 warmup = 101
      expect(display.refresh_scheduler.partial_count).to eq(101)
    end
  end

  describe '.open with managed_refresh' do
    # Uses block form — no need for the shared `after { display.close }`
    let(:display) { nil }

    it 'passes managed_refresh through' do
      ChromaWave::MockDevice.open(model: model, managed_refresh: true) do |mock|
        expect(mock.refresh_scheduler).to be_a(ChromaWave::RefreshScheduler)
      end
    end
  end

  describe 'error propagation preserves scheduler state' do
    let(:display) do
      ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 0 })
    end

    it 'does not increment partial count when display_partial raises' do
      fb = make_framebuffer(display)
      display.display_partial(fb) # warm up, count=1

      device_stub = display.send(:device)
      allow(device_stub).to receive(:_epd_display).and_raise(ChromaWave::DeviceError, 'simulated failure')

      expect { display.display_partial(fb) }.to raise_error(ChromaWave::DeviceError)
      expect(display.refresh_scheduler.partial_count).to eq(1)
    end

    it 'does not reset partial count when show raises' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }

      device_stub = display.send(:device)
      allow(device_stub).to receive(:_epd_display).and_raise(ChromaWave::DeviceError, 'simulated failure')

      expect { display.show(fb) }.to raise_error(ChromaWave::DeviceError)
      expect(display.refresh_scheduler.partial_count).to eq(3)
    end

    it 'does not reset partial count when clear raises' do
      fb = make_framebuffer(display)
      3.times { display.display_partial(fb) }

      device_stub = display.send(:device)
      allow(device_stub).to receive(:_epd_clear).and_raise(ChromaWave::DeviceError, 'simulated failure')

      expect { display.clear }.to raise_error(ChromaWave::DeviceError)
      expect(display.refresh_scheduler.partial_count).to eq(3)
    end
  end

  describe 'Layout handling in show' do
    let(:display) do
      ChromaWave::MockDevice.new(model: model, managed_refresh: { min_interval: 0 })
    end

    it 'tracks Layout show as a single full refresh (no double tracking)' do
      layout = ChromaWave::Layout.build(width: display.width, height: display.height) {} # rubocop:disable Lint/EmptyBlock
      display.show(layout)
      expect(display.refresh_scheduler.partial_count).to eq(0)
      expect(display.refresh_scheduler.last_refresh_at).not_to be_nil
    end
  end
end
