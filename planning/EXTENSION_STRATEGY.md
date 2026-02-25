# ChromaWave C Extension Strategy

Design decisions and architecture for the Ruby C extension that wraps the Waveshare vendor
library. For documentation of the vendor library itself, see [WAVESHARE_LIBRARY.md](WAVESHARE_LIBRARY.md).

**Companion documents:**
- [API_REFERENCE.md](API_REFERENCE.md) — Full code contracts for all classes and C structs
- [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md) — Color, drawing, text, icons, and image loading
- [ROADMAP.md](ROADMAP.md) — Phased task breakdown with subtasks and acceptance criteria
- [MOCKING.md](MOCKING.md) — Mock hardware strategy for development and testing

---

## 1. Vendor Component Assessment

What we use from the vendor library and how:

| Component      | Usable? | Notes                                                    |
|----------------|---------|----------------------------------------------------------|
| DEV_Config HAL | Yes     | Thin, well-defined interface. Include as-is.             |
| EPD_*.c drivers| Partial | Init register sequences and LUT tables are essential.    |
|                |         | Boilerplate (Reset, SendCommand, SendData, ReadBusy)     |
|                |         | is duplicated across all 70 files and should be factored |
|                |         | into shared helpers owned by the Device layer.           |
| GUI_Paint      | Minimal | Only the pixel-packing logic in `Paint_SetPixel` and     |
|                |         | `Paint_Clear` (~100 lines). Drawing primitives (line,    |
|                |         | rect, circle, text) are pure algorithms that belong in   |
|                |         | Ruby. See Section 2.1 for rationale.                     |
| GUI_BMPfile    | No      | File I/O should be handled in Ruby, not C.               |
| Fonts          | No      | Hard-coded bitmaps. Replace with FreeType or similar.    |
| Debug.h        | Yes     | Redirect to Ruby `rb_warn()` instead of `printf`.        |

### 1.1 What We Must Replace

- **Global PAINT state** -- the `PAINT Paint` global conflates pixel storage, coordinate
  transforms, and drawing context. Replace with a C-backed `Framebuffer` struct (owns buffer
  + pixel format metadata) wrapped via `TypedData_Wrap_Struct`. Coordinate transforms and
  drawing move to Ruby entirely (see Section 2).
- **printf-based debug** -- redirect `Debug()` macro to `rb_warn()` or a configurable logger.
- **DEV_Module_Init / Exit** -- wrap in a Ruby `ChromaWave::Device` lifecycle object with
  proper `dfree` cleanup. Supports both block-style (`Display.open { |d| ... }`) and
  explicit `close` for long-lived instances.
- **malloc for image buffers** -- allocate via `xmalloc` / `xfree` (Ruby's tracked allocator)
  so Ruby's GC tracks the memory pressure.
- **Duplicated I/O primitives** -- `Reset()`, `SendCommand()`, `SendData()`, `ReadBusy()`
  are copy-pasted identically across all 70 driver files (~1,400 lines of duplication). These
  belong on the Device layer as shared functions, parameterized by busy polarity and reset
  timing.

### 1.2 What We Must Abstract

- **Model selection** -- the vendor library is compile-time-selected. We compile all drivers
  and select at runtime via a two-tier registry (config data + optional code overrides).
  Total code size of all 70 drivers is modest (~500KB compiled). See Section 3.5.
- **Platform selection** -- similarly compile-time. For the gem, we should:
  - Default to `USE_LGPIO_LIB` for RPi 5 / modern Raspberry Pi OS
  - Allow `USE_DEV_LIB` as fallback (gpiod, most portable)
  - Detect platform in `extconf.rb` and set appropriate `-D` flags
  - Define a `MOCK` backend for development/testing on non-RPi systems

### 1.3 What We Should NOT Use

- **GUI_Paint.c drawing primitives** -- `Paint_DrawLine`, `Paint_DrawRectangle`,
  `Paint_DrawCircle`, `Paint_DrawChar`, `Paint_DrawString_*`, `Paint_DrawNum`, etc. These are
  pure Bresenham/rasterization algorithms (~750 lines) that are better implemented in Ruby for
  extensibility, testability, and ecosystem integration. Only the pixel-packing core
  (`Paint_SetPixel` + `Paint_Clear`, ~100 lines) is extracted into `framebuffer.c`.
- **GUI_BMPfile.c** -- BMP loading should happen in Ruby (ChunkyPNG, MiniMagick, or Vips).
  The C BMP loader is limited to 24-bit uncompressed BMP only.
- **Font bitmap tables** -- The built-in fonts are tiny (5x8 to 17x24) fixed-width bitmaps
  with only ASCII + limited GB2312. Replace with FreeType or Ruby-side text rendering.
- **Driver boilerplate** -- The `Reset()`, `SendCommand()`, `SendData()`, `ReadBusy()` static
  functions duplicated across all 70 driver files. These are factored into shared Device-level
  functions parameterized by model config.
- **examples/** -- Test programs are useful as reference but should not be compiled into the gem.
- **Makefile** -- We'll use `extconf.rb` + `mkmf` instead.

---

## 2. Responsibility Split: Ruby vs C

A critical design decision is where to draw the line between C and Ruby. The guiding principle:
**C handles hardware I/O and bit-level buffer manipulation. Ruby handles everything else.**

### 2.1 Why Drawing Belongs in Ruby

The vendor's `GUI_Paint.c` has two distinct responsibilities:

1. **Pixel packing** (`Paint_SetPixel`, `Paint_Clear`) -- Scale-dependent bit-twiddling that
   packs color values into byte buffers using format-specific layouts (1-bit MSB bitmask,
   2-bit pairs, 4-bit nibbles). This is ~100 lines of C and genuinely benefits from being in C.

2. **Drawing algorithms** (`Paint_DrawLine`, `Paint_DrawRectangle`, `Paint_DrawCircle`,
   `Paint_DrawChar`, etc.) -- Pure Bresenham/rasterization algorithms that call `SetPixel` in
   loops. These are ~750 lines of C that:
   - Have no hardware interaction
   - Are limited (no anti-aliasing, no alpha, no clipping, no real font support)
   - Duplicate what Ruby drawing libraries already do better
   - Are trivial to implement in Ruby (Bresenham is ~20 lines)

For e-paper displays, refresh takes 2-15 seconds. Drawing overhead is irrelevant. Even the
worst case (filling every pixel on an 800x480 display = ~384K Ruby->C FFI calls for `set_pixel`)
completes well under a second.

**By keeping drawing in Ruby, we gain:**
- Extensibility (anti-aliasing, compositing, alpha) without touching C
- Testability (no hardware needed to test drawing logic)
- Ecosystem integration (ChunkyPNG, Vips, FreeType interop at the Ruby level)
- No need to fork/maintain a modified GUI_Paint.c

### 2.2 Responsibility Matrix

| Concern                    | Layer | Rationale                                     |
|----------------------------|-------|-----------------------------------------------|
| GPIO/SPI lifecycle         | C     | Hardware handles, platform-specific           |
| SPI command/data protocol  | C     | Bit-level timing, CS/DC pin toggling          |
| Display init/sleep/refresh | C     | Register sequences, busy-wait, GVL release    |
| Pixel packing into buffer  | C     | Bit-twiddling (MSB bitmask, nibble packing)   |
| Buffer allocation/free     | C     | `xmalloc`/`xfree` with `TypedData` lifecycle  |
| Bulk buffer clear/fill     | C     | Format-aware memset, faster than per-pixel    |
| Canvas bulk ops            | C*    | clear, blit_alpha, load_rgba (~80 lines)      |
| Coordinate transforms      | Ruby  | Rotation/mirror matrix math, no hardware      |
| Surface protocol           | Ruby  | Abstract drawing target (duck-type interface)  |
| Canvas (RGBA buffer)       | Ruby  | Packed String storage, Ruby API, C hot paths  |
| Layer composition          | Ruby  | Clip regions, offset blitting, widget bounds  |
| Drawing primitives         | Ruby  | Bresenham algorithms, calls `Surface#set_pixel`|
| Rendering / quantization   | Ruby  | RGBA→palette mapping, dithering, dual-buf split|
| Text rendering             | Ruby  | FreeType or pre-rendered, not bitmap fonts    |
| Image loading/conversion   | Ruby  | ruby-vips, bulk load into Canvas via load_rgba|
| Display capability queries | Ruby  | `respond_to?` / module inclusion checks       |
| Model configuration        | Ruby  | Resolution, format, capabilities per model    |

> **C\*:** Canvas C accelerators are optional. All three methods have Ruby fallbacks.
> The C code operates on Canvas's Ruby String buffer (`RSTRING_PTR`), not its own
> allocation — Canvas owns its data, C just processes it faster.

---

## 3. Architecture

### 3.1 The `PixelFormat` Unifying Concept

The vendor library's `Scale` value, the color constants, and the buffer size math all express
the same underlying concept: **how pixels are packed into bytes**. This concept appears in at
least four places in a naive design (Image buffer, Display config, Color validation, driver
registry). It should be modeled once.

`PixelFormat` is a `Data.define(:name, :bits_per_pixel, :palette)` value object. `Palette` is
an `Enumerable` color lookup table with nearest-color matching (memoized by packed RGBA key).
Four format constants cover all vendor displays: `MONO`, `GRAY4`, `COLOR4`, `COLOR7`.

Both `Display` and `Framebuffer` reference a `PixelFormat`. The Display declares what format it
requires. The Framebuffer declares what format it contains. Compatibility is checked once at
the point of use (`display.show(framebuffer)`), not scattered across layers.

**Dual-buffer displays** (black + red/yellow) are modeled as two Framebuffers, both `MONO`
format, not as a special pixel format. The `Renderer` handles splitting a Canvas into the two
mono Framebuffers via color-channel mapping. The `DualBuffer` capability module is purely a
hardware concern — it knows how to send two buffers over SPI.

> See [API_REFERENCE.md, Section 1](API_REFERENCE.md#1-core-value-types) for the full
> Palette and PixelFormat implementations.

### 3.2 Directory Structure

```
ext/chroma_wave/                    # C -- only what MUST be C
  chroma_wave.c                       # Init_chroma_wave: define module, classes, constants
  chroma_wave.h                       # Shared type definitions, Ruby VALUE externs
  device.c                            # Device: SPI/GPIO lifecycle + shared I/O primitives
  |                                   #   epd_send_command(), epd_send_data(), epd_reset(),
  |                                   #   epd_read_busy() -- factored OUT of individual drivers
  framebuffer.c                       # Framebuffer: pixel packing (set_pixel, get_pixel,
  |                                   #   clear, raw buffer access). ~100 lines extracted
  |                                   #   from GUI_Paint.c. Parameterized, no global state.
  canvas.c                            # Canvas C accelerators: _canvas_clear, _canvas_blit_alpha,
  |                                   #   _canvas_load_rgba. ~80 lines. Operates on Canvas's
  |                                   #   packed String buffer via RSTRING_PTR. Optional —
  |                                   #   Ruby fallbacks exist for all three methods.
  display.c                           # Display: init/clear/refresh/sleep dispatch.
  |                                   #   Calls device I/O + driver-specific logic.
  driver_registry.c                   # Two-tier registry: config data + optional overrides.
  |                                   #   Generic init/display functions interpret config tables.
  |                                   #   Complex models provide override function pointers.
  freetype.c                          # FreeType bindings: load_face, render_glyph, metrics
  freetype.h                          # FT_Library lifecycle, FT_Face struct wrapper
  extconf.rb                          # Platform detection, backend selection, compiler flags
  |
  vendor/                             # Vendored C sources (restructured from vendor/waveshare_epd)
    config/                           #   DEV_Config.c, platform backends (as-is)
    drivers/                          #   All EPD_*.c files -- compiled unconditionally.
    |                                 #   Boilerplate (Reset/SendCommand/SendData/ReadBusy)
    |                                 #   is stripped; these files provide only Init register
    |                                 #   sequences, LUT tables, and model-specific Display
    |                                 #   logic for complex models.
    |                                 #   Root vendor/waveshare_epd/ kept as upstream reference.

lib/chroma_wave/                    # Ruby -- everything that doesn't need to be C
  chroma_wave.rb                      # Top-level require, autoloads
  version.rb                          # VERSION constant
  errors.rb                           # Exception hierarchy (Error, DeviceError, etc.)
  palette.rb                          # Palette value object (color lookup, nearest-match, indexing)
  pixel_format.rb                     # PixelFormat value object (MONO, GRAY4, COLOR7, etc.)
  color.rb                            # Color (RGBA Data.define, named constants, compositing)
  surface.rb                          # Surface protocol module (duck-type drawing target)
  framebuffer.rb                      # Ruby wrapper for C-backed Framebuffer (includes Surface)
  canvas.rb                           # RGB pixel buffer, compositing, drawing (includes Surface)
  layer.rb                            # Clipped, offset sub-region of a parent Surface
  renderer.rb                         # Canvas→Framebuffer: quantization, dithering, channel split
  drawing/                            # Drawing primitives (mixed into Surface)
    primitives.rb                     #   line, polyline, rect, rounded_rect, circle,
    |                                 #   ellipse, arc, polygon, flood_fill
    text.rb                           #   draw_text, word_wrap, render_glyph
  font.rb                            # Font loading, measurement, glyph iteration (wraps C)
  icon_font.rb                       # IconFont (Font subclass, symbol→codepoint registry)
  icon_font/
    lucide_glyphs.rb                  #   Generated glyph map (rake icons:generate)
  image.rb                           # Image loading via ruby-vips (load, resize, crop, blit)
  transform.rb                        # Rotation, mirroring, coordinate mapping
  device.rb                           # Hardware lifecycle, connection management, Mutex
  display.rb                          # Display factory (symbol registry), base methods
  registry.rb                         # Model registry: builds subclasses from C config data
  capabilities/                       # Composable capability modules (wrap private C methods)
    partial_refresh.rb                #   display_partial, display_base
    fast_refresh.rb                   #   init_fast, display_fast
    grayscale_mode.rb                 #   init_grayscale, display_grayscale
    dual_buffer.rb                    #   show(black_fb, red_fb) -- hardware SPI concern only
    regional_refresh.rb               #   display_region(fb, x, y, w, h)

data/
  fonts/
    lucide.ttf                        # Bundled icon font (~120KB, ISC license)
    LICENSE-lucide.txt                # Lucide license text
```

### 3.3 Model Instantiation and the Registry

Users instantiate displays via a **symbol registry**. `Display.new` is a factory that returns
an instance of a dynamically-constructed subclass with the correct capability modules:

```ruby
display = ChromaWave::Display.new(model: :epd_2in13_v4)
display.respond_to?(:display_partial)          # => true
display.is_a?(Capabilities::PartialRefresh)    # => true

ChromaWave::Display.models  # => [:epd_2in13_v4, :epd_7in5_v2, ...]
```

At gem load time, the registry iterates C-side model configs and builds one Ruby subclass per
model, including the appropriate capability modules based on the config's capability bitfield.
Typos raise `ModelNotFoundError` immediately with did-you-mean suggestions.

> See [API_REFERENCE.md, Section 3.4](API_REFERENCE.md#34-model-registry) for the registry
> implementation.

### 3.4 Capabilities as Composable Modules

The vendor drivers expose capabilities as inconsistently-named optional functions
(`Init_Fast`, `Display_Partial`, `Display_Part`, `Display_part`). Rather than modeling these
as nullable function pointers in a flat C struct, use Ruby modules that wrap private C methods.

Five capability modules: `PartialRefresh`, `FastRefresh`, `GrayscaleMode`, `DualBuffer`,
`RegionalRefresh`. Each provides a public Ruby API with format validation, delegating to
private C methods (`_epd_display_partial`, `_epd_init_fast`, etc.) defined on the Display
base class in `Init_chroma_wave`.

The base `Display#show` accepts either a Canvas (common path, auto-rendered) or a pre-rendered
Framebuffer (power-user path). `DualBuffer` overrides `show` to split the Canvas into two
mono Framebuffers via the Renderer.

**Advantages over nullable function pointers:**
- Shared behavior is defined once per capability, reused across all models that support it
- `display.respond_to?(:display_partial)` works naturally for capability checking
- `display.is_a?(Capabilities::FastRefresh)` for type-based dispatch
- New capabilities are added without changing existing code (Open/Closed Principle)
- Documentation and tests live with each capability module
- C bridge is explicit: Ruby modules wrap private C methods with validation

> See [API_REFERENCE.md, Section 3](API_REFERENCE.md#3-display--capabilities) for the full
> Display, C bridge, and capability module implementations.

### 3.5 Two-Tier Driver Registry

Analysis of all 70 driver files reveals that **60-70% of driver code is identical boilerplate**
(see [WAVESHARE_LIBRARY.md, Section 9](WAVESHARE_LIBRARY.md#9-driver-variation-analysis)):
`Reset()`, `SendCommand()`, `SendData()`, `ReadBusy()` are copy-pasted with only busy polarity
and reset timing varying. What actually differs per model:

| Variation               | Type     | Can Be Config Data? |
|-------------------------|----------|---------------------|
| Resolution (w, h)       | Data     | Yes                 |
| Reset timings (ms)      | Data     | Yes -- `{20, 2, 20}` vs `{200, 2, 200}` |
| Busy-wait polarity      | Data     | Yes -- `ACTIVE_HIGH` vs `ACTIVE_LOW` |
| Init register sequence  | Data     | Yes -- encoded as `{cmd, len, data...}` pairs |
| Display write command   | Data     | Yes -- `0x24` vs `0x10` |
| Pixel format            | Data     | Yes -- maps to `PixelFormat` enum |
| LUT waveform tables     | **Code** | No -- Tier 2 overrides own their LUT data (see below) |
| Capability flags        | Data     | Yes -- bitmask |
| LUT selection logic     | **Code** | No -- runtime mode selection (EPD_4in2, EPD_3in7) |
| 4-gray pixel repacking  | **Code** | No -- controller-specific bit manipulation |
| 7-color power workflow   | **Code** | No -- EPD_5in65f requires power on/off per refresh |
| In-place buffer invert  | **Code** | No -- EPD_7in5_V2 inverts buffer before sending |

This motivates a **two-tier registry** in C:

- **Tier 1 (`epd_model_config_t`):** Static configuration struct — resolution, pixel format,
  busy polarity, reset timing, init register sequence, display command, capability flags.
  Handles 60-70% of drivers completely with zero custom C code.
- **Tier 2 (`epd_driver_t`):** Optional code overrides — `custom_init`, `custom_display`,
  `pre_display`, `post_display` function pointers. Only ~20 models need these.

A single `epd_generic_init()` function interprets `init_sequence` byte arrays. Simple
monochrome displays need **zero custom C code** — just a config struct entry. Complex models
provide override function pointers that call `epd_generic_init()` for the shared part and add
their own logic (LUT selection, power cycling, buffer inversion, etc.).

**LUT tables are Tier 2 concerns.** Override functions own their LUT data as `static const`
byte arrays, keeping the Tier 1 config struct simple.

**Impact:** Adding support for a new simple display model is adding ~10 lines of config data
rather than writing a new C file.

> See [API_REFERENCE.md, Section 5](API_REFERENCE.md#5-two-tier-driver-registry-c) for the
> C struct definitions and override examples.

### 3.6 Device Owns I/O Primitives

The vendor library duplicates `Reset()`, `SendCommand()`, `SendData()`, and `ReadBusy()` as
static functions in every one of 70 driver files. These are identical except for busy-wait
polarity and reset timing, both configurable via `epd_model_config_t`.

In our architecture, these live on the **Device** as shared functions parameterized by model
config: `epd_reset()`, `epd_send_command()`, `epd_send_data()`, `epd_send_data_bulk()`,
`epd_read_busy()`. This eliminates ~20 lines x 70 drivers = **~1,400 lines of duplicated
C code** and centralizes the timeout/interruptibility improvement in one place.

### 3.7 Three-Layer Drawing Architecture

The vendor's `PAINT` struct conflates pixel storage, coordinate transforms, and drawing state
into a single global. Our design separates these into three layers with distinct responsibilities:

```
┌─────────────────────────────────────────────────────────┐
│                   🎨 Drawing Layer                       │
│                                                          │
│  Surface ← duck-type protocol (set_pixel, dimensions)   │
│    ├── Canvas        (RGBA packed String, C-accelerated) │
│    ├── Layer         (clipped sub-region of a Surface)   │
│    └── Framebuffer   (device-format, C-backed)           │
│                                                          │
│  Drawing primitives work on any Surface:                 │
│    line, rect, circle, text, blit, flood_fill            │
│                                                          │
├─────────────────────────────────────────────────────────┤
│                   🔄 Rendering Layer                     │
│                                                          │
│  Renderer: Canvas → Framebuffer                          │
│    • Palette mapping (Color → palette entry)              │
│    • Dithering (Floyd-Steinberg, ordered, threshold)     │
│    • Dual-buffer splitting (one Canvas → two mono FBs)   │
│                                                          │
├─────────────────────────────────────────────────────────┤
│                   ⚡ Hardware Layer                       │
│                                                          │
│  Framebuffer (C) → Display (C) → Device (C)              │
│    • Pixel packing, SPI transfer, GPIO lifecycle         │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

#### Surface: The Drawing Target Protocol

Any object that includes `Surface` is a valid drawing target. The module requires three
methods from includers (`set_pixel`, `get_pixel`, `width`/`height`) and provides drawing
primitives as mixins. The same `draw_line` works on a Canvas (RGB), a Framebuffer (device
format), or a Layer (clipped sub-region).

`set_pixel` silently clips out-of-bounds writes. `get_pixel` returns `nil` for out-of-bounds
reads. This asymmetry is intentional: silent clipping avoids overhead in the hot drawing path,
while explicit `nil` prevents silent use of garbage data on reads.

#### Canvas: RGBA Compositing Surface

Canvas stores pixels in a **packed binary String** (4 bytes/pixel: RGBA). This is a single
GC object regardless of resolution. C accelerators (~80 lines in `canvas.c`) handle three
hot paths that would otherwise require per-pixel Ruby→C round-trips: `_canvas_clear`,
`_canvas_blit_alpha`, `_canvas_load_rgba`. All three have Ruby fallbacks.

| Metric                    | Array\<Color\> (rejected) | Packed String (chosen)   |
|---------------------------|--------------------------|--------------------------|
| Memory per 800×480 Canvas | ~15MB (384K × ~40B)      | ~1.5MB (384K × 4B)      |
| GC objects per Canvas     | ~384,001                 | 2 (Canvas + String)      |
| `Canvas.new` + clear      | ~120ms (384K Color.new)  | <1ms (String.new)        |
| `Image#draw_onto` 800×480 | ~800ms (384K Color.new)  | ~5ms (C bulk memcpy)     |
| `blit` 400×300 with alpha | ~50ms (120K get/over/set)| ~2ms (C alpha loop)      |
| 4 Layers on Pi Zero       | ~60MB, GC thrashing      | ~6MB, no GC pressure     |

**Why an RGBA intermediate matters:** If Canvas wrote directly to a Framebuffer, every
`set_pixel` quantizes immediately — a photo blitted onto a mono surface loses all color
information before text could be composited over it. With an RGBA Canvas, composition happens
in full color and quantization is applied once at the end by the Renderer.

**Color materialization is lazy.** `get_pixel` creates a `Color` on demand from 4 bytes.
Bulk operations (image loading, blit, clear, quantization) operate directly on packed bytes,
bypassing Color entirely. The Renderer iterates `canvas.rgba_bytes` in a single linear scan.

#### Layer: Clipped Sub-Region

A Layer wraps a parent Surface with an offset and clip rectangle. Drawing uses local
coordinates (0,0 is top-left of the layer). Layers compose — a Layer of a Layer works
correctly. This is the foundation for widget-based UI composition.

Layer bounds are **not validated** against the parent. Out-of-bounds coordinates delegate to
the parent's clipping behavior. This avoids validation overhead and allows intentional
"overflow" patterns.

#### Renderer: Canvas → Framebuffer Bridge

The Renderer owns **quantization** — converting RGBA Canvas pixels to palette entries in a
device-format Framebuffer. This is the only place where dithering algorithms are applied
(Floyd-Steinberg default, ordered for text, threshold for line art). Dual-buffer channel
splitting also lives here — the `DualBuffer` capability module is hardware-only (SPI send);
the Renderer handles the logical concern of routing colors to two mono layers.

#### Framebuffer: Device-Format Pixel Storage

C-backed pixel buffer in the display's native format. Includes `Surface` so it can be drawn
on directly (power-user path). `set_pixel` accepts palette entry symbols (`:black`, `:red`);
the C implementation maps to integer indices and bit-packs. The `Surface` protocol is
duck-typed — it passes color values through without constraining the type.

#### Transform Integration

Coordinate transforms (rotation, mirroring) apply at the `Surface` level via a `Transform`
value object composed with a `TransformedSurface` wrapper. Canvas always operates in logical
(unrotated) coordinates — physical rotation is applied at the Renderer→Framebuffer boundary.

> **Deferred design:** The concrete Transform API will be designed during implementation.

> See [API_REFERENCE.md, Sections 2-4](API_REFERENCE.md#2-surface-protocol--implementations)
> for full Surface, Canvas, Layer, Framebuffer, and Renderer implementations.

---

## 4. Content Pipeline

The content that flows through the drawing layers — colors, shapes, text, icons, and images —
is specified in a dedicated document.

> See [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md) for the complete content pipeline spec.

**Summary:** Colors are RGBA `Data.define` value objects with alpha compositing. Drawing
primitives (Bresenham, midpoint circle, scanline fill) are `Surface` mixins. Text rendering
uses FreeType (C-linked) for glyph rasterization with Ruby-side layout. Icons use an
`IconFont` class with bundled Lucide (~1,500 icons, ISC license). Images load via ruby-vips
with bulk RGBA transfer into Canvas.

---

## 5. Integration Challenges

### 5.1 Platform Detection in `extconf.rb`

Need to:
- Check for `lgpio.h`, `bcm2835.h`, `wiringPi.h`, `gpiod.h` headers
- Check for corresponding `-l` libraries
- Auto-select the best available backend
- Provide a `--with-epd-backend=` configure option for override
- Define a `MOCK` backend for development/testing on non-RPi systems

**Fallback behavior:** If no GPIO/SPI library is found, `extconf.rb` **auto-selects the MOCK
backend** and emits a warning. The gem always installs. Under MOCK, `Framebuffer`, `Canvas`,
`PixelFormat`, and all drawing operations work normally (pure memory, no hardware). Hardware
operations (`Display#show`, `Display#clear`, `Device.new`) raise `ChromaWave::DeviceError`
at runtime with a clear message.

**FreeType is optional.** If not found, the extension compiles without `freetype.c` and sets
`-DNO_FREETYPE`. At runtime, `Font.new`, `IconFont.new`, and `Surface#draw_text` raise
`ChromaWave::DependencyError` with an install hint (`apt install libfreetype-dev`).

### 5.2 Buffer Ownership and GC Integration

Framebuffers own pixel data allocated via `xmalloc`/`xfree` (Ruby's tracked allocator).
Wrapped with `TypedData_Wrap_Struct` with:
- `dfree`: calls `xfree` on the pixel buffer
- `dsize`: reports `buffer_size` bytes to Ruby's GC for memory pressure tracking
- `dmark`: not needed (no `VALUE`s stored in the C struct)
- `flags`: `RUBY_TYPED_FREE_IMMEDIATELY` (no GVL needed for `xfree`)

### 5.3 Busy-Wait Blocking and GVL Release

`EPD_*_ReadBusy()` spin-waits with no timeout. This blocks the GVL. Our design:
- Wrap display refresh operations with `rb_thread_call_without_gvl()` so other Ruby threads
  can run during the (potentially multi-second) refresh cycle
- Add a configurable timeout with an interruptible loop (10ms polling interval)
- Provide an unblocking function (`ubf`) for clean interrupt of long refreshes

### 5.4 EPD_7in5_V2 Destructive Buffer Inversion

`EPD_7IN5_V2_Display()` modifies the caller's buffer in-place (bitwise NOT) before sending
over SPI. This is a bug in the vendor code. **Resolution:** Copy the buffer before passing to
the driver. The copy cost is negligible (800x480/8 = 48KB, microseconds to copy).

### 5.5 EPD_5in65f Dual Busy Polarity

`EPD_5in65f` uses both busy-HIGH and busy-LOW waits in different lifecycle phases.
**Resolution:** This model already requires a Tier 2 override for its power-on/off-per-refresh
cycle. The override owns its busy-wait logic entirely, calling polarity-specific helpers
internally. No change to the Tier 1 config struct is needed.

### 5.6 Error Handling Strategy

A **categorized exception hierarchy** separates hardware errors (inherit from
`ChromaWave::Error < StandardError`) from API misuse errors (inherit from `ArgumentError` /
`TypeError`). C functions return `int` status codes; Ruby wrappers check and raise the
appropriate exception.

> See [API_REFERENCE.md, Section 6](API_REFERENCE.md#6-error-hierarchy) for the full
> hierarchy.

### 5.7 Thread Safety

Device-level mutual exclusion via a Ruby `Mutex`. All hardware operations synchronize through
the Device's mutex. Pure-memory operations (`Framebuffer#set_pixel`, Canvas drawing) are
**not locked** — contention is the caller's responsibility.

The GVL release composes correctly: mutex acquired before entering C, GVL released inside C
for busy-wait, mutex released after C returns. Other Ruby threads can run during busy-wait
but cannot start a concurrent hardware operation.

### 5.8 Multi-Display (Out of Scope for v1)

Multiple displays on one Raspberry Pi are architecturally possible — the SPI bus is shared
while each display needs its own CS, DC, RST, and BUSY GPIO pins. However, the vendor HAL
hardcodes pin assignments as global integers and supports only one active display. Supporting
multi-display would require reworking the HAL to accept per-display pin configuration. This
is deferred to a future version — v1 supports one Display per Device (1:1).

---

## 6. Expected C Footprint

| Component           | Vendor Lines | After Refactor | Notes                           |
|---------------------|-------------|----------------|---------------------------------|
| DEV_Config + backends| ~1,200     | ~1,200         | Used as-is                      |
| EPD_*.c drivers     | ~25,000     | ~8,000         | Data tables + ~20 custom files  |
| GUI_Paint + BMPfile | ~1,200      | ~100           | Pixel packing only              |
| Fonts               | ~15,000     | 0              | Not vendored                    |
| Canvas accelerators | 0           | ~80            | New: clear, blit_alpha, load_rgba |
| FreeType bindings   | 0           | ~200           | New: glyph rasterization bridge |
| **Total**           | **~42,400** | **~9,580**     | **23% of original**             |

