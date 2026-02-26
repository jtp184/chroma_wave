# frozen_string_literal: true

require 'mkmf'

# Makes all symbols private by default
append_cflags('-fvisibility=hidden')

# Warning flags
append_cflags('-Wall')
append_cflags('-Wextra')
append_cflags('-Wno-unused-parameter')

# Phase 1: Always use mock backend (no GPIO/SPI hardware required)
# rubocop:disable Style/GlobalVars -- mkmf convention for preprocessor defines
$defs << '-DEPD_MOCK_BACKEND'
# rubocop:enable Style/GlobalVars
message "NOTE: Building with mock HAL backend (no GPIO/SPI hardware required)\n"

create_makefile('chroma_wave/chroma_wave')
