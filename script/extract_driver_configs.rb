#!/usr/bin/env ruby
# frozen_string_literal: true

# AUTO-GENERATES ext/chroma_wave/driver_configs_generated.h from vendor Waveshare
# E-Paper driver source files. Thin shim — all logic lives in
# ChromaWave::DriverExtraction::Runner.
#
# Usage:
#   ruby script/extract_driver_configs.rb
#   rake generate:driver_configs

require_relative '../lib/chroma_wave/driver_extraction'

ChromaWave::DriverExtraction::Runner.new.call
