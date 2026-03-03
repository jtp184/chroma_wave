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

    # Renders and displays only the dirty region of a canvas.
    #
    # When the canvas is clean (no modifications since last +clean!+), returns
    # +self+ immediately (no-op). Otherwise renders the full canvas (for dither
    # correctness) and pushes the dirty sub-region to hardware.
    #
    # On {Capabilities::RegionalRefresh}-capable displays, always uses
    # +display_region+ to update only the changed rectangle — +mode+ is
    # ignored. On non-regional displays, falls back to a full-screen refresh
    # by default, or to {Capabilities::PartialRefresh#display_partial} when
    # +mode: :partial+ is specified.
    #
    # Always calls +canvas.clean!+ after a successful display operation.
    #
    # @param canvas [Canvas] the canvas to display
    # @param mode [Symbol, nil] display mode (+nil+ for default, +:partial+
    #   for partial refresh). Only affects the non-regional fallback path.
    # @return [self]
    # @raise [TypeError] if +canvas+ is not a Canvas
    # @raise [ArgumentError] if +mode+ is not recognized or display lacks the requested capability
    def show_dirty(canvas, mode: nil)
      raise TypeError, "expected Canvas, got #{canvas.class}" unless canvas.is_a?(Canvas)

      validate_display_mode!(mode)
      return self unless canvas.dirty?

      validate_canvas_dimensions!(canvas)
      region = canvas.dirty_region

      fb = renderer.render(canvas)

      if is_a?(Capabilities::RegionalRefresh)
        # display_region expects logical-space FB and handles rotation internally
        display_dirty_regional(fb, region)
      else
        # Full-screen path needs native-orientation FB
        fb = fb.rotate(rotation) unless rotation.zero?
        display_dirty_fallback(fb, mode)
      end

      canvas.clean!
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

    # Forces a full-mode initialization and display cycle on the device.
    #
    # Used by {Capabilities::ManagedRefresh} for automatic maintenance refreshes.
    # Must be called while holding the device lock.
    #
    # @param framebuffer [Framebuffer] the content to display
    # @return [void]
    def force_full_refresh!(framebuffer)
      device.send(:_epd_init, Native::MODE_FULL)
      device.send(:_epd_display, framebuffer)
      @current_mode = :full
      @initialized = true
    end

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
      if pixel_format == PixelFormat::COLOR4
        raise ArgumentError,
              'managed_refresh is not supported on tri-color (COLOR4) displays'
      end

      unless options == true || options.is_a?(Hash)
        raise ArgumentError,
              "managed_refresh must be true or a Hash, got #{options.inspect} (#{options.class})"
      end

      opts = options == true ? {} : options
      @refresh_scheduler = RefreshScheduler.new(**opts)
      extend Capabilities::ManagedRefresh
    end

    # Validates the display mode, raising for unknown or unsupported modes.
    #
    # +:partial+ is accepted with {Capabilities::PartialRefresh} or
    # {Capabilities::RegionalRefresh} (where +mode+ is ignored).
    #
    # @param mode [Symbol, nil] the requested mode
    # @raise [ArgumentError] if mode is unrecognized or display lacks the capability
    def validate_display_mode!(mode)
      case mode
      when nil then nil
      when :partial
        return if is_a?(Capabilities::PartialRefresh) || is_a?(Capabilities::RegionalRefresh)

        raise ArgumentError, 'display does not support partial mode'
      else
        raise ArgumentError, "unknown mode: #{mode.inspect}"
      end
    end

    # Displays the dirty region using regional refresh.
    #
    # @param framebuffer [Framebuffer] full-screen rendered framebuffer (logical space)
    # @param region [Rect] dirty region bounding box
    # @return [void]
    def display_dirty_regional(framebuffer, region)
      display_region(framebuffer,
                     x: region.x, y: region.y,
                     width: region.width, height: region.height)
    end

    # Falls back to full-screen refresh when regional refresh is unavailable.
    #
    # Routes through {#show} so that {Capabilities::ManagedRefresh} tracking
    # wraps the operation automatically (tracked as full refresh).
    #
    # @param framebuffer [Framebuffer] full-screen rendered framebuffer (native orientation)
    # @param mode [Symbol, nil] display mode (already validated)
    # @return [void]
    def display_dirty_fallback(framebuffer, mode)
      if mode == :partial
        display_partial(framebuffer)
      else
        # Framebuffer is already rotated to native orientation;
        # enters show's Framebuffer branch (validate + display).
        show(framebuffer)
      end
    end

    # Validates that a canvas matches this display's logical dimensions.
    #
    # @param canvas [Canvas] the canvas to validate
    # @raise [ArgumentError] if dimensions do not match
    def validate_canvas_dimensions!(canvas)
      return if canvas.width == width && canvas.height == height

      raise ArgumentError,
            "canvas dimensions #{canvas.width}x#{canvas.height} " \
            "do not match display size #{width}x#{height}"
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
