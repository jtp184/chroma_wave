# Feature 002: Display Rotation

## Decision

Rotation lives at the **Display level only**. `Canvas` always works in logical (rotated)
coordinates. The rotation is applied **post-render** via a C-accelerated
`Framebuffer#rotate` operation, just before hardware dispatch.
Width and height auto-swap for 90/270 degree rotations.

**Priority:** P0 (basic usability gap)
**Effort:** Medium
**Status:** Complete

## Dependencies

**Blocked by:** None
**Blocks:** None
**Enhances:**
- Feature 008 (Dirty Region Tracking) — dirty rects must be transformed through rotation
  when dispatching to `display_region`. Rotation should land first so 008 can account for it.
- Feature 009 (Preview Server) — preview should reflect the rotated orientation. Not
  blocking, but if 002 lands first the preview gets it for free.

---

## Design

### API

```ruby
# Rotation specified at construction
display = Display.new(model: :epd_2in13_v4, rotation: 90)

# Dimensions reflect the rotated orientation
display.width   # => 250 (was 122 in native portrait)
display.height  # => 122 (was 250 in native portrait)

# Canvas uses logical dimensions
canvas = Canvas.new(width: display.width, height: display.height)
canvas.draw_text("Hello", x: 10, y: 10, font: font, color: Color::BLACK)

# Display rotates the rendered framebuffer before SPI transfer
display.show(canvas)  # internally: render -> rotate -> display
```

### Supported Values

- `0` (default) — native orientation
- `90` — 90 degrees clockwise
- `180` — upside down
- `270` — 90 degrees counter-clockwise

Invalid values raise `ArgumentError`.

### Architecture

```
Canvas (logical coords, rotated w/h)
  |
  v
Renderer.render(canvas)
  |  - Iterates canvas pixels
  |  - Quantizes RGBA -> palette entries
  |  - Packs into Framebuffer in logical orientation
  v
Framebuffer (logical orientation, logical w/h)
  |
  v
Framebuffer#rotate(degrees)           ← C-accelerated, GVL-released
  |  - Creates new Framebuffer with native w/h
  |  - Pixel-by-pixel coordinate mapping
  v
Framebuffer (native orientation, native w/h)
  |
  v
Device._epd_display(framebuffer)      ← no change needed
```

**Design rationale:** Rotation was originally planned inside `Renderer#render`, but
moving it post-render to `Framebuffer#rotate` proved superior:
1. Renderer stays rotation-agnostic (single-responsibility)
2. C-accelerated pixel loop is faster than per-pixel coordinate mapping during rendering
3. Composes cleanly with DualBuffer (rotate both mono planes independently)
4. GVL release during rotation allows other Ruby threads to proceed

The rotation transform uses these coordinate mappings:

| Rotation | Mapping (x, y) -> (native_x, native_y) |
|---|---|
| 0   | (x, y) |
| 90  | (native_w - 1 - y, x) |
| 180 | (native_w - 1 - x, native_h - 1 - y) |
| 270 | (y, native_h - 1 - x) |

### Where Rotation State Lives

- `Display` stores `@rotation` (0, 90, 180, 270)
- `Display#width` / `#height` return rotated (logical) dimensions
- `Display#native_width` / `#native_height` return the hardware dimensions
- `Display#show` renders, then calls `fb.rotate(rotation)` before hardware dispatch
- `DualBuffer#show` rotates both mono planes independently after `render_dual`
- `RegionalRefresh#display_region` transforms region coordinates to native space,
  extracts only the sub-region, rotates that piece, and blits into a scratch buffer
- `MockDevice` mirrors rotation behavior from Display

### Files Modified

- `ext/chroma_wave/framebuffer.c` — added `rotate`, `extract`, `_fb_blit` C accelerators
  (GVL-released workers with `RB_GC_GUARD`); refactored pixel get/set into raw helpers
- `lib/chroma_wave/framebuffer.rb` — added `blit` override dispatching to C accelerator
- `lib/chroma_wave/display.rb` — `rotation:` constructor param, dimension swap,
  `native_width`/`native_height`, post-render rotate in `show`
- `lib/chroma_wave/capabilities/dual_buffer.rb` — rotate both planes after `render_dual`
- `lib/chroma_wave/capabilities/regional_refresh.rb` — coordinate transforms
  (`transform_region_to_native` / `transform_native_to_logical`), scratch buffer caching,
  sub-region extract+rotate optimization
- `lib/chroma_wave/registry.rb` — pass `rotation:` through factory
- `lib/chroma_wave/mock_device.rb` — composite screen replacing `@last_framebuffer`,
  `last_red_framebuffer`, `blit_region_to_composite`

### Files NOT Modified

- `ext/chroma_wave/device.c` — no changes, receives native-orientation framebuffer
- `lib/chroma_wave/canvas.rb` — no changes, works in logical coords
- `lib/chroma_wave/renderer.rb` — no changes, stays rotation-agnostic

## Acceptance Criteria

- [x] `Display.new(model:, rotation: 90)` works for 0, 90, 180, 270
- [x] Invalid rotation values raise `ArgumentError`
- [x] `display.width` / `display.height` swap correctly for 90/270
- [x] `display.native_width` / `display.native_height` always return hardware dims
- [x] A Canvas drawn at logical (10, 10) appears at the correct native position for each rotation
- [x] `MockDevice` respects rotation (PNG export shows rotated content)
- [x] All 4 pixel formats work correctly with all 4 rotations
- [x] Dual-buffer (DualBuffer capability) works with rotation
- [x] RegionalRefresh coordinates are correctly transformed
- [x] Specs cover pixel-level correctness for all 4 rotations x all 4 pixel formats
