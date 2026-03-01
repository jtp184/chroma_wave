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

# FreeType 2 detection (optional — text rendering)
# rubocop:disable Style/GlobalVars -- mkmf convention for preprocessor defines
have_freetype = pkg_config('freetype2') ||
                (find_header('ft2build.h') && have_library('freetype', 'FT_Init_FreeType'))

if have_freetype
  message "NOTE: FreeType 2 found — text rendering enabled\n"
else
  $defs << '-DNO_FREETYPE'
  message "NOTE: FreeType 2 not found — text will raise DependencyError\n"
end
# rubocop:enable Style/GlobalVars

create_makefile('chroma_wave/chroma_wave')
