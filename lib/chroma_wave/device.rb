# frozen_string_literal: true

module ChromaWave
  # Wraps a Waveshare E-Paper display with HAL lifecycle management.
  #
  # The C layer provides alloc/initialize (model lookup, DEV_Module_Init),
  # close, open?, model_name, and private _epd_* bridge methods.
  # This Ruby reopening adds a Mutex for thread safety and a block-form
  # +.open+ for automatic cleanup.
  class Device
    # Adds Ruby-level lifecycle management on top of the C-defined Device class.
    #
    # Prepended onto the C-defined +Device+ so +super+ dispatches to the
    # C +initialize+ method.
    module Lifecycle
      # Initializes the device for the given model, setting up a mutex for
      # thread-safe access.
      #
      # @param model_name [String] the EPD model identifier (e.g. "epd_2in13_v4")
      # @raise [ChromaWave::ModelNotFoundError] if the model is not in the registry
      # @raise [ChromaWave::InitError] if HAL initialization fails
      def initialize(model_name)
        @mutex = Mutex.new
        super # -> C device_initialize(model_name)
      end

      # Synchronizes access to the device using the internal mutex.
      #
      # @yield the block to execute while holding the lock
      # @return the block's return value
      def synchronize(&)
        mutex.synchronize(&)
      end

      private

      attr_reader :mutex
    end

    prepend Lifecycle

    # Opens a device, optionally yielding it and auto-closing.
    #
    # When called with a block, yields the device and ensures it is closed
    # when the block exits. Without a block, returns the open device.
    #
    # @param model_name [String] the EPD model identifier
    # @yield [device] the opened device
    # @return [Device, Object] the device (no block) or the block's return value
    def self.open(model_name)
      device = new(model_name)
      return device unless block_given?

      begin
        yield device
      ensure
        device.close
      end
    end
  end
end
