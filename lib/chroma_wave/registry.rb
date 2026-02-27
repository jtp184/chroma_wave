# frozen_string_literal: true

require 'did_you_mean'

module ChromaWave
  # Builds Display subclasses with the correct capabilities for each model.
  #
  # The Registry reads model metadata from the C extension via
  # {Native.model_config} and dynamically creates a Display subclass with
  # the appropriate capability modules mixed in. Subclasses are cached so
  # repeated instantiation of the same model reuses the same class.
  module Registry
    # Maps capability symbols from the C config to Ruby modules.
    CAPABILITY_MAP = {
      partial: Capabilities::PartialRefresh,
      fast: Capabilities::FastRefresh,
      grayscale: Capabilities::GrayscaleMode,
      dual_buf: Capabilities::DualBuffer,
      regional: Capabilities::RegionalRefresh
    }.freeze

    class << self
      # Builds a Display subclass instance for the given model.
      #
      # @param model [Symbol, String] model name (e.g. +:epd_2in13_v4+)
      # @return [Display]
      # @raise [ModelNotFoundError] if the model is not in the registry
      def build(model)
        name = model.to_s
        config = Native.model_config(name)
        raise_not_found!(name) unless config

        klass = display_classes[name] ||= build_class(name, config)
        klass.send(:new, model_name: name, config: config)
      end

      # Returns all registered model names as symbols.
      #
      # @return [Array<Symbol>]
      def model_names
        Native.model_names.map(&:to_sym)
      end

      private

      # Cache of dynamically-built Display subclasses, keyed by model name string.
      #
      # @return [Hash{String => Class}]
      def display_classes
        @display_classes ||= {}
      end

      # Builds a Display subclass with the appropriate capabilities mixed in.
      #
      # @param name [String] model name
      # @param config [Hash] model configuration from Native
      # @return [Class] a Display subclass
      def build_class(name, config)
        caps = config[:capabilities] || []
        klass = Class.new(Display)

        caps.each do |cap|
          mod = CAPABILITY_MAP[cap]
          klass.include(mod) if mod
        end

        # Register as a named constant for debuggability
        const_name = name.split('_').map(&:capitalize).join
        ChromaWave.const_set(const_name, klass) unless ChromaWave.const_defined?(const_name, false)

        klass
      end

      # Raises ModelNotFoundError with did-you-mean suggestions.
      #
      # Uses Levenshtein distance via Ruby's built-in +did_you_mean+ gem
      # for accurate fuzzy matching.
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
  end
end
