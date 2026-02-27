# ChromaWave Implementation Roadmap

Task breakdown for the C extension and Ruby library. Derived from the architecture in
[EXTENSION_STRATEGY.md](EXTENSION_STRATEGY.md), with code contracts in
[API_REFERENCE.md](API_REFERENCE.md) and content details in
[CONTENT_PIPELINE.md](CONTENT_PIPELINE.md).

---

## Phase Overview

```
Phase 1: C Foundation                ✅ COMPLETE (branch: feature/groundwork-phase-1)
  ├── 1.  Framebuffer pixel packing  ✅
  ├── 1a. Error hierarchy            ✅  (added during Phase 1)
  ├── 2.  Device I/O primitives      ⚠️  C-level done; Ruby wrapper deferred
  ├── 3.  Two-tier driver registry   ⚠️  Tier 1 complete; Tier 2 overrides are stubs
  └── 3a. Driver extraction pipeline ✅  (added during Phase 1)
          │
Phase 2: Core Value Types          ✅ COMPLETE (branch: feature/groundwork-phase-2)
  ├── 4. PixelFormat & Palette     ✅
  └── 5. Color                     ✅
          │
Phase 3: Drawing Architecture      ✅ COMPLETE (branch: feature/groundwork-phase-3)
  ├── 6. Surface protocol           ✅
  ├── 7. Canvas (packed String)     ✅
  ├── 8. Canvas C accelerators      ✅
  ├── 9. Drawing primitives         ✅
  └── 10. Layer                     ✅
          │
Phase 4: Rendering & Display       ← depends on Phases 1-3
  ├── 11. Renderer (Canvas → Framebuffer)
  ├── 12. Display capability modules
  ├── 13. Compile all drivers
  ├── 14. GVL release for refresh
  └── 15. Busy-wait timeout          ⚠️  C-level polling done; Ruby integration deferred
          │
Phase 5: Content Pipeline          ← depends on Phase 3 (draws onto Surfaces)
  ├── 16. FreeType bindings
  ├── 17. IconFont + Lucide
  └── 18. Image (ruby-vips)
          │
Phase 6: Build & Platform          ← can start early, but final integration last
  ├── 19. extconf.rb platform detection ⚠️  Stub only
  ├── 20. Mock backend (C-level)     ✅
  ├── 21. MockDevice (Ruby-level)
  ├── 22. CI/CD pipeline             ✅  (added during Phase 1)
  └── 23. Code coverage              ✅  (added during Phase 1)
```

---

## 🏗️ Phase 1: C Foundation ✅

The bedrock C layer — pixel storage, hardware I/O, and driver dispatch.

### 1. Extract pixel-packing core ✅

Extract `Paint_SetPixel` and `Paint_Clear` (~100 lines) from the vendor's `GUI_Paint.c` into
a standalone `framebuffer.c`. Parameterize with a `framebuffer_t` struct — no global state.

- [x] Define `framebuffer_t` struct (buffer ptr, width, height, bits_per_pixel, pixel_format enum)
- [x] Extract pixel-packing logic for all 4 formats (1-bit MONO, 2-bit GRAY4, 4-bit COLOR4, 8-bit COLOR7)
- [x] Extract `clear` (format-aware memset)
- [x] Implement `get_pixel` (reverse of packing)
- [x] Wrap with `TypedData_Wrap_Struct` (`dfree` → `xfree`, `dsize` → buffer_size, `RUBY_TYPED_FREE_IMMEDIATELY`)
- [x] Separate `alloc_func` from `initialize`
- [x] Expose Ruby methods: `set_pixel`, `get_pixel`, `clear`, `width`, `height`, `bytes` (raw buffer)
- [x] Unit tests for pack/unpack round-trip on all 4 formats

Also implemented beyond spec: `initialize_copy` (deep copy for `dup`/`clone`), `#==` (value equality), `#inspect`, dimension cap validation.

**Files:** `ext/chroma_wave/framebuffer.c`, `ext/chroma_wave/framebuffer.h`
**Refs:** [EXTENSION_STRATEGY.md §2.2](EXTENSION_STRATEGY.md#22-responsibility-matrix), [API_REFERENCE.md §2](API_REFERENCE.md#2-surface-protocol--implementations)
**Depends on:** —
**Acceptance:** ✅ All 4 pixel formats pack/unpack correctly. `TypedData` reports accurate `dsize`.

---

### 1a. Error hierarchy ✅

Custom exception classes for structured error handling across all phases.

- [x] `ChromaWave::Error` base class
- [x] `ChromaWave::TimeoutError`, `ChromaWave::DeviceError`, etc.
- [x] Specs for error hierarchy

**Files:** `lib/chroma_wave/error.rb`
**Depends on:** —

---

### 2. Factor Device I/O primitives ⚠️ C-level done

Move `Reset()`, `SendCommand()`, `SendData()`, `ReadBusy()` out of the 70 per-driver files
into shared Device-level functions parameterized by model config. Eliminates ~1,400 lines of
duplicated C code.

- [x] Define `epd_reset(device, config)` — parameterized by `reset_ms` timing from config
- [x] Define `epd_send_command(device, cmd)` — CS/DC pin toggling + SPI write
- [x] Define `epd_send_data(device, data, len)` — single-byte and bulk variants
- [x] Define `epd_read_busy(device, config)` — parameterized by busy polarity from config
- [ ] Wrap Device SPI/GPIO lifecycle in a `device_t` struct with `TypedData` GC integration
- [ ] Implement `Device.open { |d| ... }` block form and explicit `#close`
- [ ] Thread safety via Ruby `Mutex` on all hardware operations
- [ ] Redirect vendor `Debug()` macro to `rb_warn()`

The C-internal functions (`epd_reset`, `epd_send_command`, `epd_send_data`, `epd_send_data_bulk`, `epd_read_busy`) are fully implemented and used by the driver registry. The Ruby-visible `Device` class wrapping these functions is deferred to Phase 4 when the Display layer is built.

**Files:** `ext/chroma_wave/device.c`, `ext/chroma_wave/device.h`
**Refs:** [EXTENSION_STRATEGY.md §3.6](EXTENSION_STRATEGY.md#36-device-owns-io-primitives), [WAVESHARE_LIBRARY.md](WAVESHARE_LIBRARY.md)
**Depends on:** —
**Acceptance:** ⚠️ C-level I/O primitives serve all drivers. Ruby wrapper and block form deferred.

---

### 3. Build two-tier driver registry ⚠️ Tier 1 complete, Tier 2 stubs

Static config data for simple models (Tier 1), optional code overrides for complex ones
(Tier 2, ~20 models).

- [x] Define `epd_model_config_t` (resolution, pixel_format, busy_polarity, reset_timing, init_sequence, display_cmd, capability_flags)
- [x] Define `epd_driver_t` (optional function pointers: `custom_init`, `custom_display`, `pre_display`, `post_display`)
- [x] Implement `epd_generic_init()` that interprets `init_sequence` byte arrays — full bytecode interpreter with 7 opcodes
- [x] Implement `epd_generic_display()` that sends buffer via the configured display command
- [x] Register all ~70 models as config entries — auto-generated via `rake generate:driver_configs`
- [ ] Write Tier 2 overrides for complex models (~20: EPD_4in2 LUT selection, EPD_3in7, EPD_5in65f power cycle, EPD_7in5_V2 buffer inversion, etc.)
- [ ] Handle EPD_7in5_V2 buffer inversion with a pre-send copy (see [§5.4](EXTENSION_STRATEGY.md#54-epd_7in5_v2-destructive-buffer-inversion))
- [ ] Handle EPD_5in65f dual busy polarity in its Tier 2 override (see [§5.5](EXTENSION_STRATEGY.md#55-epd_5in65f-dual-busy-polarity))

The Tier 1 infrastructure is complete: all 70 models have config entries in `driver_configs_generated.h`, the generic init/display/sleep functions work, and the Ruby API exposes `.model_count`, `.model_names`, `.model_config(name)`. The 25 Tier 2 models are identified and wired into the infrastructure, but `tier2_overrides.c` is intentionally empty — they fall through to the generic implementation until real overrides are written.

Also implemented: `epd_generic_sleep()` for power management.

#### 3a. Driver config extraction pipeline ✅

A fully-tested Ruby toolchain that parses all ~70 Waveshare vendor `.c`/`.h` file pairs,
extracts hardware configuration (dimensions, init sequences, capability flags, busy polarity,
display/sleep commands, tier classification), encodes init sequences into the bytecode opcode
format, and generates `driver_configs_generated.h`. This is what produced the 70-model
config data for Task 3.

- [x] `SourceParser` — parses vendor C source files with modular concerns
- [x] `HeaderGenerator` — generates the C header with all model config structs
- [x] `Runner` — orchestrates parsing and generation
- [x] `DriverConfig` — value object for a single model's extracted config
- [x] `Opcodes` — bytecode opcode constants shared between Ruby extraction and C interpreter
- [x] `Patterns` — regex patterns for vendor C source parsing
- [x] `rake generate:driver_configs` — Rake task to regenerate the header
- [x] Full RSpec coverage for `SourceParser`, `HeaderGenerator`, and `Runner`

**Files:** `lib/chroma_wave/driver_extraction.rb`, `lib/chroma_wave/driver_extraction/*.rb`, `Rakefile`

**Files (registry):** `ext/chroma_wave/driver_registry.c`, `ext/chroma_wave/driver_registry.h`, `ext/chroma_wave/driver_configs_generated.h`, `ext/chroma_wave/tier2_overrides.c`
**Refs:** [EXTENSION_STRATEGY.md §3.5](EXTENSION_STRATEGY.md#35-two-tier-driver-registry), [API_REFERENCE.md §5](API_REFERENCE.md#5-two-tier-driver-registry-c)
**Depends on:** Task 2 (uses Device I/O primitives)
**Acceptance:** ⚠️ Simple models work from config-only entries. Tier 2 overrides deferred. Adding a new simple model is ~10 lines of config data.

---

## 🧱 Phase 2: Core Value Types ✅

Ruby value objects that unify the concept of "how pixels are packed" and "what colors exist."

### 4. PixelFormat and Palette ✅

`PixelFormat` unifies the vendor's `Scale`, color constants, and buffer-size math into one
concept. `Palette` is its color lookup table.

- [x] Implement `PixelFormat` as `Data.define(:name, :bits_per_pixel, :palette)`
- [x] Define four format constants: `MONO`, `GRAY4`, `COLOR4`, `COLOR7`
- [x] Implement `Palette` as an `Enumerable` with `nearest_color` (memoized), `index_of`, `color_at`
- [x] Memoize nearest-color lookups by packed RGBA key (32-bit integer, not String)
- [ ] Validate that Display and Framebuffer reference the same PixelFormat at `display.show()`
- [x] Specs for palette nearest-color accuracy across all 4 formats

Also implemented beyond spec: `Palette#==`/`#eql?`/`#hash` (value equality), `LruCache` for bounded nearest-color memoization, `PixelFormat::REGISTRY` with `.from_name` lookup, `PixelFormat#buffer_size` cross-validated against C, `PixelFormatBridge` prepended module bridging Ruby symbols to C integers.

**Files:** `lib/chroma_wave/pixel_format.rb`, `lib/chroma_wave/palette.rb`, `lib/chroma_wave/framebuffer.rb`
**Refs:** [EXTENSION_STRATEGY.md §3.1](EXTENSION_STRATEGY.md#31-the-pixelformat-unifying-concept), [API_REFERENCE.md §1](API_REFERENCE.md#1-core-value-types)
**Depends on:** —
**Acceptance:** ✅ `PixelFormat` replaces all occurrences of scale/color_type/bpp. Palette correctly maps RGBA to nearest palette entry for all formats. Display validation deferred to Phase 4 when Display class exists.

---

### 5. Color ✅

RGBA value type with named constants, hex parsing, and alpha compositing.

- [x] Implement `Color` as `Data.define(:r, :g, :b, :a)` with `a: 255` default
- [x] Define named constants (`Color::BLACK`, `Color::WHITE`, `Color::RED`, etc.)
- [x] Build `Color::NAME_MAP` (symbol → Color) for palette integration
- [x] Implement `#over(background)` — source-over compositing onto opaque background
- [x] Implement `#to_rgba_bytes` / `.from_rgba_bytes` for Canvas packed-buffer interop
- [x] Hex string parsing (`Color.hex("#FF0000")`, `Color.hex("#F00")`)
- [x] Specs for compositing math, named color lookup, hex parsing edge cases

Also implemented beyond spec: `#to_hex`, `#opaque?`/`#transparent?` predicates, `DARK_GRAY`/`LIGHT_GRAY`/`TRANSPARENT` additional constants.

**Files:** `lib/chroma_wave/color.rb`
**Refs:** [CONTENT_PIPELINE.md §1](CONTENT_PIPELINE.md#1-color-model-rgba), [API_REFERENCE.md §1](API_REFERENCE.md#1-core-value-types)
**Depends on:** —
**Acceptance:** ✅ Color is frozen/immutable. Compositing produces correct opaque results. Named colors match expected RGBA values.

---

## 🎨 Phase 3: Drawing Architecture ✅

The Surface protocol and its three implementations: Canvas, Framebuffer (Ruby wrapper), and Layer.

### 6. Define the Surface protocol ✅

A Ruby module that defines the duck-type drawing target. Includers provide `set_pixel`,
`get_pixel`, `width`, `height`; the module mixes in drawing primitives.

- [x] Define `Surface` module with required method contract (`set_pixel`, `get_pixel`, `width`, `height`)
- [x] Silent clipping on `set_pixel` out-of-bounds writes
- [x] Return `nil` on `get_pixel` out-of-bounds reads
- [x] Include hooks for drawing primitive mixins (Phase 3, Task 9)
- [x] Add `Surface` to Framebuffer's Ruby wrapper (`include Surface`)
- [x] Specs for clipping behavior and protocol enforcement

Also implemented beyond spec: `in_bounds?` predicate, default `clear` and `blit` implementations, `validate_dimensions!` with `MAX_DIMENSION` (4096) cap matching the C extension.

**Files:** `lib/chroma_wave/surface.rb`, `lib/chroma_wave/framebuffer.rb`
**Refs:** [EXTENSION_STRATEGY.md §3.7](EXTENSION_STRATEGY.md#37-three-layer-drawing-architecture), [API_REFERENCE.md §2](API_REFERENCE.md#2-surface-protocol--implementations)
**Depends on:** Task 1 (Framebuffer C backing)
**Acceptance:** ✅ Any object including `Surface` and providing the 4 required methods is a valid drawing target.

---

### 7. Implement Canvas ✅

RGBA pixel buffer stored as a packed binary String (4 bytes/pixel). Includes `Surface`.

- [x] Storage: single `String.new("\0" * w * h * 4, encoding: Encoding::BINARY)`
- [x] `set_pixel(x, y, color)` — decompose Color into 4 bytes at offset
- [x] `get_pixel(x, y)` — lazily materialize Color from 4 bytes (avoid allocation in bulk paths)
- [x] `clear(color)` — fill entire buffer (Ruby fallback; C accelerator in Task 8)
- [x] Expose `rgba_bytes` for direct byte access by Renderer
- [x] `include Surface` for drawing primitive support
- [x] Specs for pixel round-trip, bounds clipping, memory footprint (2 GC objects regardless of resolution)

Also implemented beyond spec: `#==`/`#eql?`/`#hash` (value equality), `#inspect`, `initialize_copy` (deep copy for `dup`/`clone`), `#layer` convenience method with block form, optimized `fill_rect` that writes scanline rows directly into the buffer (shadows the Primitives pixel-by-pixel version for Canvas instances).

**Files:** `lib/chroma_wave/canvas.rb`
**Refs:** [EXTENSION_STRATEGY.md §3.7 "Canvas"](EXTENSION_STRATEGY.md#37-three-layer-drawing-architecture), [API_REFERENCE.md §2](API_REFERENCE.md#2-surface-protocol--implementations)
**Depends on:** Tasks 5, 6
**Acceptance:** ✅ 800x480 Canvas uses ~1.5MB. `get_pixel`/`set_pixel` round-trips correctly. Only 2 GC objects (Canvas + String).

---

### 8. Canvas C accelerators ✅

~170 lines of C that accelerate three Canvas hot paths. All three have Ruby fallbacks.

- [x] `_canvas_clear(rgba_string, r, g, b, a)` — bulk memset of packed RGBA
- [x] `_canvas_blit_alpha(dst_string, src_string, dx, dy, sw, sh, dw, dh)` — alpha-composited blit
- [x] `_canvas_load_rgba(dst_string, src_bytes, x, y, w, h, dw)` — bulk load from external RGBA data
- [x] All operate on `RSTRING_PTR` of Canvas's String buffer (Canvas owns data, C processes it)
- [x] Graceful fallback: if C extension unavailable, Ruby methods work (just slower)
- [x] Specs comparing C-accelerated vs Ruby fallback output for correctness

All three C methods include `Check_Type`, bounds checking, and `EPD_MAX_DIMENSION` guards. Alpha compositing uses `(s*a + d*(255-a) + 127) / 255` for correct rounding. Canvas detects C methods via `respond_to?(:_canvas_clear, true)`.

**Files:** `ext/chroma_wave/canvas.c`
**Refs:** [EXTENSION_STRATEGY.md §2.2](EXTENSION_STRATEGY.md#22-responsibility-matrix)
**Depends on:** Task 7 (Canvas Ruby implementation)
**Acceptance:** ✅ C accelerators produce byte-identical output to Ruby fallbacks. Canvas detects and prefers C when available.

---

### 9. Drawing primitives ✅

Bresenham/midpoint algorithms as `Surface` mixin methods. All work on any Surface (Canvas,
Framebuffer, Layer).

- [x] `draw_line(x0, y0, x1, y1, pen:)`
- [x] `draw_polyline(points, pen:, closed:)`
- [x] `draw_rect(x, y, w, h, pen:)`
- [x] `draw_rounded_rect(x, y, w, h, radius:, pen:)`
- [x] `draw_circle(cx, cy, r, pen:)`
- [x] `draw_ellipse(cx, cy, rx, ry, pen:)`
- [x] `draw_arc(cx, cy, r, start_angle, end_angle, pen:)`
- [x] `draw_polygon(points, pen:)`
- [x] `flood_fill(x, y, color:)`
- [x] Specs for each primitive on a test Canvas, including edge cases (zero-size, single pixel, clipping)

The original `color:`/`stroke_width:`/`fill:` keyword arguments were replaced with a single `pen:` keyword accepting a `Pen` value object. `Pen` is built on `Data.define(:stroke, :fill, :stroke_width)` for structural equality, immutability, and pattern matching. Factory methods: `Pen.stroke(color, width:)`, `Pen.fill(color)`.

Also implemented beyond spec: thick line via perpendicular offset, annulus optimization for thick circle/ellipse strokes, scanline flood fill with O(height) stack, `draw_rounded_rect` with corner arcs.

**Files:** `lib/chroma_wave/drawing/primitives.rb`, `lib/chroma_wave/pen.rb`
**Refs:** [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md), [API_REFERENCE.md §2](API_REFERENCE.md#2-surface-protocol--implementations)
**Depends on:** Task 6 (Surface protocol)
**Acceptance:** ✅ All primitives render correctly. Stroke and fill work via `Pen`. Clipping is silent. Verified on Canvas, Layer, and Framebuffer.

---

### 10. Layer ✅

Clipped, offset sub-region of a parent Surface. Foundation for widget-based UI composition.

- [x] `Layer.new(parent:, x:, y:, width:, height:)` — wraps any Surface
- [x] `set_pixel` translates local coords → parent coords, delegates to parent
- [x] `get_pixel` translates and delegates; returns `nil` for out-of-bounds
- [x] Layers compose: Layer of a Layer works correctly (additive offset)
- [x] No bounds validation against parent (intentional — see [§3.7](EXTENSION_STRATEGY.md#37-three-layer-drawing-architecture))
- [x] `include Surface` for drawing primitive support
- [x] Specs for nested layers, coordinate translation, out-of-bounds behavior

Also implemented beyond spec: `#inspect`, dimension validation via `Surface#validate_dimensions!`, tested with both Canvas and Framebuffer parents.

**Files:** `lib/chroma_wave/layer.rb`
**Refs:** [EXTENSION_STRATEGY.md §3.7 "Layer"](EXTENSION_STRATEGY.md#37-three-layer-drawing-architecture), [API_REFERENCE.md §2](API_REFERENCE.md#2-surface-protocol--implementations)
**Depends on:** Task 6 (Surface protocol)
**Acceptance:** ✅ Nested layers translate coordinates correctly. Drawing on a Layer clips to its bounds while delegating to the parent's pixel storage.

---

## ⚡ Phase 4: Rendering & Display

The bridge from drawing to hardware: quantization, display dispatch, and refresh lifecycle.

### 11. Renderer (Canvas → Framebuffer)

Converts RGBA Canvas pixels to palette entries in a device-format Framebuffer. The only place
quantization and dithering occur.

- [ ] `Renderer.new(pixel_format:)` or `Renderer.render(canvas, framebuffer:, dither:)`
- [ ] Palette mapping: RGBA → nearest palette entry (delegates to `Palette#nearest_color`)
- [ ] Dithering strategies: Floyd-Steinberg (default), ordered, threshold
- [ ] Dual-buffer channel splitting: one Canvas → two MONO Framebuffers (for `DualBuffer` displays)
- [ ] Linear scan over `canvas.rgba_bytes` (no per-pixel Color materialization)
- [ ] Specs for quantization accuracy, dithering output, dual-buffer split correctness

**Files:** `lib/chroma_wave/renderer.rb`
**Refs:** [EXTENSION_STRATEGY.md §3.7 "Renderer"](EXTENSION_STRATEGY.md#37-three-layer-drawing-architecture), [API_REFERENCE.md §4](API_REFERENCE.md#4-renderer)
**Depends on:** Tasks 1, 4, 7
**Acceptance:** Renderer produces correct Framebuffer output for all 4 pixel formats. Dithering is visually reasonable. Dual-buffer split routes colors correctly to black/red layers.

---

### 12. Display capability modules

Composable Ruby modules that wrap private C methods for optional display features.

- [ ] `Capabilities::PartialRefresh` — `display_partial`, `display_base`
- [ ] `Capabilities::FastRefresh` — `init_fast`, `display_fast`
- [ ] `Capabilities::GrayscaleMode` — `init_grayscale`, `display_grayscale`
- [ ] `Capabilities::DualBuffer` — overrides `show` to split Canvas into 2 mono FBs via Renderer
- [ ] `Capabilities::RegionalRefresh` — `display_region(fb, x, y, w, h)`
- [ ] Base `Display#show` accepts Canvas (auto-rendered) or Framebuffer (power-user)
- [ ] Model registry: auto-build subclasses from C config capability bitfields at gem load time
- [ ] `Display.new(model: :symbol)` factory with did-you-mean on typos
- [ ] `respond_to?(:display_partial)` and `is_a?(Capabilities::PartialRefresh)` work naturally
- [ ] Specs for capability inclusion, method dispatch, format validation

**Files:** `lib/chroma_wave/capabilities/partial_refresh.rb`, `fast_refresh.rb`, `grayscale_mode.rb`, `dual_buffer.rb`, `regional_refresh.rb`, `lib/chroma_wave/display.rb`, `lib/chroma_wave/registry.rb`
**Refs:** [EXTENSION_STRATEGY.md §3.3-3.4](EXTENSION_STRATEGY.md#33-model-instantiation-and-the-registry), [API_REFERENCE.md §3](API_REFERENCE.md#3-display--capabilities)
**Depends on:** Tasks 3, 11
**Acceptance:** `Display.new(model: :epd_2in13_v4).respond_to?(:display_partial)` returns true. Typos raise `ModelNotFoundError` with suggestions.

---

### 13. Compile all drivers unconditionally

All ~70 driver files are compiled into the extension. Runtime model selection via the registry.

- [ ] Add all `EPD_*.c` files to `extconf.rb` source list
- [ ] Verify total binary size is acceptable (~500KB)
- [ ] Ensure no compile-time `#ifdef` guards exclude any driver

**Files:** `ext/chroma_wave/extconf.rb`, `ext/chroma_wave/vendor/drivers/`
**Refs:** [EXTENSION_STRATEGY.md §1.2](EXTENSION_STRATEGY.md#12-what-we-must-abstract)
**Depends on:** Tasks 2, 3
**Acceptance:** All 70 models are accessible at runtime. Binary size is reasonable.

---

### 14. Release the GVL during refresh

Wrap display refresh operations with `rb_thread_call_without_gvl()` so other Ruby threads can
run during multi-second refresh cycles.

- [ ] Identify all C functions that block on `ReadBusy` or SPI transfer
- [ ] Wrap with `rb_thread_call_without_gvl(refresh_func, arg, ubf, ubf_arg)`
- [ ] Implement unblocking function (`ubf`) for clean interrupt of long refreshes
- [ ] Verify Mutex composes correctly: acquired before entering C, GVL released inside C, Mutex released after C returns

**Files:** `ext/chroma_wave/display.c`
**Refs:** [EXTENSION_STRATEGY.md §5.3](EXTENSION_STRATEGY.md#53-busy-wait-blocking-and-gvl-release), [EXTENSION_STRATEGY.md §5.7](EXTENSION_STRATEGY.md#57-thread-safety)
**Depends on:** Task 2
**Acceptance:** Other Ruby threads continue running during display refresh. `Thread.new { display.refresh }.kill` interrupts cleanly.

---

### 15. Busy-wait timeout ⚠️ C-level done

Add configurable timeout to `ReadBusy` with an interruptible polling loop.

- [x] Replace spin-wait with 1ms polling interval loop
- [x] Add configurable `timeout_ms` parameter to `epd_read_busy()` — returns `EPD_ERR_TIMEOUT`
- [ ] Raise `ChromaWave::TimeoutError` on expiry (Ruby integration — needs Display layer)
- [ ] Integrate with the ubf from Task 14 for clean interrupt

The C-level `epd_read_busy(polarity, timeout_ms)` function is implemented with a 1ms polling loop and returns `EPD_ERR_TIMEOUT` on expiry. Ruby-level error raising and interrupt integration deferred to Phase 4 when the Display class is built.

**Files:** `ext/chroma_wave/device.c`
**Refs:** [EXTENSION_STRATEGY.md §5.3](EXTENSION_STRATEGY.md#53-busy-wait-blocking-and-gvl-release)
**Depends on:** Task 2
**Acceptance:** ⚠️ C-level busy-wait respects timeout. Ruby error raising and interrupt integration deferred.

---

## 📐 Phase 5: Content Pipeline

Text, icons, and images — the high-level content types that draw onto Surfaces.

### 16. FreeType bindings

C extension bindings for FreeType glyph rasterization. Ruby-side `Font` class handles layout.

- [ ] Link `libfreetype` in `extconf.rb` (optional — compile without if not found, set `-DNO_FREETYPE`)
- [ ] `freetype.c`: manage `FT_Library` lifecycle (singleton, initialized on first use)
- [ ] Wrap `FT_Face` in a `TypedData` struct with proper `dfree`
- [ ] Expose private C methods: `_ft_load_face`, `_ft_render_glyph`, `_ft_glyph_metrics`
- [ ] Ruby `Font` class: font discovery, size setting, measurement (`text_width`, `text_height`)
- [ ] Ruby `Surface#draw_text`: layout engine (alignment, word wrapping), calls `Font` for glyphs
- [ ] When `NO_FREETYPE`: `Font.new` / `draw_text` raise `ChromaWave::DependencyError` with install hint
- [ ] Specs for glyph rendering, metrics accuracy, missing-freetype fallback error

**Files:** `ext/chroma_wave/freetype.c`, `ext/chroma_wave/freetype.h`, `lib/chroma_wave/font.rb`, `lib/chroma_wave/drawing/text.rb`
**Refs:** [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md), [EXTENSION_STRATEGY.md §5.1](EXTENSION_STRATEGY.md#51-platform-detection-in-extconfrb)
**Depends on:** Task 6 (Surface protocol)
**Acceptance:** Text renders correctly with system TTF fonts. Missing FreeType gives a helpful error.

---

### 17. IconFont + Lucide

`IconFont` subclass of `Font` with symbol → codepoint registry. Bundles Lucide icons.

- [ ] `IconFont` extends `Font` with symbol-based glyph lookup (`icon_font.glyph(:arrow_right)`)
- [ ] Bundle `lucide.ttf` (~120KB, ISC license) in `data/fonts/`
- [ ] Include `LICENSE-lucide.txt`
- [ ] `rake icons:generate` task: parse Lucide metadata → `lib/chroma_wave/icon_font/lucide_glyphs.rb`
- [ ] Generated glyph map: `{ arrow_right: 0xE001, ... }`
- [ ] Specs for icon rendering, symbol lookup, missing-icon error

**Files:** `lib/chroma_wave/icon_font.rb`, `lib/chroma_wave/icon_font/lucide_glyphs.rb`, `data/fonts/lucide.ttf`, `data/fonts/LICENSE-lucide.txt`
**Refs:** [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md)
**Depends on:** Task 16 (Font / FreeType)
**Acceptance:** `icon_font.glyph(:home)` renders the Lucide home icon. Rake task regenerates the glyph map from upstream metadata.

---

### 18. Image loading (ruby-vips)

Load any image format, resize/crop, and bulk-transfer RGBA data into Canvas.

- [ ] `Image.load(path)` — load via ruby-vips, convert to RGBA
- [ ] `Image#resize(width:, height:, fit:)` — resize with various fit modes
- [ ] `Image#crop(x:, y:, width:, height:)`
- [ ] `Image#draw_onto(canvas, x:, y:)` — bulk RGBA transfer via `Canvas#load_rgba_bytes` / C accelerator
- [ ] vips packed RGBA output maps directly to Canvas's packed String buffer
- [ ] Specs for load, resize, crop, and draw_onto correctness

**Files:** `lib/chroma_wave/image.rb`
**Refs:** [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md)
**Depends on:** Tasks 7, 8 (Canvas + C accelerators)
**Acceptance:** JPEG/PNG/WebP images load, resize, and blit onto Canvas correctly. Bulk transfer uses C accelerator when available.

---

## 🔧 Phase 6: Build & Platform

Compilation, platform detection, and development support.

### 19. Platform detection in `extconf.rb` ⚠️ Stub only

Auto-detect GPIO/SPI backend and configure compiler flags.

- [ ] Check for headers: `lgpio.h`, `bcm2835.h`, `wiringPi.h`, `gpiod.h`
- [ ] Check for corresponding `-l` libraries
- [ ] Auto-select best available backend (prefer `USE_LGPIO_LIB` for RPi 5)
- [ ] Allow `--with-epd-backend=` configure option for manual override
- [ ] Detect and optionally link `libfreetype` (see Task 16)
- [x] If no GPIO/SPI library found: auto-select MOCK backend ~~with warning~~
- [x] Set appropriate `-D` compiler flags (`-DEPD_MOCK_BACKEND` unconditionally for now)

Current state: `extconf.rb` unconditionally sets `-DEPD_MOCK_BACKEND` and compiler warning flags. No header probing, library detection, or `--with-epd-backend=` option yet. Full platform detection deferred until hardware integration begins.

**Files:** `ext/chroma_wave/extconf.rb`
**Refs:** [EXTENSION_STRATEGY.md §1.2](EXTENSION_STRATEGY.md#12-what-we-must-abstract), [EXTENSION_STRATEGY.md §5.1](EXTENSION_STRATEGY.md#51-platform-detection-in-extconfrb)
**Depends on:** —
**Acceptance:** ⚠️ Gem compiles on dev machines with MOCK. Full platform detection deferred.

---

### 20. Mock backend (C-level) ✅

C-level no-op stubs so the extension compiles on any platform without GPIO/SPI hardware.

- [x] Define `MOCK` backend that stubs all GPIO/SPI calls
- [x] `Framebuffer` and all pixel operations work normally (pure memory)
- [ ] `Display#show`, `Display#clear`, `Device.new` raise `ChromaWave::DeviceError` with clear message (needs Display/Device Ruby classes)
- [x] CI runs full test suite with MOCK backend
- [ ] Specs verify that mock mode raises on hardware ops but allows drawing ops (needs Display/Device Ruby classes)

`mock_hal.c` / `mock_hal.h` provide full no-op GPIO/SPI stubs compiled under `#ifdef EPD_MOCK_BACKEND`. All C-level operations (framebuffer, driver registry, device I/O) work in pure-memory mode. The `DeviceError` raising is deferred until the Ruby Display/Device classes exist.

**Files:** `ext/chroma_wave/mock_hal.c`, `ext/chroma_wave/mock_hal.h`, `ext/chroma_wave/extconf.rb`
**Refs:** [EXTENSION_STRATEGY.md §5.1](EXTENSION_STRATEGY.md#51-platform-detection-in-extconfrb)
**Depends on:** Task 19
**Acceptance:** ✅ Full test suite passes on x86_64 Linux with no GPIO hardware. C extension compiles and runs with mock stubs.

---

### 21. MockDevice (Ruby-level)

Ruby `Display` subclass that replaces C hardware calls with no-op stubs, records every
operation as an inspectable log, and supports palette-accurate PNG export. This is the
primary interface for test suites and development scripts.

- [ ] `MockDevice` subclass of `Display` — loads same model config, includes same capability modules
- [ ] Constructor: `MockDevice.new(model:, busy_duration: 0)` — `model:` required, `busy_duration:` controls simulated refresh delay
- [ ] Override private C hardware methods (`_epd_display`, `_epd_clear`, etc.) with Ruby stubs
- [ ] Operation log: append `{ op:, timestamp:, **metadata }` for each hardware operation (`:init`, `:show`, `:clear`, `:sleep`, `:close`)
- [ ] Thread-safe operation log protected by Mutex
- [ ] Convenience queries: `operations(type = nil)`, `last_operation`, `operation_count(type)`, `clear_operations!`
- [ ] `last_framebuffer` — stores the most recently rendered Framebuffer for inspection
- [ ] `save_png(path)` — palette-accurate PNG export of `last_framebuffer` via ruby-vips (native resolution, no scaling)
- [ ] Busy-wait simulation: when `busy_duration > 0`, `show` blocks for the configured duration (exercises timeout/interrupt paths)
- [ ] `BusyTimeoutError` raised when display timeout < `busy_duration`
- [ ] All capability methods work: `display_partial`, `init_fast`, `init_grayscale`, `display_region`, `DualBuffer#show`
- [ ] RSpec helper: `:hardware` metadata tag with `mock_device` injection (see [MOCKING.md §4.1](MOCKING.md#41-rspec-helper))
- [ ] Specs for operation logging, PNG export accuracy, busy-wait timeout, capability dispatch, thread safety

**Files:** `lib/chroma_wave/mock_device.rb`, `spec/support/mock_device.rb`
**Refs:** [MOCKING.md §2.2–§4](MOCKING.md#22-ruby-level-mockdevice)
**Depends on:** Tasks 11, 12, 20 (Renderer, Display capabilities, C mock backend)
**Acceptance:** `MockDevice.new(model: :epd_2in13_v4).is_a?(Display)` is true. Operation log captures all hardware calls. `save_png` produces a palette-accurate image matching what the physical display would show. Full test suite uses MockDevice for all hardware integration tests.

---

### 22. CI/CD pipeline ✅

GitHub Actions workflow with 5 jobs providing comprehensive quality gates.

- [x] `compile` — compiles the C extension
- [x] `rspec` — runs specs, uploads coverage artifact
- [x] `rubocop` — linting enforcement
- [x] `coverage` — enforces 90% line / 80% branch coverage thresholds
- [x] `docs` — generates RDoc, deploys to GitHub Pages (main branch only)

**Files:** `.github/workflows/main.yml`
**Depends on:** —
**Acceptance:** ✅ All 5 jobs pass on every push. Coverage gates enforce minimum thresholds.

---

### 23. Code coverage ✅

SimpleCov integration with enforced thresholds.

- [x] SimpleCov configured in `spec_helper.rb`
- [x] 90% line coverage minimum, 80% branch coverage minimum
- [x] Coverage artifact uploaded by CI for inspection

**Files:** `spec/spec_helper.rb`
**Depends on:** Task 22
**Acceptance:** ✅ Coverage reports generated on every test run. CI enforces thresholds.
