# Feature 002: Display Rotation

## Decision

Rotation lives at the **Display level only**. `Canvas` always works in logical (rotated)
coordinates. The rotation is applied at render time when converting Canvas to Framebuffer.
Width and height auto-swap for 90/270 degree rotations.

**Priority:** P0 (basic usability gap)
**Effort:** Medium

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

# Renderer handles coordinate transformation
display.show(canvas)  # internally rotates framebuffer pixels before SPI transfer
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
Renderer.render(canvas, rotation:)
  |  - Iterates canvas pixels
  |  - Maps (x, y) -> (native_x, native_y) based on rotation
  |  - Packs into Framebuffer in native orientation
  v
Framebuffer (native orientation, native w/h)
  |
  v
Device._epd_display(framebuffer)  # no change needed
```

The rotation transform is a simple coordinate mapping applied during rendering:

| Rotation | Mapping (x, y) -> (native_x, native_y) |
|---|---|
| 0   | (x, y) |
| 90  | (native_w - 1 - y, x) |
| 180 | (native_w - 1 - x, native_h - 1 - y) |
| 270 | (y, native_h - 1 - x) |

### Where Rotation State Lives

- `Display` stores `@rotation` (0, 90, 180, 270)
- `Display#width` / `#height` return rotated dimensions
- `Display#native_width` / `#native_height` return the hardware dimensions
- `Renderer#render` accepts `rotation:` parameter
- `Display#show` passes `rotation:` to the renderer automatically
- `MockDevice` inherits rotation behavior from Display

### Files to Modify

- `lib/chroma_wave/display.rb` — add `rotation:` to constructor, swap width/height
- `lib/chroma_wave/renderer.rb` — add rotation coordinate mapping to render loop
- `lib/chroma_wave/registry.rb` — pass rotation through factory
- `lib/chroma_wave/mock_device.rb` — inherit rotation from Display
- `spec/chroma_wave/display_spec.rb` — rotation construction, dimension swap
- `spec/chroma_wave/renderer_spec.rb` — pixel mapping correctness for all 4 rotations

### Files NOT Modified

- `ext/chroma_wave/device.c` — no changes, receives native-orientation framebuffer
- `ext/chroma_wave/framebuffer.c` — no changes, always native dimensions
- `lib/chroma_wave/canvas.rb` — no changes, works in logical coords

## Acceptance Criteria

- [ ] `Display.new(model:, rotation: 90)` works for 0, 90, 180, 270
- [ ] Invalid rotation values raise `ArgumentError`
- [ ] `display.width` / `display.height` swap correctly for 90/270
- [ ] `display.native_width` / `display.native_height` always return hardware dims
- [ ] A Canvas drawn at logical (10, 10) appears at the correct native position for each rotation
- [ ] `MockDevice` respects rotation (PNG export shows rotated content)
- [ ] All 4 pixel formats work correctly with all 4 rotations
- [ ] Dual-buffer (DualBuffer capability) works with rotation
- [ ] RegionalRefresh coordinates are correctly transformed
- [ ] Specs cover pixel-level correctness for all 4 rotations x all 4 pixel formats
