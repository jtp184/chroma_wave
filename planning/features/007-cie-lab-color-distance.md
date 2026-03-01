# Feature 007: CIE Lab Color Distance

## Decision

Replace redmean RGB distance with **CIE Lab (Delta E)** for palette nearest-color matching.
This produces more perceptually accurate color quantization, which matters most for
multi-color displays (COLOR4, COLOR7, and future Spectra 6).

**Priority:** P2 (color accuracy)
**Effort:** Small

## Dependencies

**Blocked by:** None
**Blocks:** None
**Ordering note:** This changes `Palette#nearest_color` output, which affects all dithering
strategies. If Feature 003 (Atkinson) is planned for the same release, **land 007 first**
so Atkinson test expectations are written against CIE Lab distances from the start, avoiding
a re-baseline.
**Enhances:**
- Feature 012 (Spectra 6) — CIE Lab produces more accurate palette mapping for the
  6-color Spectra palette. Not blocking, but significantly improves quality.

---

## Design

### Background

The current `Palette#nearest_color` uses **redmean weighted Euclidean distance** in RGB space:

```ruby
# Current (redmean)
r_mean = (r1 + r2) / 2.0
dr = r1 - r2
dg = g1 - g2
db = b1 - b2
(2 + r_mean/256.0) * dr**2 + 4 * dg**2 + (2 + (255 - r_mean)/256.0) * db**2
```

Redmean is a reasonable approximation but doesn't account for the non-linearity of human
color perception. CIE Lab color space is designed to be perceptually uniform — equal
numerical distances correspond to equal perceived differences.

### CIE Lab Conversion

RGB -> CIE Lab requires two steps:

1. **RGB -> XYZ** (linear transform via sRGB matrix, with gamma decode)
2. **XYZ -> Lab** (non-linear transform relative to D65 white point)

```
sRGB (gamma)
  → Linear RGB (gamma decode: inverse companding)
    → CIE XYZ (3x3 matrix multiply, D65 reference)
      → CIE Lab (cube root transform)
```

### API

No public API change. The switch is internal to `Palette#nearest_color`:

```ruby
# Before (internal)
palette.nearest_color(Color.new(r: 200, g: 100, b: 100))
# Uses redmean distance → may return :red or :orange

# After (internal)
palette.nearest_color(Color.new(r: 200, g: 100, b: 100))
# Uses CIE Lab Delta E → more perceptually accurate match
```

### Implementation

Add a `Color#to_lab` method that returns `[l, a, b]` values. Cache the Lab conversion
on the Color object (it's immutable, so safe to memoize).

Replace the distance function in `Palette` with CIE76 Delta E:

```ruby
# CIE76 Delta E (simplest, sufficient for e-paper palettes)
delta_e = Math.sqrt((l1-l2)**2 + (a1-a2)**2 + (b1-b2)**2)
```

CIE76 is the simplest Delta E formula. More advanced variants (CIE94, CIEDE2000) exist
but are overkill for palettes with 2-7 colors.

### Performance Consideration

The LRU cache on `Palette#nearest_color` already memoizes results by packed RGBA key.
The Lab conversion and distance calculation only run on cache misses. Since e-paper palettes
have at most 7 colors, each cache miss computes at most 7 Lab distances. Performance
impact is negligible.

Pre-compute Lab values for all palette entries at `Palette` construction time (they're
immutable named colors, so this is a one-time cost).

### Files to Modify

- `lib/chroma_wave/color.rb` — add `#to_lab` method (sRGB -> XYZ -> Lab)
- `lib/chroma_wave/palette.rb` — replace redmean with CIE Lab Delta E
- `spec/chroma_wave/color_spec.rb` — specs for Lab conversion accuracy
- `spec/chroma_wave/palette_spec.rb` — verify improved nearest-color results

## Acceptance Criteria

- [ ] `Color#to_lab` returns `[l, a, b]` array with correct values
- [ ] Lab conversion matches known reference values (e.g., Color::RED -> [53.23, 80.11, 67.22])
- [ ] `Palette#nearest_color` uses CIE Lab Delta E instead of redmean
- [ ] LRU cache continues to work (performance unchanged for repeated lookups)
- [ ] Lab values for palette entries are pre-computed at construction
- [ ] All existing dithering specs still pass (behavior may change slightly — update expected values)
- [ ] Named colors map to themselves (Color::RED nearest to [:red] palette -> :red)
- [ ] Perceptual edge cases improve (e.g., dark green closer to black than to green in
  COLOR7 palette, matching human perception)
- [ ] MONO and GRAY4 behavior is unchanged (only 2-4 entries, same mapping regardless)
