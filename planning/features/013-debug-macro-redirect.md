# Feature 013: Redirect Vendor Debug() Macro

## Decision

Standalone quick fix. Redirect the Waveshare vendor library's `Debug()` macro to Ruby's
`rb_warn()` so that vendor debug output is captured by Ruby's warning system instead of
going to stderr or being silently discarded.

**Priority:** P3 (completeness — last unchecked ROADMAP item)
**Effort:** Small

## Dependencies

**Blocked by:** None
**Blocks:** None
**Note:** Completely independent of all other features. Touches only C build configuration
and vendor code. Can land at any time without affecting or being affected by other work.

---

## Design

### Current State

The vendor library (`vendor/waveshare_epd/`) defines a `Debug()` macro in `Debug.h` that
calls `printf` to stderr. When compiled into the ChromaWave extension, these messages go
directly to stderr, bypassing Ruby's warning infrastructure.

### Implementation

Override the `Debug()` macro in the extension's compilation to redirect to `rb_warn()`:

```c
// In chroma_wave.h or a dedicated header included before vendor code
#undef Debug
#define Debug(fmt, ...) rb_warn("ChromaWave [vendor]: " fmt, ##__VA_ARGS__)
```

Alternatively, if the vendor's `Debug.h` uses a guard:

```c
// In extconf.rb, add compiler flag
$CFLAGS << " -DDebug(...)=rb_warn(\"ChromaWave [vendor]: \" __VA_ARGS__)"
```

The cleanest approach depends on how the vendor macro is currently defined. Inspect
`vendor/waveshare_epd/Debug.h` to determine the right override mechanism.

### Considerations

- `rb_warn()` respects Ruby's `-W` warning level flags
- `rb_warn()` can be captured by `Warning.warn` for programmatic handling
- The `[vendor]` prefix makes it clear these messages originate from Waveshare code
- This should NOT change any behavior in the mock backend (no vendor code runs there)

### Files to Modify

- `ext/chroma_wave/chroma_wave.h` or `ext/chroma_wave/extconf.rb` — macro override
- Possibly `vendor/waveshare_epd/Debug.h` — if direct modification is cleaner

### Files to Create

- None (or a small spec if we can trigger vendor debug output)

## Acceptance Criteria

- [ ] Vendor `Debug()` calls go through `rb_warn()` instead of `printf`/`stderr`
- [ ] Messages are prefixed with `"ChromaWave [vendor]: "`
- [ ] Ruby's `-W0` flag silences vendor debug output
- [ ] `Warning.warn` can intercept vendor messages programmatically
- [ ] Mock backend compilation is unaffected
- [ ] No compilation warnings from the macro redefinition
- [ ] The ROADMAP Phase 2 Task 2 checkbox can be marked complete
