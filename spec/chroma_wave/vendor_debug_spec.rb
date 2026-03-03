# frozen_string_literal: true

RSpec.describe 'Vendor debug redirect' do
  describe 'ChromaWave::Native._vendor_debug_test' do
    # Intercept Warning.warn to capture rb_warn output.
    # rb_warn routes through Warning.warn in Ruby 2.7+, which is the
    # same path the vendor Debug() macro uses via vendor_debug.h.
    around do |example|
      original = Warning.method(:warn)
      Warning.define_singleton_method(:warn) { |msg, **| @captured << msg }
      Warning.instance_variable_set(:@captured, [])
      example.run
    ensure
      Warning.define_singleton_method(:warn, original)
      Warning.remove_instance_variable(:@captured) if Warning.instance_variable_defined?(:@captured)
    end

    def captured_warnings
      Warning.instance_variable_get(:@captured)
    end

    it 'routes output through Warning.warn' do
      ChromaWave::Native._vendor_debug_test('hello')
      expect(captured_warnings).to include(a_string_matching(/hello/))
    end

    it 'prefixes output with ChromaWave [vendor]' do
      ChromaWave::Native._vendor_debug_test('test message')
      expect(captured_warnings.first).to match(/warning: ChromaWave \[vendor\]: test message/)
    end

    it 'emits no output when warnings are silenced' do
      original_verbose = $VERBOSE
      $VERBOSE = nil # equivalent to -W0
      ChromaWave::Native._vendor_debug_test('silenced')
      expect(captured_warnings).to be_empty
    ensure
      $VERBOSE = original_verbose
    end
  end
end
