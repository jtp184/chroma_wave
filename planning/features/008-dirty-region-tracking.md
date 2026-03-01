# Feature 008: Dirty Region Tracking

## Decision

**Canvas-level dirty region tracking.** Canvas tracks a dirty rectangle (bounding box of all
mutations since last render). Renderer only processes the dirty region. Display uses regional
refresh on capable models, falls back to full refresh otherwise.

**Priority:** P2 (performance for partial updates)
**Effort:** Medium

## Dependencies

**Blocked by:** None
**Blocks:** None
**Recommended ordering:**
- Feature 002 (Rotation) should land first. `show_dirty` dispatches to `display_region`,
  which must account for rotation when mapping logical dirty rects to native hardware
  coordinates. If rotation isn't implemented yet, `show_dirty` can skip the transform,
  but it will need to be revisited when rotation lands — landing 002 first avoids rework.
- Feature 004 (Refresh Scheduler) — if both land, the scheduler's `ManagedRefresh` module
  should wrap `show_dirty` to track partial refreshes triggered by dirty updates. Small
  integration point, either ordering works.

---

## Design

### API

```ruby
canvas = Canvas.new(width: 800, height: 480)

# Initial full render
display.show(canvas)

# Small update — only the changed region is tracked
canvas.draw_text("73°F", x: 100, y: 200, font: big_font, color: Color::BLACK)

# Query the dirty region
canvas.dirty_region  # => { x: 100, y: 200, width: 80, height: 40 } or nil if clean

# Smart show: renders only dirty region, uses regional refresh if available
display.show_dirty(canvas)   # renders dirty rect, refreshes that region
display.show(canvas)         # always full render + full refresh (unchanged)

# Manual dirty management
canvas.mark_dirty(x: 0, y: 0, width: 100, height: 100)  # explicit dirty rect
canvas.clean!                # reset dirty tracking (after manual render)
```

### Architecture

**Canvas tracks a dirty bounding box:**

```ruby
class Canvas
  # After every mutation (set_pixel, draw_*, blit, clear, load_rgba_bytes):
  #   expand @dirty_rect to include the affected region

  def dirty_region
    @dirty_rect&.to_h  # { x:, y:, width:, height: } or nil
  end

  def dirty?
    !@dirty_rect.nil?
  end

  def clean!
    @dirty_rect = nil
  end
end
```

**Display#show_dirty orchestrates the optimized path:**

```
canvas.dirty_region
  |
  v (nil → no-op, return early)
  |
  v (has dirty rect)
Renderer.render_region(canvas, region)
  |  - Only iterates pixels within the dirty rect
  |  - Produces a region-sized Framebuffer (or patches into existing FB)
  v
Display.display_region(fb, x:, y:, width:, height:)  [if RegionalRefresh capable]
  or
Display.show(full_fb)  [fallback: re-render full frame]
  |
  v
canvas.clean!  # reset dirty tracking
```

### Dirty Rect Expansion

Every mutation expands the bounding box:

```ruby
def expand_dirty(x, y, width, height)
  if @dirty_rect
    @dirty_rect = @dirty_rect.union(x, y, width, height)
  else
    @dirty_rect = Rect.new(x, y, width, height)
  end
end
```

### Which Methods Track Dirty Regions

| Method | Dirty region |
|---|---|
| `set_pixel(x, y, color)` | 1x1 at (x, y) |
| `clear(color)` | Full canvas |
| `blit(src, x:, y:)` | src.width x src.height at (x, y) |
| `load_rgba_bytes(...)` | w x h at (x, y) |
| `fill_rect(x, y, w, h, color)` | w x h at (x, y) |
| `draw_line(...)` | Bounding box of line endpoints + stroke width |
| `draw_rect(...)` | Given rect + stroke width |
| `draw_circle(...)` | Bounding box of circle + stroke width |
| `draw_text(...)` | TextMetrics bounds at (x, y) |
| `flood_fill(...)` | Full canvas (conservative — flood extent unknown in advance) |

### Value Type: Rect

```ruby
Rect = Data.define(:x, :y, :width, :height) do
  def union(ox, oy, ow, oh)
    nx = [x, ox].min
    ny = [y, oy].min
    Rect.new(
      x: nx, y: ny,
      width: [x + width, ox + ow].max - nx,
      height: [y + height, oy + oh].max - ny
    )
  end

  def to_h = { x:, y:, width:, height: }
end
```

### Files to Create

- `lib/chroma_wave/rect.rb` — Rect value type with `#union`
- `spec/chroma_wave/rect_spec.rb`
- `spec/chroma_wave/dirty_tracking_spec.rb`

### Files to Modify

- `lib/chroma_wave/canvas.rb` — add dirty tracking to all mutation methods
- `lib/chroma_wave/renderer.rb` — add `render_region` method
- `lib/chroma_wave/display.rb` — add `show_dirty` method
- `lib/chroma_wave/surface.rb` — add `expand_dirty` hook for drawing primitives
- `spec/chroma_wave/canvas_spec.rb` — dirty region tracking specs

## Acceptance Criteria

- [ ] `canvas.dirty?` returns false on a fresh canvas
- [ ] `canvas.dirty?` returns true after any mutation
- [ ] `canvas.dirty_region` returns the bounding box of all changes since last `clean!`
- [ ] Multiple mutations expand the dirty rect (union of all affected areas)
- [ ] `canvas.clean!` resets dirty tracking
- [ ] `display.show_dirty(canvas)` renders only the dirty region
- [ ] On RegionalRefresh-capable displays, `show_dirty` uses `display_region`
- [ ] On non-RegionalRefresh displays, `show_dirty` falls back to full refresh
- [ ] `display.show_dirty(canvas)` is a no-op when canvas is clean
- [ ] `display.show_dirty` calls `canvas.clean!` after successful refresh
- [ ] `display.show(canvas)` is unchanged (always full render, does NOT call clean!)
- [ ] Drawing primitives (line, rect, circle, text) correctly expand dirty rect
- [ ] Dirty tracking has negligible performance overhead on drawing operations
- [ ] Layer mutations propagate dirty regions to the parent Canvas
