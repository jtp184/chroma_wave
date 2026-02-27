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
    attr_reader :model, :width, :height, :pixel_format

    # Factory method -- builds the correct Display subclass via {Registry}.
    #
    # Only triggers on +Display+ itself, not on subclasses (which are built
    # internally by {Registry}).
    #
    # @param model [Symbol, String] model name (e.g. +:epd_2in13_v4+)
    # @return [Display] a subclass instance with appropriate capabilities
    # @raise [ModelNotFoundError] if the model is not in the registry
    def self.new(model: nil, **)
      if self == Display
        raise ArgumentError, 'missing keyword: :model' unless model

        return Registry.build(model)
      end

      instance = allocate
      instance.send(:initialize, **)
      instance
    end

    # Block form -- opens a display, yields it, and ensures it is closed.
    #
    # Without a block, returns the open display.
    #
    # @param model [Symbol, String] model name
    # @yield [display] the opened display
    # @return [Display, Object] the display (no block) or the block's return value
    def self.open(model:)
      display = new(model: model)
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

    # Renders a Canvas and sends to the display, or sends a Framebuffer directly.
    #
    # Lazily initializes the EPD on first use.
    #
    # @param canvas_or_fb [Canvas, Framebuffer] content to display
    # @return [self]
    # @raise [FormatMismatchError] if a Framebuffer's format does not match
    def show(canvas_or_fb)
      ensure_initialized!
      if canvas_or_fb.is_a?(Canvas)
        fb = renderer.render(canvas_or_fb)
        synchronize_device { device.send(:_epd_display, fb) }
      else
        validate_framebuffer!(canvas_or_fb)
        synchronize_device { device.send(:_epd_display, canvas_or_fb) }
      end
      self
    end

    # Clears the display to white.
    #
    # @param color [Symbol] reserved for future use (currently ignored)
    # @return [self]
    def clear(color: :white) # rubocop:disable Lint/UnusedMethodArgument
      ensure_initialized!
      synchronize_device { device.send(:_epd_clear) }
      self
    end

    # Puts the display into deep sleep mode (EPD power-down).
    #
    # This is *not* +Kernel#sleep+ -- it sends the EPD deep-sleep command,
    # after which the display must be re-initialized before the next use.
    # To pause execution, call +Kernel.sleep(seconds)+ instead.
    #
    # @return [self]
    def sleep
      synchronize_device { device.send(:_epd_sleep) }
      @initialized = false
      @current_mode = nil
      self
    end

    # Closes the device connection.
    #
    # Attempts a best-effort sleep before closing. Safe to call multiple times.
    #
    # @return [void]
    def close
      sleep
    rescue StandardError
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
      "#<#{self.class} #{model} #{width}x#{height} #{pixel_format.name}>"
    end

    protected

    # Internal constructor -- called by {Registry.build}, NOT by users.
    #
    # Use {Display.new} or {Display.open} instead.
    #
    # @param model_name [Symbol, String] the model identifier
    # @param config [Hash] the model configuration from {Native.model_config}
    def initialize(model_name:, config:)
      @model = model_name.to_sym
      @width = config[:width]
      @height = config[:height]
      @pixel_format = PixelFormat.from_name(config[:pixel_format])
      @device = Device.new(model_name.to_s)
      @initialized = false
      @current_mode = nil
    end

    private

    attr_reader :device, :current_mode

    # Lazily initializes the EPD on first use with full refresh mode.
    #
    # @return [void]
    def ensure_initialized!
      return if @initialized

      synchronize_device do
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

    # Validates that a framebuffer's pixel format matches this display.
    #
    # @param framebuffer [Framebuffer] the framebuffer to validate
    # @raise [FormatMismatchError] if formats do not match
    def validate_framebuffer!(framebuffer)
      return if framebuffer.pixel_format == pixel_format

      raise FormatMismatchError,
            "expected #{pixel_format.name} framebuffer, got #{framebuffer.pixel_format.name}"
    end
  end
end
