# frozen_string_literal: true

require_relative 'chroma_wave/version'
require 'chroma_wave/chroma_wave'

# Ruby bindings for Waveshare E-Paper displays.
#
# Provides a simple, idiomatic Ruby interface for rendering content
# on E-Paper displays via a C extension wrapping vendor drivers.
module ChromaWave
end

require_relative 'chroma_wave/color'        # Color before Palette (NAME_MAP)
require_relative 'chroma_wave/palette'      # Palette before PixelFormat (constants)
require_relative 'chroma_wave/pixel_format' # PixelFormat before Framebuffer wrapper
require_relative 'chroma_wave/pen'          # Pen before Surface (used by Drawing::Primitives)
require_relative 'chroma_wave/surface'      # Surface before Framebuffer (included by FB)
require_relative 'chroma_wave/framebuffer'  # Reopens C class, prepends bridge, includes Surface
require_relative 'chroma_wave/canvas'       # RGBA pixel buffer, includes Surface
require_relative 'chroma_wave/layer'        # Clipped sub-region, includes Surface
require_relative 'chroma_wave/drawing/text' # Text drawing (Canvas & Layer only, not Framebuffer)
ChromaWave::Canvas.include(ChromaWave::Drawing::Text)
ChromaWave::Layer.include(ChromaWave::Drawing::Text)
require_relative 'chroma_wave/text_metrics' # TextMetrics value type (used by Font#measure)
require_relative 'chroma_wave/font'         # Font loading, glyph measurement (requires Surface)
require_relative 'chroma_wave/icon_font'    # IconFont < Font with glyph name registry
require_relative 'chroma_wave/image'        # Optional vips-backed image loading
require_relative 'chroma_wave/device'       # Reopens C class, adds Mutex + open/close lifecycle
require_relative 'chroma_wave/dither'       # Dithering strategies (loaded before Renderer)
require_relative 'chroma_wave/renderer'     # Canvas -> Framebuffer rendering pipeline

require_relative 'chroma_wave/capabilities/partial_refresh'  # Partial-refresh display mode
require_relative 'chroma_wave/capabilities/fast_refresh'     # Fast-refresh display mode
require_relative 'chroma_wave/capabilities/grayscale_mode'   # Grayscale display mode
require_relative 'chroma_wave/capabilities/dual_buffer'      # Dual-buffer tri-color support
require_relative 'chroma_wave/capabilities/regional_refresh' # Regional sub-area refresh
require_relative 'chroma_wave/display'      # High-level Display with lazy init + capabilities
require_relative 'chroma_wave/registry'     # Auto-builds Display subclasses from C config
