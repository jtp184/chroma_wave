# Feature 004: Smart Refresh Scheduler

## Decision

Built-in but **opt-in**. A `RefreshScheduler` module that auto-tracks partial refresh counts,
enforces minimum intervals between refreshes, and triggers full refresh at configurable
thresholds. Prevents hardware damage and ghosting per Waveshare's recommendations.

**Priority:** P1 (hardware safety)
**Effort:** Medium

## Dependencies

**Blocked by:** None
**Blocks:** None
**Enhances:**
- Feature 008 (Dirty Region Tracking) — `show_dirty` triggers partial/regional refreshes
  that the scheduler should track. If both are planned, the scheduler's `ManagedRefresh`
  module should wrap `show_dirty` in addition to `display_partial` and `show`. Either
  ordering works — the integration point is small.

---

## Design

### API

```ruby
# Opt-in via constructor
display = Display.new(model: :epd_2in13_v4, managed_refresh: true)

# Or with custom thresholds
display = Display.new(model: :epd_2in13_v4, managed_refresh: {
  partial_limit: 5,          # full refresh after N partials (default: 5)
  min_interval: 180,         # minimum seconds between refreshes (default: 180)
  auto_full_refresh: true    # auto-trigger full refresh at limit (default: true)
})

# Usage is transparent — the scheduler wraps existing methods
display.display_partial(fb)   # tracked
display.display_partial(fb)   # tracked
display.display_partial(fb)   # tracked
display.display_partial(fb)   # tracked
display.display_partial(fb)   # 5th partial: auto-triggers full refresh first, then partial

# Manual query
display.refresh_scheduler.partial_count    # => 0 (reset after full refresh)
display.refresh_scheduler.last_refresh_at  # => Time
display.refresh_scheduler.needs_full?      # => false
display.refresh_scheduler.reset!           # manual reset

# Interval enforcement
display.show(canvas)
display.show(canvas)  # warns via rb_warn if < min_interval seconds elapsed
```

### Architecture

```ruby
# New class: RefreshScheduler
class RefreshScheduler
  def initialize(partial_limit: 5, min_interval: 180, auto_full_refresh: true)
  def track_partial!         # increment counter, check threshold
  def track_full!            # reset counter
  def check_interval!        # warn if too soon
  def needs_full?            # partial_count >= partial_limit
  def reset!                 # manual counter reset
end
```

The scheduler is injected into Display via a **capability module** (`Capabilities::ManagedRefresh`)
that wraps `display_partial`, `display_fast`, and `show`:

```
display_partial(fb)
  → check_interval!
  → needs_full? → auto full refresh if configured
  → delegate to original display_partial
  → track_partial!

show(fb)
  → check_interval!
  → delegate to original show
  → track_full!
```

### Behavior Details

- **Partial limit**: After N partial refreshes, the next partial automatically triggers a
  full refresh first (if `auto_full_refresh: true`), then proceeds with the partial.
  Counter resets on full refresh.
- **Interval warning**: If less than `min_interval` seconds have elapsed since the last
  refresh, `rb_warn` is called with a message. The refresh still proceeds (non-blocking).
- **Thread safety**: Counter and timestamp are protected by the existing Display mutex.
- **MockDevice**: RefreshScheduler works with MockDevice for testing (no special handling needed).

### Files to Create

- `lib/chroma_wave/refresh_scheduler.rb` — scheduler logic
- `lib/chroma_wave/capabilities/managed_refresh.rb` — capability module
- `spec/chroma_wave/refresh_scheduler_spec.rb`
- `spec/chroma_wave/capabilities/managed_refresh_spec.rb`

### Files to Modify

- `lib/chroma_wave/display.rb` — accept `managed_refresh:` option, include module when enabled
- `lib/chroma_wave/registry.rb` — pass `managed_refresh:` through factory

## Acceptance Criteria

- [ ] `Display.new(model:, managed_refresh: true)` enables the scheduler with defaults
- [ ] `Display.new(model:, managed_refresh: { partial_limit: 10 })` accepts custom thresholds
- [ ] Partial refresh counter increments on `display_partial` and `display_fast`
- [ ] Counter resets on `show` (full refresh) and `clear`
- [ ] Auto-full-refresh triggers at threshold, then proceeds with partial
- [ ] Interval warning fires via `warn` when refresh is too frequent
- [ ] `refresh_scheduler.partial_count`, `.last_refresh_at`, `.needs_full?` work
- [ ] Thread-safe (concurrent calls don't corrupt counter)
- [ ] Works with MockDevice (scheduler tracks mock operations)
- [ ] Disabled by default (no behavior change for existing users)
- [ ] Specs cover threshold trigger, interval warning, reset, and thread safety
