# frozen_string_literal: true

require 'mkmf'

# Makes all symbols private by default
append_cflags('-fvisibility=hidden')

# Warning flags
append_cflags('-Wall')
append_cflags('-Wextra')
append_cflags('-Wno-unused-parameter')

# ── GPIO/SPI backend detection ──────────────────────────────────────
#
# Probes for hardware GPIO/SPI libraries in priority order, preferring
# newer libraries (lgpio for RPi 5) over older ones (bcm2835, wiringPi).
# Falls back to the mock backend when no hardware library is found.
#
# Real backends also require the Waveshare vendor HAL (DEV_Config.h) to
# be in the include path. The C code uses mock_hal.h as a replacement
# when building with the mock backend.
#
# Override with: --with-epd-backend=lgpio|bcm2835|wiringpi|devlib|mock

# rubocop:disable Style/GlobalVars -- mkmf convention for preprocessor defines

BACKENDS = {
  'lgpio' => { header: 'lgpio.h', lib: 'lgpio', func: 'lgGpiochipOpen', defines: %w[USE_LGPIO_LIB RPI] },
  'bcm2835' => { header: 'bcm2835.h', lib: 'bcm2835', func: 'bcm2835_init', defines: %w[USE_BCM2835_LIB RPI] },
  'wiringpi' => { header: 'wiringPi.h', lib: 'wiringPi', func: 'wiringPiSetup', defines: %w[USE_WIRINGPI_LIB RPI] },
  'devlib' => { header: 'gpiod.h', lib: 'gpiod', func: 'gpiod_chip_open', defines: %w[USE_DEV_LIB RPI] }
}.freeze

BACKEND_PRIORITY = %w[lgpio bcm2835 wiringpi devlib].freeze
VALID_BACKENDS = (BACKEND_PRIORITY + ['mock']).freeze

# Checks whether the Waveshare vendor HAL header is available.
# Real backends need DEV_Config.h to compile — without it, the C code
# has no GPIO/SPI function declarations or pin definitions.
#
# @return [Boolean] true if the vendor HAL is in the include path
def vendor_hal_available?
  have_header('DEV_Config.h')
end

# Probes for the first available hardware backend.
# Requires both the GPIO library AND the vendor HAL to be present.
#
# Note: mkmf's +have_header+ and +have_library+ add defines/libs to
# +$defs+ and +$libs+ as a side effect. The caller is responsible for
# rolling back these globals when falling through to the mock backend.
#
# @return [String, nil] backend name or nil if none found
def detect_backend
  return nil unless vendor_hal_available?

  BACKEND_PRIORITY.find do |name|
    spec = BACKENDS[name]
    have_header(spec[:header]) && have_library(spec[:lib], spec[:func])
  end
end

# Applies the selected backend's compiler defines and libraries.
#
# @param name [String] backend name (key in BACKENDS)
def apply_backend!(name)
  spec = BACKENDS[name]
  spec[:defines].each { |d| $defs << "-D#{d}" }
  message "NOTE: Building with #{name} backend\n"
end

# Applies the mock backend with an informational message.
#
# @param reason [String] human-readable reason for mock selection
def apply_mock!(reason)
  $defs << '-DEPD_MOCK_BACKEND'
  message "NOTE: #{reason}\n"
end

# Validates and applies an explicit backend override.
#
# @param override [String] the requested backend name
# @return [void]
def apply_override!(override)
  unless BACKENDS.key?(override)
    abort "ERROR: Unknown EPD backend '#{override}'. Valid options: #{VALID_BACKENDS.join(', ')}"
  end

  spec = BACKENDS[override]
  unless vendor_hal_available?
    abort "ERROR: EPD backend '#{override}' requested but vendor HAL (DEV_Config.h) not found. " \
          'Provide the Waveshare library include path via --with-epd-backend-include=DIR.'
  end

  unless have_header(spec[:header]) && have_library(spec[:lib], spec[:func])
    abort "ERROR: EPD backend '#{override}' requested but #{spec[:lib]} library not found. " \
          "Install #{spec[:lib]} development headers and retry."
  end

  apply_backend!(override)
end

# Selects the GPIO/SPI backend: override > auto-detect > mock fallback.
#
# @return [void]
def select_backend!
  override = with_config('epd-backend')

  if override
    override = override.to_s.downcase
    if override == 'mock'
      apply_mock!('Building with mock HAL backend (forced via --with-epd-backend)')
    else
      apply_override!(override)
    end
  else
    # Snapshot $defs/$libs before probing — have_header/have_library add
    # defines as a side effect that must be rolled back on mock fallback.
    defs_before = $defs.dup
    libs_before = $libs.dup
    detected = detect_backend
    if detected
      apply_backend!(detected)
    else
      $defs.replace(defs_before)
      $libs = libs_before
      apply_mock!('No GPIO/SPI library found — building with mock HAL backend')
    end
  end
end

select_backend!

# ── FreeType 2 detection (optional — text rendering) ────────────────

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
