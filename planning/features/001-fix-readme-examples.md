# Feature 001: Fix README API Examples

## Decision

The README currently shows drawing primitives with `color:`, `fill:`, `stroke_width:` keyword
arguments, but the actual API uses a `Pen` value object. The Pen API is the correct design.
Update the README to match.

**Priority:** P0 (prevents new-user confusion on first contact)
**Effort:** Small (documentation only)

## Dependencies

**Blocked by:** None
**Blocks:** None
**Enhanced by:** Feature 002 (rotation examples should be included once rotation lands)

---

## Scope

Update all drawing primitive examples in `README.md` to use the `pen:` keyword with `Pen`
objects. Also update any code examples in `planning/` docs that reference the old API.

## Changes

### README.md

Replace all instances of the old pattern:

```ruby
canvas.draw_rect(10, 10, 200, 100, color: Color::BLACK, stroke_width: 2)
canvas.draw_rect(10, 120, 200, 80, color: Color::RED, fill: true)
```

With the correct Pen API:

```ruby
canvas.draw_rect(10, 10, 200, 100, pen: Pen.stroke(Color::BLACK, width: 2))
canvas.draw_rect(10, 120, 200, 80, pen: Pen.fill(Color::RED))
```

### Files to audit

- `README.md` (primary)
- `planning/API_REFERENCE.md`
- `planning/CONTENT_PIPELINE.md`
- Any other `.md` files referencing drawing methods

## Acceptance Criteria

- [ ] All drawing primitive examples in README use `pen:` keyword
- [ ] `Pen` class is introduced/explained before first use in examples
- [ ] `Pen.stroke()`, `Pen.fill()`, and `Pen.new()` patterns are all shown
- [ ] No stale `color:` / `fill:` / `stroke_width:` kwargs remain in docs
- [ ] Examples are runnable as-is (correct method signatures)
