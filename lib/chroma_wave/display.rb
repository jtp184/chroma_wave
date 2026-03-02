# frozen_string_literal: true

module ChromaWave
  # High-level interface for rendering content on a Waveshare E-Paper display.
  #
  # Display wraps a {Device} and a {Renderer}, providing a simple API for
  # showing Canvas or Framebuffer content. Capability modules are mixed in
  # automatically based on the model's hardware features.
  #
  # Do not instantiate directly -- use {Display.new} (factory) or
  # {Display.open} (block form with auto-close).
  #
  # @example Show a canvas on a display
  #   Display.open(model: :epd_2in13_v4) do |display|
  #     canvas = Canvas.new(width: display.width, height: display.height)
  #     canvas.set_pixel(10, 20, Color::BLACK)
  #     display.show(canvas)
  #   end
  class Display
    # Valid rotation angles (degrees clockwise).
    VALID_ROTATIONS = [0, 90, 180, 270].freeze

    attr_reader :model, :width, :height, :pixel_format, :rotation, :native_width, :native_height

    # Factory method -- builds the correct Display subclass via {Registry}.
    #
    # Only triggers on +Display+ itself, not on subclasses (which are built
    # internally by {Registry}).
    #
    # @param model [Symbol, String] model name (e.g. +:epd_2in13_v4+)
    # @param rotation [Integer] display rotation in degrees (0, 90, 180, 270)
    # @param managed_refresh [Boolean, Hash, nil] opt-in refresh scheduling.
    #   Pass +true+ for defaults, or a Hash with +:partial_limit+, +:min_interval+,
    #   and/or +:auto_full_refresh+ keys. +nil+ (default) disables scheduling.
    # @return [Display] a subclass instance with appropriate capabilities
    # @raise [ModelNotFoundError] if the model is not in the registry
    def self.new(model: nil, rotation: 0, managed_refresh: nil, **kwargs)
      if self == Display
        raise ArgumentError, 'missing keyword: :model' unless model
        raise ArgumentError, "unknown keyword(s): #{kwargs.keys.join(', ')}" unless kwargs.empty?

        return Registry.build(model, rotation: rotation, managed_refresh: managed_refresh)
      end

      instance = allocate
      instance.send(:initialize, rotation: rotation, managed_refresh: managed_refresh, **kwargs)
      instance
    end

    # Block form -- opens a display, yields it, and ensures it is closed.
    #
    # Without a block, returns the open display.
    #
    # @param model [Symbol, String] model name
    # @param rotation [Integer] display rotation in degrees (0, 90, 180, 270)
    # @param managed_refresh [Boolean, Hash, nil] opt-in refresh scheduling
    # @yield [display] the opened display
    # @return [Display, Object] the display (no block) or the block's return value
    def self.open(model:, rotation: 0, managed_refresh: nil)
      display = new(model: model, rotation: rotation, managed_refresh: managed_refresh)
      return display unless block_given?

      begin
        yield display
      ensure
        display.close
      end
    end

    # Lists all registered model names as symbols.
    #
    # @return [Array<Symbol>]
    def self.models
      Registry.model_names
    end

    # Renders content and sends to the display.
    #
    # Accepts Canvas, Layout, or Framebuffer input:
    # - Canvas: rendered and automatically rotated to match display rotation.
    # - Layout: rendered to a Canvas first, then displayed as Canvas.
    # - Framebuffer: sent directly; must match native dimensions and format.
    #
    # Lazily initializes the EPD on first use.
    #
    # @param canvas_or_fb [Canvas, Layout, Framebuffer] content to display
    # @return [self]
    # @raise [FormatMismatchError] if a Framebuffer's format does not match
    # @raise [ArgumentError] if a Framebuffer's dimensions do not match native display size
    def show(canvas_or_fb)
      ensure_initialized!
      case canvas_or_fb
      when Canvas
        fb = renderer.render(canvas_or_fb)
        fb = fb.rotate(rotation) unless rotation.zero?
        synchronize_device { device.send(:_epd_display, fb) }
      when Layout
        show(canvas_or_fb.render)
      when Framebuffer
        validate_framebuffer!(canvas_or_fb)
        synchronize_device { device.send(:_epd_display, canvas_or_fb) }
      else
        raise TypeError, "expected Canvas, Layout, or Framebuffer, got #{canvas_or_fb.class}"
      end
      self
    end

    # Clears the display to a solid color.
    #
    # When +color+ is +:white+ (the default), delegates to the hardware's
    # native clear command. For any other color, fills a Framebuffer with
    # the specified palette color and pushes it to the display.
    #
    # @param color [Symbol] palette color name (e.g. +:black+, +:white+, +:red+)
    # @return [self]
    # @raise [KeyError] if +color+ is not in this display's palette
    def clear(color: :white)
      ensure_initialized!
      if color == :white
        synchronize_device { device.send(:_epd_clear) }
      else
        fb = Framebuffer.new(native_width, native_height, pixel_format)
        fb.clear(color)
        synchronize_device { device.send(:_epd_display, fb) }
      end
      self
    end

    # Puts the display into deep sleep mode (EPD power-down).
    #
    # The display must be re-initialized before the next use.
    #
    # @return [self]
    def deep_sleep
      synchronize_device do
        return self unless @initialized

        device.send(:_epd_sleep)
        @initialized = false
        @current_mode = nil
      end
      self
    end

    # Closes the device connection.
    #
    # Attempts a best-effort deep sleep before closing. Safe to call multiple times.
    #
    # @return [void]
    def close
      deep_sleep
    rescue DeviceError
      nil
    ensure
      device.close
    end

    # Returns the lazy-initialized Renderer for this display.
    #
    # @return [Renderer]
    def renderer
      @renderer ||= Renderer.new(pixel_format: pixel_format)
    end

    # Human-readable description of the display.
    #
    # @return [String]
    def inspect
      base = "#<#{self.class} #{model} #{width}x#{height} #{pixel_format.name}"
      base += " rot=#{rotation}" unless rotation.zero?
      "#{base}>"
    end

    protected

    # Internal constructor -- called by {Registry.build}, NOT by users.
    #
    # Use {Display.new} or {Display.open} instead.
    #
    # @param model_name [Symbol, String] the model identifier
    # @param config [Hash] the model configuration from {Native.model_config}
    # @param rotation [Integer] display rotation in degrees (0, 90, 180, 270)
    # @param managed_refresh [Boolean, Hash, nil] opt-in refresh scheduling
    def initialize(model_name:, config:, rotation: 0, managed_refresh: nil)
      validate_rotation!(rotation)
      @model = model_name.to_sym
      @rotation = rotation
      @native_width = config[:width]
      @native_height = config[:height]
      @pixel_format = PixelFormat.from_name(config[:pixel_format])
      @device = Device.new(model_name.to_s)
      @initialized = false
      @current_mode = nil

      apply_logical_dimensions!
      setup_managed_refresh!(managed_refresh) if managed_refresh
    end

    private

    attr_reader :device, :current_mode

    # Lazily initializes the EPD on first use with full refresh mode.
    #
    # Thread-safe: always synchronizes the @initialized check to prevent
    # races on JRuby/TruffleRuby where reads are not atomic.
    #
    # @return [void]
    def ensure_initialized!
      synchronize_device do
        return if @initialized

        device.send(:_epd_init, Native::MODE_FULL)
        @initialized = true
        @current_mode = :full
      end
    end

    # Thread-safe device access.
    #
    # @yield the block to execute while holding the device mutex
    # @return the block's return value
    def synchronize_device(&)
      device.synchronize(&)
    end

    # Validates that the rotation is a valid angle.
    #
    # @param degrees [Integer] the rotation angle
    # @raise [ArgumentError] if the angle is not valid
    def validate_rotation!(degrees)
      return if VALID_ROTATIONS.include?(degrees)

      raise ArgumentError, "rotation must be one of #{VALID_ROTATIONS.join(', ')} (got #{degrees})"
    end

    # Sets +@width+ and +@height+ from native dimensions and rotation.
    #
    # For 90/270 rotations the logical dimensions are swapped relative to
    # the native (hardware) dimensions.
    #
    # @return [void]
    def apply_logical_dimensions!
      if [90, 270].include?(rotation)
        @width = @native_height
        @height = @native_width
      else
        @width = @native_width
        @height = @native_height
      end
    end

    # Configures managed refresh scheduling for this instance.
    #
    # Creates a {RefreshScheduler} and extends this instance with
    # {Capabilities::ManagedRefresh} to wrap display methods with
    # automatic refresh tracking.
    #
    # @param options [Boolean, Hash] +true+ for defaults, or a Hash of
    #   scheduler options (see {RefreshScheduler#initialize})
    # @return [void]
    def setup_managed_refresh!(options)
      opts = options == true ? {} : options
      @refresh_scheduler = RefreshScheduler.new(**opts)
      extend Capabilities::ManagedRefresh
    end

    # Validates that a framebuffer's pixel format and dimensions match this display.
    #
    # Framebuffers operate in native coordinate space, so their dimensions
    # must match {#native_width} and {#native_height}, regardless of rotation.
    #
    # @param framebuffer [Framebuffer] the framebuffer to validate
    # @raise [FormatMismatchError] if the pixel format does not match
    # @raise [ArgumentError] if dimensions do not match native display size
    def validate_framebuffer!(framebuffer)
      unless framebuffer.pixel_format == pixel_format
        raise FormatMismatchError,
              "expected #{pixel_format.name} framebuffer, got #{framebuffer.pixel_format.name}"
      end

      return if framebuffer.width == native_width && framebuffer.height == native_height

      raise ArgumentError,
            "framebuffer dimensions #{framebuffer.width}x#{framebuffer.height} " \
            "do not match native display size #{native_width}x#{native_height}"
    end
  end
end
