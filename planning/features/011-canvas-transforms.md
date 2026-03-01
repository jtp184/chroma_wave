# Feature 011: Canvas Transforms

## Decision

Add basic image transforms directly on Canvas: flip horizontal/vertical, scale, and crop.
Returns new Canvas instances (immutable transform pattern). Complements the Image class
which handles file-based transforms — these operate on in-memory Canvas content.

**Priority:** P2 (usability)
**Effort:** Small

## Dependencies

**Blocked by:** None
**Blocks:** None
**Note:** Canvas transforms are independent of Display rotation (Feature 002). Rotation
operates at the Renderer level during Canvas-to-Framebuffer conversion. Canvas transforms
(flip/scale/crop) produce new Canvas instances and have no interaction with the rendering
pipeline. The two features can land in any order.

---

## Design

### API

```ruby
canvas = Canvas.new(width: 200, height: 100)
# ... draw content ...

# Flip
flipped_h = canvas.flip(:horizontal)   # => new Canvas, mirror left-right
flipped_v = canvas.flip(:vertical)      # => new Canvas, mirror top-bottom

# Scale
scaled = canvas.scale(2.0)              # => new Canvas, 400x200 (nearest-neighbor)
scaled = canvas.scale(0.5)              # => new Canvas, 100x50
scaled = canvas.scale(width: 300)       # => new Canvas, 300x150 (preserve aspect ratio)
scaled = canvas.scale(height: 50)       # => new Canvas, 100x50 (preserve aspect ratio)
scaled = canvas.scale(width: 300, height: 200)  # => new Canvas, exact size (may distort)

# Crop
cropped = canvas.crop(x: 10, y: 10, width: 50, height: 50)  # => new Canvas, 50x50

# Chaining
result = canvas
  .crop(x: 10, y: 10, width: 180, height: 80)
  .flip(:horizontal)
  .scale(2.0)
```

### Implementation

All transforms create **new Canvas instances**. The original Canvas is never modified.

**Flip:**
```ruby
def flip(direction)
  Canvas.new(width: width, height: height).tap do |dest|
    height.times do |y|
      width.times do |x|
        src_x = direction == :horizontal ? width - 1 - x : x
        src_y = direction == :vertical ? height - 1 - y : y
        dest.set_pixel(x, y, get_pixel(src_x, src_y))
      end
    end
  end
end
```

Optimization: operate on raw `rgba_bytes` buffer directly (copy rows/reverse rows)
instead of per-pixel get/set.

**Scale:**

Use nearest-neighbor interpolation for integer scale factors (crisp for e-paper).
Use bilinear interpolation for non-integer factors (smoother gradients).

For the common case of integer downscaling (e.g., 2x, 4x), use area averaging
which produces better results than point sampling.

**Crop:**

Extract a rectangular sub-region. Copy pixel data from the source buffer directly
(row-by-row memcpy on the raw buffer).

### C Accelerators (Optional)

If performance matters, add C accelerators for flip and scale that operate on the
raw RGBA buffer. Follow the existing pattern: `_canvas_flip`, `_canvas_scale` private
methods with Ruby fallbacks.

For v1, Ruby-only is fine — these are one-shot operations, not per-frame.

### Files to Modify

- `lib/chroma_wave/canvas.rb` — add `flip`, `scale`, `crop` methods

### Files to Create

- `spec/chroma_wave/canvas_transforms_spec.rb`

## Acceptance Criteria

- [ ] `canvas.flip(:horizontal)` returns a new horizontally-mirrored Canvas
- [ ] `canvas.flip(:vertical)` returns a new vertically-mirrored Canvas
- [ ] Invalid flip direction raises `ArgumentError`
- [ ] `canvas.scale(factor)` scales uniformly by the given factor
- [ ] `canvas.scale(width:)` scales to width, preserving aspect ratio
- [ ] `canvas.scale(height:)` scales to height, preserving aspect ratio
- [ ] `canvas.scale(width:, height:)` scales to exact dimensions
- [ ] Scale factor of 0 or negative raises `ArgumentError`
- [ ] `canvas.crop(x:, y:, width:, height:)` extracts a sub-region
- [ ] Crop with out-of-bounds coordinates clips to canvas bounds
- [ ] Crop with zero width/height raises `ArgumentError`
- [ ] All transforms return new Canvas instances (original unchanged)
- [ ] Transforms are chainable
- [ ] Pixel data is correct after each transform (round-trip verified)
- [ ] Specs cover edge cases: 1x1 canvas, single-row, single-column, full-size crop
