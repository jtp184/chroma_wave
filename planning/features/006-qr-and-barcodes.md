# Feature 006: QR Codes and Barcodes

## Decision

Bundle both QR code and 1D barcode rendering. QR codes via the `rqrcode` gem, 1D barcodes
(Code 128, EAN-13) via the `barby` gem. These are the most common content types on e-paper
displays (product labels, dashboards, configuration screens).

**Priority:** P2 (common use case)
**Effort:** Small

## Design

### API

```ruby
# QR codes
canvas.draw_qr("https://example.com",
  x: 50, y: 50,
  module_size: 4,            # pixels per QR module (default: auto-fit)
  color: Color::BLACK,       # foreground
  background: Color::WHITE,  # background (default: transparent)
  error_correction: :medium  # :low, :medium, :quartile, :high (default: :medium)
)

# Measure before drawing
metrics = ChromaWave::QR.measure("https://example.com", module_size: 4)
metrics.width   # => 116
metrics.height  # => 116
metrics.modules # => 29 (QR version determines this)

# Auto-fit to a bounding box
canvas.draw_qr("https://example.com",
  x: 50, y: 50,
  max_width: 200, max_height: 200  # module_size calculated to fit
)

# 1D Barcodes
canvas.draw_barcode("ABC-123",
  x: 50, y: 300,
  symbology: :code128,       # :code128, :ean13, :ean8, :code39
  height: 60,                # bar height in pixels
  module_width: 2,           # narrowest bar width (default: 2)
  color: Color::BLACK,
  include_text: true,        # render human-readable text below (default: true)
  text_font: Font.default(size: 12)
)
```

### Architecture

Drawing methods are mixed into Surface via a new `Drawing::Codes` module:

```ruby
module Drawing
  module Codes
    def draw_qr(data, x:, y:, **options)
    def draw_barcode(data, x:, y:, symbology:, **options)
  end
end
```

**QR rendering**: Use `rqrcode` to generate the QR matrix, then draw each module as a
filled rectangle on the surface. Simple and direct — no intermediate image.

**Barcode rendering**: Use `barby` to generate the encoding, then draw each bar as a
filled rectangle. Optionally render human-readable text below using `draw_text`.

### Feature Dependencies

**Blocked by:** None
**Blocks:** None
**Note:** `draw_barcode` with `include_text: true` uses `draw_text`, which requires
FreeType (Feature 16 from the original roadmap — already complete). If FreeType is
unavailable at runtime and `include_text: true` is passed, it should raise
`DependencyError` rather than silently omitting the text.

### Gem Dependencies

```ruby
# In gemspec — optional runtime dependencies
spec.add_dependency "rqrcode", "~> 2.0"  # QR generation
spec.add_dependency "barby", "~> 0.6"    # 1D barcode generation
```

Both gems are **lazy-loaded** — `require 'rqrcode'` / `require 'barby'` happens on first use.
Missing gems raise `ChromaWave::DependencyError` with install instructions.

### Supported Symbologies

| Type | Symbology | Gem | Use Case |
|---|---|---|---|
| 2D | QR Code | rqrcode | URLs, config data, WiFi credentials |
| 1D | Code 128 | barby | General alphanumeric labels |
| 1D | EAN-13 | barby | Product barcodes (retail) |
| 1D | EAN-8 | barby | Small product labels |
| 1D | Code 39 | barby | Industrial / inventory |

### Files to Create

- `lib/chroma_wave/drawing/codes.rb` — `draw_qr`, `draw_barcode` methods
- `spec/chroma_wave/drawing/codes_spec.rb`

### Files to Modify

- `lib/chroma_wave/surface.rb` — include `Drawing::Codes`
- `chroma_wave.gemspec` — add optional dependencies

## Acceptance Criteria

- [ ] `canvas.draw_qr(data, x:, y:)` renders a QR code
- [ ] QR module_size is configurable or auto-calculated from max_width/max_height
- [ ] QR error correction levels (:low, :medium, :quartile, :high) work
- [ ] `canvas.draw_barcode(data, x:, y:, symbology: :code128)` renders a barcode
- [ ] Supported symbologies: Code 128, EAN-13, EAN-8, Code 39
- [ ] `include_text: true` renders human-readable text below barcodes
- [ ] Foreground and background colors are configurable
- [ ] Missing `rqrcode` / `barby` gems raise `DependencyError` with install hint
- [ ] Works on all Surface types (Canvas, Layer, Framebuffer)
- [ ] QR codes are scannable by real QR readers (validated manually or via test image)
- [ ] Specs cover rendering, auto-sizing, error correction, and missing-dependency fallback
