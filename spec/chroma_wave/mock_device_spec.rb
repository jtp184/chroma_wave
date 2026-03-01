# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe ChromaWave::MockDevice do
  let(:model) { :epd_2in13_v4 }
  let(:config) { ChromaWave::Native.model_config(model.to_s) }

  describe '.new' do
    it 'returns a Display subclass instance' do
      mock = described_class.new(model: model)
      expect(mock).to be_a(ChromaWave::Display)
      mock.close
    end

    it 'returns a MockDevice subclass instance' do
      mock = described_class.new(model: model)
      expect(mock).to be_a(described_class)
      mock.close
    end

    it 'sets the model as a symbol' do
      mock = described_class.new(model: model)
      expect(mock.model).to eq(:epd_2in13_v4)
      mock.close
    end

    it 'sets correct dimensions from config' do
      mock = described_class.new(model: model)
      expect(mock.width).to eq(config[:width])
      expect(mock.height).to eq(config[:height])
      mock.close
    end

    it 'sets the pixel format from config' do
      mock = described_class.new(model: model)
      expect(mock.pixel_format).to eq(ChromaWave::PixelFormat::MONO)
      mock.close
    end

    it 'accepts a string model name' do
      mock = described_class.new(model: 'epd_2in13_v4')
      expect(mock.model).to eq(:epd_2in13_v4)
      mock.close
    end

    it 'raises ModelNotFoundError for unknown model' do
      expect { described_class.new(model: :nonexistent_model) }
        .to raise_error(ChromaWave::ModelNotFoundError, /unknown model/)
    end

    it 'raises ArgumentError when model is omitted' do
      expect { described_class.new }
        .to raise_error(ArgumentError, /missing keyword/)
    end

    it 'raises ArgumentError for unknown keywords' do
      expect { described_class.new(model: model, bogus: true) }
        .to raise_error(ArgumentError, /unknown keyword/)
    end

    it 'defaults busy_duration to 0' do
      mock = described_class.new(model: model)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.show(fb) # warm up lazy init
      mock.clear_operations!
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      mock.show(fb)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.05
      mock.close
    end
  end

  describe '.open' do
    context 'without a block' do
      it 'returns a MockDevice' do
        mock = described_class.open(model: model)
        expect(mock).to be_a(described_class)
        mock.close
      end
    end

    context 'with a block' do
      it 'yields the mock device' do
        yielded = nil
        described_class.open(model: model) { |m| yielded = m }
        expect(yielded).to be_a(described_class)
      end

      it 'returns the block value' do
        result = described_class.open(model: model, &:model)
        expect(result).to eq(:epd_2in13_v4)
      end

      it 'closes the mock after the block' do
        ops = nil
        described_class.open(model: model) do |m|
          m.show(make_canvas(m))
          ops = m.operations.map { |o| o[:op] }
        end
        expect(ops).to include(:show)
      end

      it 'closes even if the block raises' do
        mock_ref = nil
        begin
          described_class.open(model: model) do |m|
            mock_ref = m
            raise 'boom'
          end
        rescue RuntimeError
          nil
        end
        # After close, the close operation should be logged
        expect(mock_ref.operations.map { |o| o[:op] }).to include(:close)
      end
    end
  end

  describe 'capability inclusion' do
    it 'includes PartialRefresh for models with :partial' do
      mock = described_class.new(model: :epd_2in13_v4)
      expect(mock).to be_a(ChromaWave::Capabilities::PartialRefresh)
      expect(mock).to respond_to(:display_partial)
      mock.close
    end

    it 'includes FastRefresh for models with :fast' do
      mock = described_class.new(model: :epd_2in13_v4)
      expect(mock).to be_a(ChromaWave::Capabilities::FastRefresh)
      expect(mock).to respond_to(:display_fast)
      mock.close
    end

    it 'includes DualBuffer for models with :dual_buf' do
      mock = described_class.new(model: :epd_2in13_v4)
      expect(mock).to be_a(ChromaWave::Capabilities::DualBuffer)
      expect(mock).to respond_to(:show_raw)
      mock.close
    end

    it 'includes GrayscaleMode for models with :grayscale' do
      mock = described_class.new(model: :epd_2in7_v2)
      expect(mock).to be_a(ChromaWave::Capabilities::GrayscaleMode)
      expect(mock).to respond_to(:display_grayscale)
      mock.close
    end

    it 'includes RegionalRefresh for models with :regional' do
      mock = described_class.new(model: :epd_2in7_v2)
      expect(mock).to be_a(ChromaWave::Capabilities::RegionalRefresh)
      expect(mock).to respond_to(:display_region)
      mock.close
    end
  end

  describe 'operation logging' do
    it 'logs :init and :show on first show' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      ops = mock.operations.map { |o| o[:op] }
      expect(ops).to eq(%i[init show])
      mock.close
    end

    it 'logs :clear' do
      mock = described_class.new(model: model)
      mock.clear
      expect(mock.operations.last[:op]).to eq(:clear)
      expect(mock.operations.last[:color]).to eq(:white)
      mock.close
    end

    it 'logs :sleep on deep_sleep' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock)) # force init
      mock.deep_sleep
      expect(mock.operations.map { |o| o[:op] }).to include(:sleep)
      mock.close
    end

    it 'logs :close' do
      mock = described_class.new(model: model)
      mock.close
      expect(mock.operations.map { |o| o[:op] }).to include(:close)
    end

    it 'includes timestamps in each operation' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      mock.operations.each do |op|
        expect(op[:timestamp]).to be_a(Time)
      end
      mock.close
    end

    it 'logs init mode correctly' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      init_op = mock.operations(:init).first
      expect(init_op[:mode]).to eq(:full)
      expect(init_op[:model]).to eq(:epd_2in13_v4)
      mock.close
    end

    it 'logs show buffer bytes' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      show_op = mock.operations(:show).first
      expect(show_op[:buffer_bytes]).to be_a(Integer)
      expect(show_op[:buffer_bytes]).to be_positive
      mock.close
    end
  end

  describe '#operations' do
    it 'returns all operations when no type given' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      mock.clear
      expect(mock.operations.size).to eq(3) # init + show + clear (clear triggers init if needed)
      mock.close
    end

    it 'filters by type' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      mock.clear
      expect(mock.operations(:show).size).to eq(1)
      expect(mock.operations(:clear).size).to eq(1)
      mock.close
    end

    it 'returns a copy (not the internal array)' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      ops = mock.operations
      ops.clear
      expect(mock.operations.size).to eq(2)
      mock.close
    end
  end

  describe '#last_operation' do
    it 'returns nil before any operations' do
      mock = described_class.new(model: model)
      expect(mock.last_operation).to be_nil
      mock.close
    end

    it 'returns the most recent operation' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      expect(mock.last_operation[:op]).to eq(:show)
      mock.close
    end
  end

  describe '#operation_count' do
    it 'counts all operations' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      mock.clear
      expect(mock.operation_count).to eq(3)
      mock.close
    end

    it 'counts by type' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      mock.show(make_canvas(mock))
      expect(mock.operation_count(:show)).to eq(2)
      expect(mock.operation_count(:init)).to eq(1)
      mock.close
    end
  end

  describe '#clear_operations!' do
    it 'empties the operation log' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      mock.clear_operations!
      expect(mock.operations).to be_empty
      mock.close
    end

    it 'returns self for chaining' do
      mock = described_class.new(model: model)
      expect(mock.clear_operations!).to eq(mock)
      mock.close
    end
  end

  describe '#last_framebuffer' do
    it 'is nil before any show' do
      mock = described_class.new(model: model)
      expect(mock.last_framebuffer).to be_nil
      mock.close
    end

    it 'is populated after show' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      expect(mock.last_framebuffer).to be_a(ChromaWave::Framebuffer)
      mock.close
    end

    it 'has correct dimensions' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      fb = mock.last_framebuffer
      expect(fb.width).to eq(mock.width)
      expect(fb.height).to eq(mock.height)
      mock.close
    end

    it 'returns a dup (not the internal reference)' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      fb1 = mock.last_framebuffer
      fb2 = mock.last_framebuffer
      expect(fb1).not_to equal(fb2)
      expect(fb1).to eq(fb2)
      mock.close
    end
  end

  describe 'capability dispatch' do
    it 'logs partial refresh init and show' do
      mock = described_class.new(model: model)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.display_partial(fb)
      ops = mock.operations.map { |o| o[:op] }
      expect(ops).to eq(%i[init show])
      init_op = mock.operations(:init).first
      expect(init_op[:mode]).to eq(:partial)
      mock.close
    end

    it 'logs fast refresh init and show' do
      mock = described_class.new(model: model)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.display_fast(fb)
      ops = mock.operations.map { |o| o[:op] }
      expect(ops).to eq(%i[init show])
      init_op = mock.operations(:init).first
      expect(init_op[:mode]).to eq(:fast)
      mock.close
    end

    it 'logs grayscale init and show' do
      mock = described_class.new(model: :epd_2in7_v2)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.display_grayscale(fb)
      ops = mock.operations.map { |o| o[:op] }
      expect(ops).to eq(%i[init show])
      init_op = mock.operations(:init).first
      expect(init_op[:mode]).to eq(:grayscale)
      mock.close
    end

    it 'logs DualBuffer show_dual for COLOR4 Canvas' do
      mock = described_class.new(model: :epd_13in3b)
      canvas = ChromaWave::Canvas.new(width: mock.width, height: mock.height)
      mock.show(canvas)
      expect(mock.operations(:show_dual).size).to eq(1)
      dual_op = mock.operations(:show_dual).first
      expect(dual_op[:black_bytes]).to be_a(Integer)
      expect(dual_op[:red_bytes]).to be_a(Integer)
      mock.close
    end

    it 'logs display_region with coordinates' do
      mock = described_class.new(model: :epd_2in7_v2)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.display_region(fb, x: 8, y: 10, width: 64, height: 32)
      region_op = mock.operations(:show_region).first
      expect(region_op[:x]).to eq(8)
      expect(region_op[:y]).to eq(10)
      expect(region_op[:width]).to eq(64)
      expect(region_op[:height]).to eq(32)
      mock.close
    end
  end

  describe '#save_png' do
    it 'creates a PNG file with correct dimensions' do
      mock = described_class.new(model: model)
      mock.show(make_canvas(mock))
      path = File.join(Dir.tmpdir, "chroma_wave_test_#{Process.pid}.png")
      mock.save_png(path)
      expect(File.exist?(path)).to be true
      verify_png_dimensions(path, mock.width, mock.height)
    ensure
      FileUtils.rm_f(path)
      mock&.close
    end

    it 'raises without a prior show' do
      mock = described_class.new(model: model)
      expect { mock.save_png('/tmp/should_not_exist.png') }
        .to raise_error(RuntimeError, /no framebuffer/)
      mock.close
    end
  end

  describe 'busy-wait simulation' do
    it 'does not delay when busy_duration is 0' do
      mock = described_class.new(model: model, busy_duration: 0)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.show(fb) # warm up lazy init
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      mock.show(fb)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 0.05
      mock.close
    end

    it 'delays by approximately busy_duration seconds' do
      mock = described_class.new(model: model, busy_duration: 0.1)
      fb = ChromaWave::Framebuffer.new(mock.width, mock.height, mock.pixel_format)
      mock.show(fb) # warm up lazy init
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      mock.show(fb)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be >= 0.08
      mock.close
    end
  end

  describe 'thread safety' do
    it 'handles concurrent show calls without error' do
      mock = described_class.new(model: model)
      canvas = make_canvas(mock)
      mock.show(canvas) # force init

      threads = 4.times.map do
        Thread.new { mock.show(make_canvas(mock)) }
      end
      threads.each(&:join)

      # All 4 concurrent shows plus the initial one
      expect(mock.operation_count(:show)).to eq(5)
      mock.close
    end
  end

  describe 'RSpec :hardware helper', :hardware do
    it 'provides a mock_device in metadata' do |example|
      mock = example.metadata[:mock_device]
      expect(mock).to be_a(described_class)
    end

    it 'has the default model' do |example|
      mock = example.metadata[:mock_device]
      expect(mock.model).to eq(:epd_2in13_v4)
    end
  end

  describe 'RSpec :hardware helper with custom model', :hardware, model: :epd_2in7_v2 do
    it 'uses the specified model' do |example|
      mock = example.metadata[:mock_device]
      expect(mock.model).to eq(:epd_2in7_v2)
    end
  end

  describe '#renderer' do
    it 'returns a Renderer with the correct pixel format' do
      mock = described_class.new(model: model)
      expect(mock.renderer).to be_a(ChromaWave::Renderer)
      expect(mock.renderer.pixel_format).to eq(mock.pixel_format)
      mock.close
    end
  end

  describe '#inspect' do
    it 'includes model, dimensions, and format' do
      mock = described_class.new(model: model)
      text = mock.inspect
      expect(text).to include('epd_2in13_v4')
      expect(text).to include("#{mock.width}x#{mock.height}")
      expect(text).to include('mono')
      mock.close
    end
  end

  private

  def make_canvas(mock = nil)
    w = mock&.width || 122
    h = mock&.height || 250
    ChromaWave::Canvas.new(width: w, height: h)
  end

  def verify_png_dimensions(path, expected_width, expected_height)
    require 'vips'
    img = Vips::Image.new_from_file(path)
    expect(img.width).to eq(expected_width)
    expect(img.height).to eq(expected_height)
    expect(img.bands).to eq(3)
  end
end
