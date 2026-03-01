# frozen_string_literal: true

require 'did_you_mean'

module ChromaWave
  # Test-friendly Display replacement that logs operations without touching hardware.
  #
  # MockDevice is a full Display subclass with the correct capability modules
  # for any registered model. Instead of a real C Device, it injects a
  # {DeviceStub} that records every hardware call as an inspectable log entry.
  #
  # @example Basic usage
  #   mock = MockDevice.new(model: :epd_2in13_v4)
  #   mock.show(canvas)
  #   mock.operations         # => [{ op: :init, ... }, { op: :show, ... }]
  #   mock.last_framebuffer   # => Framebuffer (dup of last rendered output)
  #
  # @example Block form with auto-close
  #   MockDevice.open(model: :epd_2in13_v4) do |mock|
  #     mock.show(canvas)
  #     mock.save_png('output.png')
  #   end
  class MockDevice < Display
    class << self
      # Factory — builds a MockDevice subclass with the correct capabilities.
      #
      # @param model [Symbol, String] model name (e.g. +:epd_2in13_v4+)
      # @param busy_duration [Numeric] simulated refresh delay in seconds
      # @return [MockDevice]
      # @raise [ModelNotFoundError] if the model is not in the registry
      def new(model: nil, busy_duration: 0, **kwargs)
        raise ArgumentError, 'missing keyword: :model' unless model
        raise ArgumentError, "unknown keyword(s): #{kwargs.keys.join(', ')}" unless kwargs.empty?

        name = model.to_s
        config = Native.model_config(name)
        raise_not_found!(name) unless config

        klass = mock_classes[name] ||= build_mock_class(config)
        instance = klass.allocate
        instance.send(:initialize, model_name: name, config: config, busy_duration: busy_duration)
        instance
      end

      # Block form — opens a mock device, yields it, ensures it is closed.
      #
      # @param model [Symbol, String] model name
      # @param busy_duration [Numeric] simulated refresh delay in seconds
      # @yield [mock] the opened MockDevice
      # @return [MockDevice, Object] the mock (no block) or the block's return value
      def open(model:, busy_duration: 0)
        mock = new(model: model, busy_duration: busy_duration)
        return mock unless block_given?

        begin
          yield mock
        ensure
          mock.close
        end
      end

      private

      # Cache of dynamically-built MockDevice subclasses, keyed by model name.
      #
      # @return [Hash{String => Class}]
      def mock_classes
        @mock_classes ||= {}
      end

      # Builds a MockDevice subclass with the appropriate capabilities.
      #
      # @param config [Hash] model configuration from Native
      # @return [Class] a MockDevice subclass
      def build_mock_class(config)
        caps = config[:capabilities] || []
        klass = Class.new(self)

        caps.each do |cap|
          mod = Registry::CAPABILITY_MAP[cap]
          klass.include(mod) if mod
        end

        klass
      end

      # Raises ModelNotFoundError with did-you-mean suggestions.
      #
      # @param name [String] the unrecognized model name
      # @raise [ModelNotFoundError]
      def raise_not_found!(name)
        suggestions = DidYouMean::SpellChecker
                      .new(dictionary: Native.model_names)
                      .correct(name)
        msg = "unknown model: #{name}"
        msg += " -- did you mean: #{suggestions.join(', ')}?" unless suggestions.empty?
        raise ModelNotFoundError, msg
      end
    end

    # Returns all recorded operations, optionally filtered by type.
    #
    # @param type [Symbol, nil] operation type filter (e.g. +:show+, +:init+)
    # @return [Array<Hash>]
    def operations(type = nil)
      @operations_mutex.synchronize do
        return @operations_log.dup unless type

        @operations_log.select { |op| op[:op] == type }
      end
    end

    # Returns the most recently recorded operation.
    #
    # @return [Hash, nil]
    def last_operation
      @operations_mutex.synchronize { @operations_log.last }
    end

    # Counts operations of the given type, or all operations if no type given.
    #
    # @param type [Symbol, nil] operation type to count
    # @return [Integer]
    def operation_count(type = nil)
      @operations_mutex.synchronize do
        return @operations_log.size unless type

        @operations_log.count { |op| op[:op] == type }
      end
    end

    # Clears all recorded operations.
    #
    # @return [self]
    def clear_operations!
      @operations_mutex.synchronize { @operations_log.clear }
      self
    end

    # Returns a dup of the last framebuffer sent to the display.
    #
    # @return [Framebuffer, nil] nil if no show has occurred
    def last_framebuffer
      @operations_mutex.synchronize { @last_framebuffer&.dup }
    end

    # Exports the last framebuffer as a palette-accurate PNG.
    #
    # Each pixel is looked up in the framebuffer's palette and mapped to its
    # Color RGB values, producing a native-resolution PNG that matches what
    # the physical display would show.
    #
    # @param path [String] output file path
    # @return [void]
    # @raise [RuntimeError] if no framebuffer has been displayed yet
    # @raise [DependencyError] if ruby-vips is not installed
    def save_png(path)
      fb = @operations_mutex.synchronize { @last_framebuffer }
      raise 'no framebuffer to export — call show first' unless fb

      require_vips!
      write_png(fb, path)
    end

    protected

    # Internal constructor — sets up the mock device with a DeviceStub.
    #
    # Does NOT call super — avoids Display#initialize which creates a real C Device.
    #
    # @param model_name [Symbol, String] the model identifier
    # @param config [Hash] the model configuration from Native
    # @param busy_duration [Numeric] simulated refresh delay in seconds
    def initialize(model_name:, config:, busy_duration: 0) # rubocop:disable Lint/MissingSuper -- intentionally avoids Display#initialize which creates a real C Device
      @model = model_name.to_sym
      @width = config[:width]
      @height = config[:height]
      @pixel_format = PixelFormat.from_name(config[:pixel_format])
      @busy_duration = busy_duration
      @initialized = false
      @current_mode = nil
      @operations_mutex = Mutex.new
      @operations_log = []
      @last_framebuffer = nil
      @device = DeviceStub.new(self)
    end

    private

    attr_reader :busy_duration

    # Records an operation to the thread-safe log.
    #
    # @param entry [Hash] the operation fields (op:, plus metadata)
    # @return [void]
    def record_operation(**entry)
      @operations_mutex.synchronize do
        @operations_log << entry.merge(timestamp: Time.now).freeze
      end
    end

    # Stores a dup of the framebuffer for later inspection.
    #
    # @param framebuffer [Framebuffer] the framebuffer to store
    # @return [void]
    def store_framebuffer(framebuffer)
      @operations_mutex.synchronize { @last_framebuffer = framebuffer.dup }
    end

    # Simulates busy-wait by sleeping for the configured duration.
    #
    # @return [void]
    def simulate_busy
      Kernel.sleep(busy_duration) if busy_duration.positive?
    end

    # Lazily requires ruby-vips for PNG export.
    #
    # @raise [DependencyError] if ruby-vips cannot be loaded
    def require_vips!
      return if defined?(::Vips)

      require 'vips'
    rescue LoadError
      raise DependencyError,
            'ruby-vips is required for PNG export. ' \
            'Install it with: gem install ruby-vips'
    end

    # Writes a framebuffer to a PNG file using palette-accurate colors.
    #
    # Builds the RGB buffer directly as a binary string, using a pre-built
    # palette lookup to avoid per-pixel Color.from_name calls.
    #
    # @param framebuffer [Framebuffer] the framebuffer to export
    # @param path [String] output file path
    # @return [void]
    def write_png(framebuffer, path)
      w = framebuffer.width
      h = framebuffer.height
      rgb_for = build_palette_rgb(framebuffer.pixel_format)
      buf = String.new(capacity: w * h * 3, encoding: 'BINARY')

      h.times do |y|
        w.times do |x|
          buf << rgb_for[framebuffer.get_pixel(x, y)]
        end
      end

      image = ::Vips::Image.new_from_memory(buf, w, h, 3, :uchar)
      image.write_to_file(path.to_s)
    end

    # Builds a hash mapping palette color names to packed RGB byte strings.
    #
    # @param pixel_format [PixelFormat] the framebuffer's pixel format
    # @return [Hash{Symbol => String}] color name to 3-byte RGB string
    def build_palette_rgb(pixel_format)
      pixel_format.palette.each_with_object({}) do |name, map|
        color = Color.from_name(name)
        map[name] = [color.r, color.g, color.b].pack('CCC')
      end
    end

    # Stub device that intercepts hardware calls and delegates to MockDevice.
    #
    # Injected as the +@device+ ivar so capability modules' calls to
    # +device.send(:_epd_xxx, ...)+ and +device.synchronize+ are
    # intercepted without needing to override methods on the MockDevice itself.
    class DeviceStub
      # @param mock_device [MockDevice] the owning mock device
      def initialize(mock_device)
        @mock_device = mock_device
        @mutex = Mutex.new
        @open = true
      end

      # Thread-safe device access (mirrors Device::Lifecycle#synchronize).
      #
      # @yield the block to execute while holding the lock
      # @return the block's return value
      def synchronize(&)
        @mutex.synchronize(&)
      end

      # Closes the stub device. Safe to call multiple times.
      #
      # @return [void]
      def close
        return unless @open

        @open = false
        @mock_device.send(:record_operation, op: :close)
      end

      # Returns whether the device is open.
      #
      # @return [Boolean]
      def open?
        @open
      end

      private

      # Raises DeviceError if the stub has been closed.
      #
      # @raise [DeviceError] if the device is not open
      # @return [void]
      def assert_open!
        raise DeviceError, 'device is closed' unless @open
      end

      # Stub for EPD init — logs the mode.
      #
      # @param mode [Integer] init mode constant
      # @return [void]
      # @raise [DeviceError] if the device is closed
      def _epd_init(mode)
        assert_open!
        mode_name = mode_to_sym(mode)
        @mock_device.send(
          :record_operation,
          op: :init, model: @mock_device.model, mode: mode_name
        )
      end

      # Stub for single-buffer display — logs buffer size and stores framebuffer.
      #
      # @param framebuffer [Framebuffer] the framebuffer to display
      # @return [void]
      # @raise [DeviceError] if the device is closed
      def _epd_display(framebuffer)
        assert_open!
        @mock_device.send(:store_framebuffer, framebuffer)
        @mock_device.send(
          :record_operation,
          op: :show, buffer_bytes: framebuffer.bytes.bytesize
        )
        @mock_device.send(:simulate_busy)
      end

      # Stub for dual-buffer display — logs both buffer sizes.
      #
      # @param black_fb [Framebuffer] the black plane framebuffer
      # @param red_fb [Framebuffer] the red plane framebuffer
      # @return [void]
      # @raise [DeviceError] if the device is closed
      def _epd_display_dual(black_fb, red_fb)
        assert_open!
        @mock_device.send(:store_framebuffer, black_fb)
        @mock_device.send(
          :record_operation,
          op: :show_dual,
          black_bytes: black_fb.bytes.bytesize,
          red_bytes: red_fb.bytes.bytesize
        )
        @mock_device.send(:simulate_busy)
      end

      # Stub for regional display — logs the region coordinates.
      #
      # @param framebuffer [Framebuffer] the full-screen framebuffer
      # @param x [Integer] aligned x coordinate
      # @param y [Integer] y coordinate
      # @param width [Integer] aligned width
      # @param height [Integer] height
      # @return [void]
      # @raise [DeviceError] if the device is closed
      def _epd_display_region(framebuffer, x, y, width, height)
        assert_open!
        @mock_device.send(:store_framebuffer, framebuffer)
        @mock_device.send(
          :record_operation,
          op: :show_region, x: x, y: y, width: width, height: height
        )
        @mock_device.send(:simulate_busy)
      end

      # Stub for EPD clear — logs the operation.
      #
      # @return [void]
      # @raise [DeviceError] if the device is closed
      def _epd_clear
        assert_open!
        @mock_device.send(:record_operation, op: :clear, color: :white)
        @mock_device.send(:simulate_busy)
      end

      # Stub for EPD sleep — logs the operation.
      #
      # @return [void]
      # @raise [DeviceError] if the device is closed
      def _epd_sleep
        assert_open!
        @mock_device.send(:record_operation, op: :sleep)
      end

      # Converts a numeric init mode to a symbol name.
      #
      # @param mode [Integer] init mode constant
      # @return [Symbol] :full, :fast, :partial, or :grayscale
      def mode_to_sym(mode)
        case mode
        when Native::MODE_FULL      then :full
        when Native::MODE_FAST      then :fast
        when Native::MODE_PARTIAL   then :partial
        when Native::MODE_GRAYSCALE then :grayscale
        else :"unknown_#{mode}"
        end
      end
    end
  end
end
