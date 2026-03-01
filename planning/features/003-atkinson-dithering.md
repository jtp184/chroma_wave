# Feature 003: Atkinson Dithering

## Decision

Add **Atkinson dithering only** as a new strategy. It's the community standard for e-ink
displays due to its high contrast preservation, making it ideal for text-heavy UIs and
illustrations. Other algorithms (Sierra Lite, Stucki, etc.) are deferred.

**Priority:** P1 (community expectation)
**Effort:** Small

## Dependencies

**Blocked by:** None
**Blocks:** None
**Note:** If Feature 007 (CIE Lab) lands first, the dithering error values will be computed
against CIE Lab distances rather than redmean. This changes the quantization output but does
not affect the Atkinson algorithm itself. Either ordering works — but if both are planned for
the same release, land 007 first to avoid re-baselining test expectations twice.

---

## Design

### API

```ruby
renderer = Renderer.new(pixel_format: PixelFormat::MONO, dither: :atkinson)
fb = renderer.render(canvas)

Dither.strategies  # => [:floyd_steinberg, :ordered, :threshold, :atkinson]
```

### Algorithm

Atkinson dithering is an error-diffusion algorithm created by Bill Atkinson for the original
Macintosh. It diffuses only 6/8 (75%) of the quantization error, which intentionally loses
some tonal range but preserves hard edges and high contrast.

**Error diffusion kernel** (1/8 of error to each marked neighbor):

```
        *   1   1
    1   1   1
        1
```

Where `*` is the current pixel. Each `1` receives 1/8 of the error.
Total distributed: 6/8. Remaining 1/4 is discarded (the key difference from Floyd-Steinberg).

### Characteristics vs Floyd-Steinberg

| Property | Floyd-Steinberg | Atkinson |
|---|---|---|
| Error distributed | 100% (16/16) | 75% (6/8) |
| Diffusion reach | 4 neighbors | 6 neighbors |
| Contrast | Lower (smooth gradients) | Higher (sharper edges) |
| Best for | Photos, gradients | Text, UI, illustrations |
| Tonal range | Full | Loses extreme lights/darks |

### Implementation

New file: `lib/chroma_wave/dither/atkinson.rb`

Follow the same pattern as `lib/chroma_wave/dither/floyd_steinberg.rb`:

- Implement `Dither::Atkinson` class
- Include `Dither::Strategy` module (or follow existing duck-type contract)
- Register in `Dither.strategies` / `Dither.resolve`
- Use a 2-row error buffer ring (same as Floyd-Steinberg, but extend to 3 rows for the
  extra diffusion reach — the kernel extends 2 rows down)

### Files to Create

- `lib/chroma_wave/dither/atkinson.rb` — algorithm implementation

### Files to Modify

- `lib/chroma_wave/dither.rb` — register `:atkinson` in strategy resolution
- `spec/chroma_wave/dither/atkinson_spec.rb` — new spec file

## Acceptance Criteria

- [ ] `Dither.resolve(:atkinson, pixel_format:)` returns an Atkinson strategy
- [ ] `Dither.strategies` includes `:atkinson`
- [ ] Atkinson produces visibly higher contrast than Floyd-Steinberg on test images
- [ ] Works correctly with all 4 pixel formats (MONO, GRAY4, COLOR4, COLOR7)
- [ ] Error is distributed to exactly 6 neighbors at 1/8 each (75% total)
- [ ] Edge pixels handle boundary conditions correctly (no out-of-bounds writes)
- [ ] Specs verify pixel-level output against known-good reference
- [ ] Specs verify that Atkinson discards 25% of error (distinguishing feature)
