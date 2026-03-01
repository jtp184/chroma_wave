# Feature 012: Spectra 6 Preparation

## Decision

**Defer full support until hardware is available** for validation. Add the pixel format
definition and palette now (so the architecture is ready), but don't claim driver support
for Spectra 6 models until tested on real hardware.

**Priority:** P3 (forward-looking)
**Effort:** Small (format definition only)

## Dependencies

**Blocked by:** None (format definition is independent)
**Blocks:** None (full Spectra 6 driver support is deferred to hardware availability)
**Enhanced by:**
- Feature 007 (CIE Lab) — CIE Lab color distance produces significantly more accurate
  palette mapping for the 6-color Spectra palette than redmean. The difference is
  especially pronounced for green and blue entries. Landing 007 first is recommended
  but not required — the format definition works with either distance function.
- Feature 003 (Atkinson) — Atkinson dithering with a 6-color palette produces better
  results for text/UI content than Floyd-Steinberg. Nice-to-have, not blocking.

---

## Design

### What to Do Now

1. Define `PixelFormat::COLOR6` with the Spectra 6 palette
2. Add the palette to the color system
3. Ensure the Renderer and dithering strategies work with 6-color palettes
4. Do NOT add Spectra 6 model configs to the driver registry yet

### Pixel Format

```ruby
PixelFormat::COLOR6 = PixelFormat.new(
  name: :color6,
  bits_per_pixel: 4,    # same as COLOR7, 4-bit packed
  palette: Palette[:black, :white, :red, :green, :blue, :yellow]
)
```

Note: Spectra 6 uses 6 colors vs ACeP's 7 (no orange). Both use 4-bit packing.

### Palette Colors

| Index | Color | RGB |
|---|---|---|
| 0 | Black | (0, 0, 0) |
| 1 | White | (255, 255, 255) |
| 2 | Red | (255, 0, 0) |
| 3 | Green | (0, 128, 0) |
| 4 | Blue | (0, 0, 255) |
| 5 | Yellow | (255, 255, 0) |

(Actual display color points TBD — will need calibration against real hardware.
These are placeholder sRGB approximations.)

### What to Defer

- Driver configs for EPD_3in6e, EPD_4in0e, EPD_7in3e, EPD_13in3e
- Tier 2 overrides for Spectra 6 init/display sequences
- Dual-buffer behavior (Spectra 6 may use a different buffer strategy than ACeP)
- Color calibration (actual display gamut measurement)

### Files to Modify

- `lib/chroma_wave/pixel_format.rb` — add `COLOR6` constant
- `ext/chroma_wave/chroma_wave.h` — add `PIXEL_FORMAT_COLOR6` enum value
- `ext/chroma_wave/framebuffer.c` — handle COLOR6 packing (same as COLOR7 4-bit)
- `spec/chroma_wave/pixel_format_spec.rb` — specs for COLOR6

## Acceptance Criteria

- [ ] `PixelFormat::COLOR6` exists with correct metadata
- [ ] `PixelFormat.from_name(:color6)` works
- [ ] Framebuffer can pack/unpack COLOR6 pixels (4-bit, same as COLOR7)
- [ ] Renderer can render Canvas to COLOR6 Framebuffer
- [ ] All dithering strategies work with COLOR6
- [ ] CIE Lab nearest-color produces reasonable mappings for 6-color palette
- [ ] No Spectra 6 display models are registered in the driver registry yet
- [ ] A comment/note documents that driver support requires hardware validation
