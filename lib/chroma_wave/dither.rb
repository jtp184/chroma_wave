# frozen_string_literal: true

require_relative 'dither/strategy'
require_relative 'dither/threshold'
require_relative 'dither/floyd_steinberg'
require_relative 'dither/ordered'

module ChromaWave
  # Dithering strategies for converting RGBA canvases to palette-indexed framebuffers.
  #
  # Each strategy implements a different algorithm for mapping continuous-tone
  # pixels to a limited palette. Use {.resolve} to instantiate a strategy by name,
  # or {.strategies} to list available strategy names.
  #
  # @example Resolve a strategy by name
  #   strategy = Dither.resolve(:floyd_steinberg, pixel_format: fmt)
  #   strategy.call(canvas, framebuffer)
  #
  # @example List available strategies
  #   Dither.strategies  #=> [:floyd_steinberg, :ordered, :threshold]
  module Dither
    # Maps strategy names to their implementing classes.
    REGISTRY = [Threshold, FloydSteinberg, Ordered].each_with_object({}) do |klass, map|
      map[klass.strategy_name] = klass
    end.freeze

    # Returns the list of available strategy names.
    #
    # @return [Array<Symbol>]
    def self.strategies
      REGISTRY.keys.sort
    end

    # Resolves a strategy name to an instantiated strategy object.
    #
    # @param name [Symbol] strategy name (e.g. +:floyd_steinberg+, +:threshold+, +:ordered+)
    # @param pixel_format [PixelFormat] target pixel format with palette
    # @return [Strategy] an instantiated strategy
    # @raise [ArgumentError] if the strategy name is not recognized
    def self.resolve(name, pixel_format:)
      klass = REGISTRY[name]
      unless klass
        raise ArgumentError,
              "unknown dither strategy: #{name.inspect} (expected one of #{strategies.join(', ')})"
      end

      klass.new(pixel_format: pixel_format)
    end
  end
end
