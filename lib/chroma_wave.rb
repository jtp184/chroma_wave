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
