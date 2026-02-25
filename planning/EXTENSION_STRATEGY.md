# ChromaWave C Extension Strategy

Design decisions and architecture for the Ruby C extension that wraps the Waveshare vendor
library. For documentation of the vendor library itself, see [WAVESHARE_LIBRARY.md](WAVESHARE_LIBRARY.md).

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
  proper `dfree` cleanup. Use `Ensure`-style block patterns.
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
| Coordinate transforms      | Ruby  | Rotation/mirror matrix math, no hardware      |
| Surface protocol           | Ruby  | Abstract drawing target (duck-type interface) |
| Canvas (RGB buffer)        | Ruby  | Off-screen compositing in full color space    |
| Layer composition          | Ruby  | Clip regions, offset blitting, widget bounds  |
| Drawing primitives         | Ruby  | Bresenham algorithms, calls `Surface#set_pixel`|
| Rendering / quantization   | Ruby  | RGB→palette mapping, dithering, dual-buf split|
| Text rendering             | Ruby  | FreeType or pre-rendered, not bitmap fonts    |
| Image loading/conversion   | Ruby  | MiniMagick, load into Canvas as RGB pixels    |
| Display capability queries | Ruby  | `respond_to?` / module inclusion checks       |
| Model configuration        | Ruby  | Resolution, format, capabilities per model    |

---

## 3. Architecture

### 3.1 The `PixelFormat` Unifying Concept

The vendor library's `Scale` value, the color constants, and the buffer size math all express
the same underlying concept: **how pixels are packed into bytes**. This concept appears in at
least four places in a naive design (Image buffer, Display config, Color validation, driver
registry). It should be modeled once.

```ruby
module ChromaWave
  class PixelFormat
    attr_reader :name, :bits_per_pixel, :palette

    def pixels_per_byte = 8 / bits_per_pixel

    MONO   = new(name: :mono,   bpp: 1, palette: %i[black white])
    GRAY4  = new(name: :gray4,  bpp: 2, palette: %i[black dark_gray light_gray white])
    COLOR4 = new(name: :color4, bpp: 4, palette: %i[black white yellow red])
    COLOR7 = new(name: :color7, bpp: 4,
                 palette: %i[black white green blue red yellow orange])

    def buffer_size(width, height)
      bytes_per_row = (width + pixels_per_byte - 1) / pixels_per_byte
      bytes_per_row * height
    end

    def valid_color?(color) = palette.include?(color)
  end
end
```

> **Note on palette ordering:** The vendor library names its grayscale values in reverse
> (`GRAY1` = blackest, `GRAY4` = white). Our `GRAY4` format intentionally reorders the palette
> to `[:black, :dark_gray, :light_gray, :white]` (dark-to-light), which is more intuitive. The
> numeric mapping to vendor values happens at the C boundary.

> **Note on `scale`:** The vendor library uses a `Scale` integer (2, 4, 6, 7) as an enum
> discriminator for pixel-packing mode. This value is **not exposed** in the Ruby `PixelFormat`
> API — it is an internal detail used only at the C boundary where `framebuffer.c` maps
> `pixel_format` enum values to packing logic.

Both `Display` and `Framebuffer` reference a `PixelFormat`. The Display declares what format it
requires. The Framebuffer declares what format it contains. Compatibility is checked once at
the point of use (`display.show(framebuffer)`), not scattered across layers.

**Dual-buffer displays** (black + red/yellow) are modeled as two Framebuffers, both `MONO`
format, not as a special pixel format. The `Renderer` handles splitting a Canvas into the two
mono Framebuffers via color-channel mapping. The `DualBuffer` capability module is purely a
hardware concern — it knows how to send two buffers over SPI (see Section 3.4).

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
  pixel_format.rb                     # PixelFormat value object (MONO, GRAY4, COLOR7, etc.)
  color.rb                            # Color (RGBA value type, named constants, compositing)
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
```

### 3.3 Model Instantiation and the Registry

Users instantiate displays via a **symbol registry**. `Display.new` is a factory that returns
an instance of a dynamically-constructed subclass with the correct capability modules:

```ruby
display = ChromaWave::Display.new(model: :epd_2in13_v4)
display.class                                  # => anonymous subclass of Display
display.respond_to?(:display_partial)          # => true
display.is_a?(Capabilities::PartialRefresh)    # => true

# Discovery
ChromaWave::Display.models  # => [:epd_2in13_v4, :epd_7in5_v2, ...]

# Typo raises immediately
ChromaWave::Display.new(model: :epd_2in13)
# => ChromaWave::ModelNotFoundError: unknown model :epd_2in13
#    Did you mean: :epd_2in13_v4, :epd_2in13b_v4?
```

At gem load time, the registry iterates C-side model configs and builds one Ruby subclass per
model, including the appropriate capability modules based on the config's capability bitfield:

```ruby
CAPABILITY_MAP = {
  EPD_CAP_PARTIAL   => Capabilities::PartialRefresh,
  EPD_CAP_FAST      => Capabilities::FastRefresh,
  EPD_CAP_GRAYSCALE => Capabilities::GrayscaleMode,
  EPD_CAP_DUAL_BUF  => Capabilities::DualBuffer,
  EPD_CAP_REGIONAL  => Capabilities::RegionalRefresh,
}.freeze

ChromaWave::Native.each_model_config do |name, config|
  klass = Class.new(Display) do
    config.capability_flags.each { |flag| include CAPABILITY_MAP[flag] }
  end
  registry[name.to_sym] = klass
end
```

### 3.4 Capabilities as Composable Modules

The vendor drivers expose capabilities as inconsistently-named optional functions
(`Init_Fast`, `Display_Partial`, `Display_Part`, `Display_part`). Rather than modeling these
as nullable function pointers in a flat C struct, use Ruby modules that wrap private C methods:

#### Base Display#show

The base `Display#show` method accepts either a Canvas (common path) or a pre-rendered
Framebuffer (power-user path). Single-buffer displays use this directly; `DualBuffer`
overrides it (see below):

```ruby
module ChromaWave
  class Display
    def show(canvas_or_fb)
      fb = case canvas_or_fb
           when Canvas     then renderer.render(canvas_or_fb)
           when Framebuffer then canvas_or_fb
           else raise TypeError, "expected Canvas or Framebuffer, got #{canvas_or_fb.class}"
           end
      validate_format!(fb)
      device.synchronize { _epd_display(fb) }
    end
  end
end
```

#### Ruby <=> C Bridge

All C-backed display operations are defined as **private methods on the Display base class**
in `Init_chroma_wave`. The Ruby capability modules provide the public API with validation:

```c
/* In chroma_wave.c Init_chroma_wave(): */
rb_define_private_method(rb_cDisplay, "_epd_display_partial",
                         rb_epd_display_partial, 1);
rb_define_private_method(rb_cDisplay, "_epd_init_fast",
                         rb_epd_init_fast, 0);
rb_define_private_method(rb_cDisplay, "_epd_display_fast",
                         rb_epd_display_fast, 1);
rb_define_private_method(rb_cDisplay, "_epd_display_dual",
                         rb_epd_display_dual, 2);
rb_define_private_method(rb_cDisplay, "_epd_display_region",
                         rb_epd_display_region, 5);
/* ... etc. C implementations check driver->custom_display or fall
   through to the generic config-driven path. */
```

```ruby
module ChromaWave
  module Capabilities
    module PartialRefresh
      def display_partial(framebuffer)
        validate_format!(framebuffer)
        _epd_display_partial(framebuffer)   # private C method
      end

      def display_base(framebuffer)
        validate_format!(framebuffer)
        _epd_display_base(framebuffer)
      end
    end

    module FastRefresh
      def init_fast  = _epd_init_fast
      def display_fast(framebuffer)
        validate_format!(framebuffer)
        _epd_display_fast(framebuffer)
      end
    end

    module GrayscaleMode
      def init_grayscale = _epd_init_grayscale
      def display_grayscale(framebuffer)
        validate_format!(framebuffer)
        _epd_display_grayscale(framebuffer)
      end
    end

    module DualBuffer
      # Pure hardware concern: sends two mono framebuffers over SPI.
      # Canvas → dual-FB splitting is handled by Renderer (see Section 3.7).
      def show(canvas_or_fb, second_fb = nil)
        case canvas_or_fb
        when Canvas
          black_fb, red_fb = renderer.render_dual(canvas_or_fb)
          _epd_display_dual(black_fb, red_fb)
        when Framebuffer
          raise ArgumentError, "DualBuffer#show requires two framebuffers" unless second_fb

          [canvas_or_fb, second_fb].each { validate_format!(_1) }
          _epd_display_dual(canvas_or_fb, second_fb)
        end
      end
    end

    module RegionalRefresh
      # Sub-rectangle partial refresh — updates only a region of the display
      # without redrawing the entire screen. Faster than full partial refresh
      # for small UI updates (e.g., clock digit, status icon).
      #
      # Coordinates are in physical display pixels (pre-transform).
      # The framebuffer must match the region dimensions, not the full display.
      def display_region(framebuffer, x:, y:, width:, height:)
        validate_format!(framebuffer)
        expected = pixel_format.buffer_size(width, height)
        unless framebuffer.buffer_size == expected
          raise FormatMismatchError,
                "region framebuffer size #{framebuffer.buffer_size} != expected #{expected} " \
                "for #{width}x#{height} region"
        end
        _epd_display_region(framebuffer, x, y, width, height)
      end
    end
  end
end
```

#### Display#show Accepts Canvas or Framebuffer

`Display#show` is polymorphic — it accepts either a `Canvas` (the common path) or a
pre-rendered `Framebuffer` (the power-user path). For single-buffer displays, the base
`Display#show` handles rendering. For dual-buffer displays, the `DualBuffer` capability
overrides `show` to split the Canvas into two mono Framebuffers via the `Renderer`:

```ruby
# Common path: draw on a Canvas, let Display handle rendering
canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
canvas.draw_rect(10, 10, 100, 50, color: Color::BLACK)
canvas.draw_circle(60, 60, 30, color: Color::RED)
display.show(canvas)                                 # renders + sends to hardware

# Power path: control rendering directly
renderer = ChromaWave::Renderer.new(
  pixel_format: display.pixel_format,
  dither: :ordered                                   # choose dithering strategy
)
fb = renderer.render(canvas)
display.show(fb)                                     # send pre-rendered framebuffer

# Dual-buffer power path: provide two raw framebuffers
display.show(custom_black_fb, custom_red_fb)
```

The Canvas is **independent of any Display** — it can be created, drawn on, and composed
without hardware. The Display's `Renderer` bridges the gap at `show` time (see Section 3.7).

**Advantages over nullable function pointers:**
- Shared behavior is defined once per capability, reused across all models that support it
- `display.respond_to?(:display_partial)` works naturally for capability checking
- `display.is_a?(Capabilities::FastRefresh)` for type-based dispatch
- New capabilities are added without changing existing code (Open/Closed Principle)
- Documentation and tests live with each capability module
- C bridge is explicit: Ruby modules wrap private C methods with validation

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

```c
/* ---- Tier 1: Static configuration (handles 60-70% of drivers completely) ---- */

typedef struct {
    const char   *name;              /* "epd_2in13_v4" */
    uint16_t      width, height;     /* 122, 250 */
    uint8_t       pixel_format;      /* PIXEL_FORMAT_MONO, _GRAY4, _COLOR7, etc. */
    uint8_t       busy_active_level; /* 0 = active-low, 1 = active-high */
    uint16_t      reset_timing[3];   /* {pre_ms, low_ms, post_ms} e.g. {20, 2, 20} */
    uint8_t       display_cmd;       /* 0x24 or 0x10 */
    const uint8_t *init_sequence;    /* Encoded: {cmd, n_data, data0, data1, ...} */
    uint16_t      init_sequence_len;
    uint32_t      capabilities;      /* EPD_CAP_FAST | EPD_CAP_PARTIAL | ... */
} epd_model_config_t;

/* ---- Tier 2: Optional code overrides (only ~20 models need these) ---- */

typedef struct {
    const epd_model_config_t *config;
    int  (*custom_init)(const epd_model_config_t *cfg, uint8_t mode);
    int  (*custom_display)(const epd_model_config_t *cfg, const uint8_t *buf, size_t len);
    void (*pre_display)(const epd_model_config_t *cfg);   /* e.g. 5in65f power-on */
    void (*post_display)(const epd_model_config_t *cfg);  /* e.g. 5in65f power-off */
} epd_driver_t;
```

A single `epd_generic_init()` function interprets `init_sequence` byte arrays and calls
`SendCommand`/`SendData`. Simple monochrome displays need **zero custom C code** -- just a
config struct entry. Complex models (EPD_4in2 with LUT selection, EPD_5in65f with power
cycling, EPD_3in7 with 4-gray repacking) provide override function pointers.

**LUT tables are Tier 2 concerns.** Models that need LUT waveform tables (EPD_4in2 has 5,
EPD_3in7 has mode-dependent LUTs) always need a `custom_init` override for runtime LUT
selection logic. The override function owns its LUT data as `static const` byte arrays:

```c
/* Tier 2 override for EPD_4in2 -- owns its own LUT tables */
static const uint8_t lut_full[]    = { /* ... */ };
static const uint8_t lut_partial[] = { /* ... */ };

static int epd_4in2_custom_init(
    const epd_model_config_t *cfg, uint8_t mode) {
    epd_generic_init(cfg);  /* shared register sequence from Tier 1 */
    switch (mode) {
        case MODE_FULL:    load_lut(lut_full, sizeof(lut_full)); break;
        case MODE_PARTIAL: load_lut(lut_partial, sizeof(lut_partial)); break;
    }
    return EPD_OK;
}
```

This keeps the Tier 1 config struct simple — no LUT pointer fields — while giving Tier 2
models full control over LUT lifecycle and selection.

**Impact:** Adding support for a new simple display model is adding ~10 lines of config data
rather than writing a new C file.

### 3.6 Device Owns I/O Primitives

The vendor library duplicates `Reset()`, `SendCommand()`, `SendData()`, and `ReadBusy()` as
static functions in every one of 70 driver files. These are identical except for:
- Busy-wait polarity (configurable via `epd_model_config_t.busy_active_level`)
- Reset timing (configurable via `epd_model_config_t.reset_timing`)

In our architecture, these live on the **Device**, parameterized by the model config:

```c
/* Shared I/O functions on Device -- called by all drivers */
void epd_reset(const epd_model_config_t *cfg);
void epd_send_command(uint8_t cmd);
void epd_send_data(uint8_t data);
void epd_send_data_bulk(const uint8_t *data, size_t len);
int  epd_read_busy(const epd_model_config_t *cfg, uint32_t timeout_ms);
```

This eliminates ~20 lines x 70 drivers = **~1,400 lines of duplicated C code** and centralizes
the timeout/interruptibility improvement (see Section 5.3) in one place.

### 3.7 Three-Layer Drawing Architecture

The vendor's `PAINT` struct conflates pixel storage, coordinate transforms, and drawing state
into a single global. Our design separates these into three layers with distinct responsibilities:

```
┌─────────────────────────────────────────────────────────┐
│                   🎨 Drawing Layer                       │
│                                                          │
│  Surface ← duck-type protocol (set_pixel, dimensions)   │
│    ├── Canvas        (RGB pixel buffer, pure Ruby)       │
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
│    • Palette mapping (RGB → display palette entries)     │
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

Any object that includes `Surface` is a valid drawing target. Drawing primitives are
decoupled from pixel storage — the same `draw_line` works on a Canvas (RGB), a Framebuffer
(device format), or a Layer (clipped sub-region):

```ruby
module ChromaWave
  module Surface
    # Required by includers:
    #   #width, #height     → Integer
    #   #set_pixel(x, y, color)
    #   #get_pixel(x, y) → color
    #   #clear(color)

    def in_bounds?(x, y) = x >= 0 && x < width && y >= 0 && y < height

    def draw_line(x0, y0, x1, y1, color:)
      # Bresenham — delegates to self.set_pixel
    end

    def draw_rect(x, y, w, h, color:, fill: false)
      # Outline or filled rectangle
    end

    def draw_circle(cx, cy, r, color:, fill: false)
      # Midpoint circle algorithm
    end

    def blit(source, x:, y:)
      # Copy pixels from another Surface
    end
  end
end
```

By defining drawing as a module mixed into Surface implementors, rather than a wrapper class,
drawing works uniformly on any pixel storage. This replaces the old model where Canvas
"wrapped" a Framebuffer — now both are peers that share the same drawing interface.

#### Canvas: RGB Compositing Surface

Canvas is a pure-Ruby pixel buffer that stores colors in a **rich intermediate format**
(RGB or named palette symbols). It has no knowledge of hardware, pixel packing, or display
formats. All compositing happens here, and quantization is deferred to the Renderer:

```ruby
module ChromaWave
  class Canvas
    include Surface

    attr_reader :width, :height

    def initialize(width:, height:, background: Color::WHITE)
      @pixels = Array.new(width * height, background)
    end

    def set_pixel(x, y, color = Color::BLACK)
      return unless in_bounds?(x, y)
      @pixels[y * width + x] = color
    end

    def get_pixel(x, y)
      return unless in_bounds?(x, y)
      @pixels[y * width + x]
    end

    def clear(color = Color::WHITE)
      @pixels.fill(color)
    end

    # Compositing — not possible when drawing directly into a Framebuffer
    def blit(source, x:, y:, opacity: 1.0)
      source.height.times do |sy|
        source.width.times do |sx|
          set_pixel(x + sx, y + sy, source.get_pixel(sx, sy))
        end
      end
    end

    # Create a clipped sub-region for independent drawing
    def layer(x:, y:, width:, height:, &block)
      Layer.new(self, x:, y:, width:, height:).tap { |l| yield l if block }
    end
  end
end
```

**Why an RGB intermediate matters:** If Canvas wrote directly to a Framebuffer, every
`set_pixel` quantizes immediately — a photo blitted onto a mono surface looses all color
information before text could be composited over it. With an RGB Canvas, composition happens
in full color and quantization is applied once at the end by the Renderer. This enables:

- Alpha blending and opacity compositing
- Layered widgets that don't destroy each other's color data
- Dithering algorithms that see the full RGB source (critical for photo quality)
- Color space transforms (gamma correction, contrast adjustment) before quantization

#### Layer: Clipped Sub-Region

A Layer wraps a parent Surface with an offset and clip rectangle. Drawing on a Layer
uses local coordinates (0,0 is top-left of the layer) and clips at the layer boundary:

```ruby
module ChromaWave
  class Layer
    include Surface

    attr_reader :width, :height

    def initialize(parent, x:, y:, width:, height:)
      @parent = parent
      @offset_x = x
      @offset_y = y
      @width = width
      @height = height
    end

    def set_pixel(x, y, color = Color::BLACK)
      return unless in_bounds?(x, y)
      @parent.set_pixel(@offset_x + x, @offset_y + y, color)
    end

    def get_pixel(x, y)
      return unless in_bounds?(x, y)
      @parent.get_pixel(@offset_x + x, @offset_y + y)
    end
  end
end
```

Layers compose naturally — a Layer of a Layer works correctly. This is the foundation for
widget-based UI composition where each component draws in its own coordinate space.

#### Renderer: Canvas → Framebuffer Bridge

The Renderer is responsible for the **quantization step** — converting a rich Canvas into
a device-format Framebuffer. This is the only place where RGB colors are mapped to palette
entries, and where dithering algorithms are applied:

```ruby
module ChromaWave
  class Renderer
    attr_reader :pixel_format, :dither

    def initialize(pixel_format:, dither: :floyd_steinberg)
      @pixel_format = pixel_format
      @dither = dither
    end

    # Render a Canvas into a Framebuffer
    def render(canvas, into: nil)
      fb = into || Framebuffer.new(
        width: canvas.width, height: canvas.height,
        format: pixel_format
      )
      quantize(canvas, fb)
      fb
    end

    # For dual-buffer displays: one Canvas → two mono Framebuffers
    def render_dual(canvas)
      black_fb = Framebuffer.new(width: canvas.width, height: canvas.height,
                                  format: PixelFormat::MONO)
      red_fb   = Framebuffer.new(width: canvas.width, height: canvas.height,
                                  format: PixelFormat::MONO)
      split_channels(canvas, black_fb, red_fb)
      [black_fb, red_fb]
    end

    private

    def quantize(canvas, fb)
      # Map each RGB pixel → nearest palette entry
      # Apply dithering algorithm to distribute quantization error
      # Write packed pixels to fb.set_pixel
    end

    def split_channels(canvas, black_fb, red_fb)
      # Route :black/:dark pixels → black_fb
      # Route :red/:yellow pixels → red_fb
      # Everything else → black_fb (default layer)
    end
  end
end
```

**Dithering lives here, not in Canvas or Framebuffer.** Dithering requires seeing the full RGB
source and writing to the quantized destination — it inherently spans both. The Renderer owns
this bridge. Different dithering strategies (Floyd-Steinberg for photos, ordered for text,
threshold for line art) are selectable per render call.

**Dual-buffer splitting lives here, not in DualBuffer.** The `DualBuffer` capability module
(Section 3.4) is purely a hardware concern — it sends two framebuffers over SPI. The
Renderer handles the *logical* concern of splitting a single Canvas into two mono layers
based on color routing. This separation means layering and compositing work identically
whether the display is single-buffer or dual-buffer — the Canvas doesn't know or care.

#### Framebuffer: Device-Format Pixel Storage

The Framebuffer is the C-backed pixel buffer in the display's native format. It includes
`Surface` so it can be drawn on directly (bypassing Canvas + Renderer for power users),
but its primary role is as the Renderer's output and the Display's input:

```
Framebuffer (C-backed, TypedData)
  +-- Includes: Surface protocol
  +-- Owns: raw byte buffer (xmalloc'd)
  +-- Knows: width, height, PixelFormat
  +-- Methods: set_pixel, get_pixel, clear, buffer_bytes, buffer_size
  +-- set_pixel/get_pixel: format-aware bit-packing (C, ~100 lines from GUI_Paint.c)
  +-- No drawing state, no transforms, no global state
```

The C implementation extracts only the pixel-packing logic from `GUI_Paint.c` (~100 lines:
the `Scale`-dependent bit-twiddling in `Paint_SetPixel` and `Paint_Clear`). No forking of
GUI_Paint.c is needed.

> **Padding invariant:** For non-byte-aligned widths, the trailing bits in the last byte of
> each row are **always zero**. This applies to all sub-byte formats: MONO (1 bpp, e.g.,
> 122px = 15.25 bytes/row → 16 bytes with 6 padding bits) and GRAY4 (2 bpp, e.g., 122px =
> 30.5 bytes/row → 31 bytes with 4 padding bits). `set_pixel` never writes to padding
> positions, and `clear` zeros the entire buffer including padding. This invariant must be
> preserved by `framebuffer.c` to prevent display artifacts from garbage padding bits.

#### Composing a Dashboard: End-to-End Example

The three-layer architecture enables widget-based UI composition that would be awkward or
impossible with Canvas directly wrapping Framebuffer:

```ruby
display = ChromaWave::Display.new(model: :epd_7in5_v2)
canvas  = ChromaWave::Canvas.new(width: display.width, height: display.height)

# Header bar — independent clipped region, local coordinates
canvas.layer(x: 0, y: 0, width: 800, height: 60) do |header|
  header.clear(Color::BLACK)
  header.draw_text("Dashboard", x: 10, y: 10, color: Color::WHITE, font: title_font)
end

# Chart widget — rendered off-screen, blitted into position
chart = render_temperature_chart(width: 380, height: 200)  # returns a Canvas
canvas.blit(chart, x: 10, y: 70)

# Sidebar — another independent region
canvas.layer(x: 410, y: 70, width: 380, height: 400) do |sidebar|
  sidebar.draw_text("Status: OK", x: 10, y: 10, color: Color::BLACK, font: body_font)
  sidebar.draw_rect(0, 0, sidebar.width, sidebar.height, color: Color::BLACK)
end

# Single render pass: RGB canvas → quantized framebuffer → hardware
display.show(canvas)
```

#### Memory Tradeoff

Canvas stores an `Array` of `Color` objects. On CRuby, each `Color` holds 4 integers plus
object overhead (~80 bytes), so an 800x480 Canvas uses ~30MB (384K pixels × ~80 bytes) vs
48KB for a mono Framebuffer. On a Raspberry Pi with 1–8GB RAM this is acceptable. For
memory-constrained scenarios, users can draw directly on a Framebuffer via the `Surface`
protocol — the path exists, it just skips Canvas compositing and Renderer quantization.

> **Future optimization:** If Canvas memory becomes an issue, a C-backed RGBA buffer (4
> bytes/pixel, ~1.5MB for 800x480) can replace the Ruby Array without changing the Surface
> API. This is deferred until profiling shows it's needed.

#### Transform Integration

Coordinate transforms (rotation, mirroring) apply at the `Surface` level. A `Transform`
value object is composed with any Surface to map logical coordinates to physical coordinates:

```
Transform (Ruby value object)
  +-- Knows: rotation (0/90/180/270), mirror mode, logical dimensions
  +-- Method: apply(x, y) -> [physical_x, physical_y]
  +-- Composed with any Surface via TransformedSurface wrapper
```

The Display applies the correct Transform based on its model config when rendering a Canvas
to a Framebuffer. Users can also apply transforms explicitly for custom coordinate systems.

---

## 4. Content Pipeline

### 4.1 Overview

Section 3.7 defines the structural layers (Surface, Canvas, Renderer, Framebuffer). This
section specifies the **content** that flows through those layers: colors, shapes, text,
and images.

### 4.2 Color Model (RGBA)

Canvas compositing requires a richer color representation than the display's final palette.
Colors are modeled as **RGBA values** with a bridge to named palette symbols:

```ruby
module ChromaWave
  class Color
    attr_reader :r, :g, :b, :a

    def initialize(r, g, b, a = 255)
      @r = r; @g = g; @b = b; @a = a
    end

    def opaque?  = a == 255
    def transparent? = a == 0

    # Alpha compositing (Porter-Duff "source over")
    def over(background)
      return self if opaque?
      return background if transparent?
      alpha = a / 255.0
      Color.new(
        (r * alpha + background.r * (1 - alpha)).round,
        (g * alpha + background.g * (1 - alpha)).round,
        (b * alpha + background.b * (1 - alpha)).round
      )
    end

    # Named constants — RGB values that map to common display palettes
    BLACK      = new(0,   0,   0)
    WHITE      = new(255, 255, 255)
    RED        = new(255, 0,   0)
    YELLOW     = new(255, 255, 0)
    GREEN      = new(0,   128, 0)
    BLUE       = new(0,   0,   255)
    ORANGE     = new(255, 165, 0)
    DARK_GRAY  = new(85,  85,  85)
    LIGHT_GRAY = new(170, 170, 170)
    TRANSPARENT = new(0, 0, 0, 0)
  end
end
```

**How RGBA flows through the pipeline:**

| Stage              | Color representation | Alpha behavior                          |
|--------------------|----------------------|-----------------------------------------|
| `set_pixel`        | `Color` (RGBA)       | Direct replacement (no compositing)     |
| `blit` / `render_glyph` | `Color` (RGBA) | Per-pixel alpha compositing (source over)|
| Renderer quantize  | RGBA → palette index | Alpha flattened against background color|
| Framebuffer        | Palette index (int)  | No alpha — device format is opaque      |

Alpha exists only in the Canvas layer. The Renderer flattens it during quantization
(compositing against a configurable background, typically white for e-paper). The
Framebuffer and Display never see alpha — they work with opaque palette indices.

> **Named colors and palettes:** `Color::RED` is an RGB value. The `Renderer` maps it to
> the nearest palette entry during quantization (e.g., index 3 on a COLOR4 display). Users
> can also use `PixelFormat#palette` symbols (`:red`, `:black`) when drawing directly onto
> a Framebuffer via the Surface protocol — these bypass the Renderer and write palette
> indices directly. The two systems coexist: RGB for Canvas compositing, palette symbols for
> direct Framebuffer access.

### 4.3 Shape Primitives

The `Surface` module provides a practical set of drawing primitives. All shapes support
`stroke_width:` for thick outlines and `fill:` for solid fills:

```ruby
module ChromaWave
  module Surface
    # --- Lines ---

    def draw_line(x0, y0, x1, y1, color:, stroke_width: 1)
      # Bresenham for 1px, offset parallel lines for thick strokes
    end

    def draw_polyline(points, color:, stroke_width: 1, closed: false)
      # Connected line segments. points = [[x0,y0], [x1,y1], ...]
      # closed: true connects last point back to first
    end

    # --- Rectangles ---

    def draw_rect(x, y, width, height, color:, stroke_width: 1, fill: false)
      # Outline or filled rectangle
    end

    def draw_rounded_rect(x, y, width, height, radius:, color:,
                          stroke_width: 1, fill: false)
      # Rectangle with rounded corners (quarter-circle arcs)
    end

    # --- Curves ---

    def draw_circle(cx, cy, r, color:, stroke_width: 1, fill: false)
      # Midpoint circle algorithm
    end

    def draw_ellipse(cx, cy, rx, ry, color:, stroke_width: 1, fill: false)
      # Midpoint ellipse algorithm
    end

    def draw_arc(cx, cy, r, start_angle, end_angle, color:, stroke_width: 1)
      # Circular arc segment (angles in radians)
    end

    # --- Polygons ---

    def draw_polygon(points, color:, stroke_width: 1, fill: false)
      # Closed polygon. Outline via draw_polyline(closed: true).
      # Fill via scanline fill algorithm.
    end

    # --- Bulk operations ---

    def blit(source, x:, y:)
      # Copy pixels from another Surface with alpha compositing
    end

    def flood_fill(x, y, color:)
      # Seed fill from (x, y), replacing contiguous same-colored region
    end
  end
end
```

> **Stroke width implementation:** For `stroke_width: 1` (the default), standard Bresenham
> and midpoint algorithms are used. For thicker strokes, lines use offset parallel lines,
> and curves use the inner/outer radius technique (draw two concentric curves and fill
> between them). This is simpler and faster than general stroke expansion.

> **Coordinate convention:** All coordinates are integer pixels, origin at top-left, x
> increases right, y increases down. This matches the display's physical pixel grid and
> avoids sub-pixel complexity that isn't meaningful on e-paper.

### 4.4 Text Rendering

Text rendering uses **FreeType** linked directly in the C extension. The C layer handles
glyph rasterization (the performance-sensitive part). The Ruby layer handles font
management, measurement, and layout:

```
┌──────────────────────────────────────────────────┐
│                  Ruby (layout)                    │
│                                                   │
│  Font          loads TTF/OTF, holds FT_Face ref  │
│  Font#measure  glyph metrics → bounding box      │
│  Font#each_glyph  yields positioned glyph bitmaps│
│  draw_text     layout + render onto Surface      │
│                                                   │
├──────────────────────────────────────────────────┤
│                  C (rasterization)                │
│                                                   │
│  ft_render_glyph   FT_Load_Char + FT_Render      │
│  ft_glyph_metrics  advance width, bearing, bbox  │
│  Linked: libfreetype via extconf.rb              │
│                                                   │
└──────────────────────────────────────────────────┘
```

#### Font Loading

```ruby
module ChromaWave
  class Font
    attr_reader :size, :path

    def initialize(path_or_name, size:)
      # Accepts a TTF/OTF file path or a system font name
      # System font lookup: searches standard font directories
      #   /usr/share/fonts, ~/.fonts, etc.
      @path = resolve_font_path(path_or_name)
      @size = size
      @ft_face = _ft_load_face(@path, @size)  # private C method
    end

    # Measure text without rendering — essential for layout
    def measure(text)
      TextMetrics.new(
        width:    _ft_measure_width(text),
        height:   _ft_line_height,
        ascent:   _ft_ascent,
        descent:  _ft_descent
      )
    end

    # Iterate glyphs with position info — used by draw_text
    def each_glyph(text, &block)
      # Yields: { char:, bitmap:, x:, y:, width:, height: }
      # bitmap is a 2D grayscale array (0-255 alpha values)
    end
  end

  TextMetrics = Data.define(:width, :height, :ascent, :descent)
end
```

#### Drawing Text on a Surface

```ruby
module ChromaWave
  module Surface
    def draw_text(text, x:, y:, font:, color: Color::BLACK,
                  align: :left, max_width: nil)
      lines = max_width ? word_wrap(text, font:, max_width:) : [text]

      lines.each_with_index do |line, i|
        line_y = y + (i * font.measure(line).height)
        line_x = case align
                 when :left   then x
                 when :center then x + (max_width - font.measure(line).width) / 2
                 when :right  then x + (max_width - font.measure(line).width)
                 end

        font.each_glyph(line) do |glyph|
          render_glyph(glyph, line_x + glyph[:x], line_y + glyph[:y], color)
        end
      end
    end

    private

    def render_glyph(glyph, x, y, color)
      glyph[:bitmap].each_with_index do |row, gy|
        row.each_with_index do |alpha, gx|
          next if alpha == 0
          set_pixel(x + gx, y + gy, Color.new(color.r, color.g, color.b, alpha))
        end
      end
    end

    def word_wrap(text, font:, max_width:)
      # Split text into lines that fit within max_width
      # Break on whitespace boundaries
    end
  end
end
```

> **Anti-aliasing and e-paper:** FreeType produces grayscale glyph bitmaps (256 levels of
> alpha). On Canvas, these alpha values composite smoothly against any background. When the
> Renderer quantizes to a limited palette, the dithering algorithm handles the grayscale
> edges — Floyd-Steinberg dithering on text produces clean, readable results even on mono
> displays. This is significantly better than binary (on/off) glyph rendering.

> **C extension surface:** FreeType is linked in `extconf.rb` via
> `have_library('freetype')` and `find_header('ft2build.h')`. The C methods
> `_ft_load_face`, `_ft_render_glyph`, and `_ft_measure_width` are defined as private
> methods on a `ChromaWave::Font` class registered in `Init_chroma_wave`. The `FT_Library`
> is initialized once at gem load time and cleaned up via an `at_exit` hook.

#### Font Discovery

```ruby
module ChromaWave
  class Font
    SYSTEM_FONT_DIRS = [
      "/usr/share/fonts",
      "/usr/local/share/fonts",
      File.expand_path("~/.fonts"),
      File.expand_path("~/.local/share/fonts"),
    ].freeze

    private

    def resolve_font_path(path_or_name)
      return path_or_name if File.exist?(path_or_name)

      # Search system font directories — try exact stem first, then fuzzy
      exact_pattern = "**/#{path_or_name}.{ttf,otf}"
      fuzzy_pattern = "**/*#{path_or_name}*.{ttf,otf}"

      [exact_pattern, fuzzy_pattern].each do |pattern|
        SYSTEM_FONT_DIRS.each do |dir|
          match = Dir.glob(File.join(dir, pattern), File::FNM_CASEFOLD).first
          return match if match
        end
      end

      raise ArgumentError, "Font not found: #{path_or_name}"
    end
  end
end
```

### 4.5 Icon Support (Bundled Lucide + IconFont)

Icons are a special case of text rendering — icon fonts are TTF files where glyphs are
symbols instead of letters. Since we already have FreeType, the infrastructure is free. The
gap is **convenience**: mapping human-readable names to Unicode codepoints.

#### Bundled Font

The gem ships [Lucide](https://lucide.dev/) (ISC license, ~120KB TTF, ~1,500 icons) as a
zero-config icon set. The font and its license live in the gem's `data/` directory:

```
data/
  fonts/
    lucide.ttf
    LICENSE-lucide.txt
```

Accessed at runtime via a root path helper:

```ruby
module ChromaWave
  def self.data_path(*segments)
    File.join(File.expand_path("../..", __dir__), "data", *segments)
  end
end
```

#### IconFont Class

`IconFont` subclasses `Font` and adds a symbol → codepoint registry. It works with any
icon font (Font Awesome, Material Symbols, Phosphor, etc.), not just the bundled Lucide:

```ruby
module ChromaWave
  class IconFont < Font
    attr_reader :glyphs

    def initialize(path_or_name = nil, size:, glyphs: {})
      path = path_or_name || ChromaWave.data_path("fonts", "lucide.ttf")
      super(path, size:)
      @glyphs = glyphs.freeze
    end

    # Look up a glyph by name
    def codepoint(name)
      glyphs.fetch(name) do
        raise ArgumentError, "Unknown icon: #{name}. " \
              "Available: #{glyphs.keys.first(10).join(', ')}..."
      end
    end

    # Convenience: render a single icon onto a Surface
    def draw(surface, name, x:, y:, color: Color::BLACK)
      surface.draw_text(codepoint(name).chr(Encoding::UTF_8),
                        x:, y:, font: self, color:)
    end

    # Built-in Lucide icon set with pre-mapped names
    def self.lucide(size:)
      new(size:, glyphs: LUCIDE_GLYPHS)
    end

    # Subset of Lucide's ~1,500 icons — the full map is generated from
    # Lucide's metadata at gem build time
    LUCIDE_GLYPHS = {
      wifi:          0xE801,
      battery_full:  0xE802,
      battery_low:   0xE803,
      sun:           0xE804,
      cloud:         0xE805,
      cloud_rain:    0xE806,
      thermometer:   0xE807,
      arrow_up:      0xE808,
      arrow_down:    0xE809,
      check:         0xE80A,
      x:             0xE80B,
      alert_triangle: 0xE80C,
      clock:         0xE80D,
      settings:      0xE80E,
      # ... ~1,500 total, generated from Lucide metadata
    }.freeze
  end
end
```

#### Usage

```ruby
# Zero-config: bundled Lucide icons
icons = ChromaWave::IconFont.lucide(size: 32)
icons.draw(canvas, :wifi, x: 10, y: 10)
icons.draw(canvas, :battery_full, x: 50, y: 10, color: Color::BLACK)
icons.draw(canvas, :cloud_rain, x: 90, y: 10)

# Or inline with draw_text for mixed content
font  = ChromaWave::Font.new("DejaVuSans", size: 16)
canvas.draw_text("Signal: Strong ", x: 50, y: 14, font:)
icons.draw(canvas, :wifi, x: 170, y: 10)

# Custom icon font (e.g., Font Awesome)
fa = ChromaWave::IconFont.new(
  "/usr/share/fonts/FontAwesome.ttf",
  size: 24,
  glyphs: { home: 0xF015, user: 0xF007, cog: 0xF013 }
)
fa.draw(canvas, :home, x: 10, y: 100)
```

> **Glyph map generation:** The `LUCIDE_GLYPHS` hash is generated from Lucide's
> `info.json` metadata file via a Rake task (`rake icons:generate`). This runs at gem
> build/development time, not at runtime. The generated file is checked into the repo.

> **Why Lucide:** ISC license (MIT-compatible, no attribution clause in binary
> distribution). ~1,500 icons with good coverage of dashboard-relevant symbols (weather,
> connectivity, status, navigation, devices). Actively maintained. Small file (~120KB TTF).

### 4.6 Image Loading (ruby-vips)

Images are loaded via **ruby-vips** and converted to Canvas-compatible pixel data. The
`Image` class provides a thin wrapper that handles format detection, color space conversion,
resizing, and pixel extraction:

```ruby
module ChromaWave
  class Image
    attr_reader :width, :height

    def initialize(vips_image)
      @vips_image = ensure_rgba(vips_image)
      @width  = @vips_image.width
      @height = @vips_image.height
    end

    # --- Loading ---

    def self.load(path)
      new(Vips::Image.new_from_file(path))
    end

    def self.from_buffer(data)
      new(Vips::Image.new_from_buffer(data, ""))
    end

    # --- Transforms (return new Image, non-destructive) ---

    def resize(width: nil, height: nil)
      scale = if width && height
                [width.to_f / self.width, height.to_f / self.height].min
              elsif width
                width.to_f / self.width
              else
                height.to_f / self.height
              end
      Image.new(@vips_image.resize(scale))
    end

    def crop(x, y, width, height)
      Image.new(@vips_image.crop(x, y, width, height))
    end

    # --- Canvas integration ---

    def to_canvas
      Canvas.new(width:, height:).tap do |canvas|
        pixels = @vips_image.write_to_memory.unpack("C*")
        height.times do |y|
          width.times do |x|
            offset = (y * width + x) * 4
            canvas.set_pixel(x, y, Color.new(
              pixels[offset], pixels[offset + 1],
              pixels[offset + 2], pixels[offset + 3]
            ))
          end
        end
      end
    end

    # Blit directly onto an existing Canvas (avoids intermediate Canvas)
    def draw_onto(canvas, x:, y:)
      pixels = @vips_image.write_to_memory.unpack("C*")
      height.times do |row|
        width.times do |col|
          offset = (row * width + col) * 4
          color = Color.new(
            pixels[offset], pixels[offset + 1],
            pixels[offset + 2], pixels[offset + 3]
          )
          canvas.set_pixel(x + col, y + row, color)
        end
      end
    end

    private

    def ensure_rgba(vips_image)
      case vips_image.bands
      when 1 then vips_image.colourspace(:srgb)                        # grayscale → RGB
                             .bandjoin(vips_image.new_from_image(255)) # + full alpha
      when 3 then vips_image.bandjoin(vips_image.new_from_image(255))  # RGB → RGBA
      when 4 then vips_image                                           # already RGBA
      end.cast(:uchar)
    end
  end
end
```

#### End-to-End Image Workflow

```ruby
display = ChromaWave::Display.new(model: :epd_7in5_v2)
canvas  = ChromaWave::Canvas.new(width: display.width, height: display.height)

# Load a photo, resize to fit, blit onto canvas
photo = ChromaWave::Image.load("vacation.jpg")
photo = photo.resize(width: 400)
photo.draw_onto(canvas, x: 200, y: 40)

# Load an icon with transparency — alpha composites correctly
icon = ChromaWave::Image.load("wifi.png")     # PNG with alpha channel
icon.draw_onto(canvas, x: 10, y: 10)          # transparent pixels blend

# Add text overlay
font = ChromaWave::Font.new("DejaVuSans", size: 24)
canvas.draw_text("Signal: Strong", x: 80, y: 20, font:, color: Color::BLACK)

# Render and display — Renderer quantizes RGB→mono with dithering
display.show(canvas)
```

> **Why ruby-vips and not an adapter pattern:** This gem targets Raspberry Pi hardware.
> Users who can install GPIO/SPI libraries can install libvips (`apt install libvips-dev`).
> The direct dependency avoids abstraction overhead and gives access to vips' full feature
> set (color space conversion, sharpening, contrast adjustment) which is valuable for
> preparing photos for limited-palette displays. For users who only need the drawing
> primitives and text (no photo loading), `Image` is never required — Canvas and Surface
> work independently.

### 4.7 Updated Directory Structure

The content pipeline adds the following files:

```
data/
  fonts/
    lucide.ttf                        # Bundled icon font (~120KB, ISC license)
    LICENSE-lucide.txt                # Lucide license text

lib/chroma_wave/
  color.rb                            # Color (RGBA value type, named constants, compositing)
  drawing/                            # Drawing primitives (mixed into Surface)
    primitives.rb                     #   line, polyline, rect, rounded_rect, circle,
    |                                 #   ellipse, arc, polygon, flood_fill
    text.rb                           #   draw_text, word_wrap, render_glyph
  font.rb                            # Font (FreeType wrapper, measurement, glyph iteration)
  icon_font.rb                       # IconFont (Font subclass, symbol→codepoint registry)
  icon_font/
    lucide_glyphs.rb                  #   Generated glyph map (rake icons:generate)
  image.rb                           # Image (Vips wrapper, load/resize/crop/blit)

ext/chroma_wave/
  freetype.c                          # FreeType C bindings: load_face, render_glyph,
  |                                   #   measure_width, line_height, ascent, descent
  freetype.h                          # FT_Library lifecycle, FT_Face struct wrapper
```

For the updated C footprint including these additions, see Section 6.

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
at runtime with a clear message. This ensures the gem is usable for development, testing, and
CI without hardware.

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
- Add a configurable timeout with an interruptible loop:
  ```c
  int epd_read_busy(const epd_model_config_t *cfg, uint32_t timeout_ms) {
      uint32_t elapsed = 0;
      while (DEV_Digital_Read(EPD_BUSY_PIN) == cfg->busy_active_level) {
          if (elapsed >= timeout_ms) return EPD_ERR_TIMEOUT;
          DEV_Delay_ms(10);
          elapsed += 10;
      }
      return EPD_OK;
  }
  ```
- Provide an unblocking function (`ubf`) for `rb_thread_call_without_gvl` that sets a
  cancellation flag, allowing clean interrupt of long refreshes

### 5.4 EPD_7in5_V2 Destructive Buffer Inversion

`EPD_7IN5_V2_Display()` modifies the caller's buffer in-place (bitwise NOT) before sending
over SPI. This is a bug in the vendor code (violates the implied const contract). Our display
layer must either:
- **(A)** Copy the buffer before passing to the driver, or
- **(B)** Have the Framebuffer support an "inverted" flag and apply inversion during
  `buffer_bytes` export rather than modifying the source

**(A) is simpler** and the copy cost is negligible (800x480/8 = 48KB, microseconds to copy).

### 5.5 EPD_5in65f Dual Busy Polarity

`EPD_5in65f` uses both busy-HIGH and busy-LOW waits in different lifecycle phases (power-on
waits for HIGH, post-refresh waits for LOW). The Tier 1 config struct has a single
`busy_active_level` field, which is insufficient.

**Resolution:** EPD_5in65f already requires a Tier 2 override for its power-on/off-per-refresh
cycle. The override owns its busy-wait logic entirely, calling polarity-specific helpers
internally. No change to the Tier 1 config struct is needed:

```c
static int epd_5in65f_custom_display(
    const epd_model_config_t *cfg, const uint8_t *buf, size_t len) {
    epd_5in65f_power_on();
    epd_wait_busy_high(cfg, 5000);     /* wait for HIGH (power ready) */
    send_buffer(buf, len);
    epd_wait_busy_low(cfg, 30000);     /* wait for LOW (refresh done) */
    epd_5in65f_power_off();
    return EPD_OK;
}
```

### 5.6 Error Handling Strategy

The vendor library has essentially no error handling — functions don't return error codes, SPI
failures are silent, and the only error path is `DEV_Module_Init()` returning 1. Our extension
defines a **categorized exception hierarchy**:

```ruby
# Hardware errors (runtime failures, things go wrong with the device)
ChromaWave::Error < StandardError              # base class for all gem errors
ChromaWave::DeviceError < ChromaWave::Error    # SPI/GPIO failures
ChromaWave::InitError < ChromaWave::DeviceError    # DEV_Module_Init failed
ChromaWave::BusyTimeoutError < ChromaWave::DeviceError  # ReadBusy exceeded timeout
ChromaWave::SPIError < ChromaWave::DeviceError     # SPI transfer failed

# API misuse (programmer errors, fail fast)
ChromaWave::FormatMismatchError < ArgumentError  # wrong PixelFormat for display
ChromaWave::ModelNotFoundError < ArgumentError   # unknown model symbol
```

**Design rationale:** Hardware errors inherit from `ChromaWave::Error` (a `StandardError`
subclass) so `rescue ChromaWave::DeviceError` catches all hardware problems. API misuse errors
inherit from `ArgumentError` / `TypeError` — these are programmer mistakes that should fail
fast and loud, and they integrate with Ruby's standard exception semantics.

**C-side error propagation:** C functions return `int` status codes (`EPD_OK`, `EPD_ERR_TIMEOUT`,
`EPD_ERR_SPI`). The Ruby method wrappers check return values and raise the appropriate exception.
`rb_set_errinfo(Qnil)` is called after handling to clear `$!`.

### 5.7 Thread Safety

The SPI bus is shared hardware with no concurrent access support. Our design provides
**Device-level mutual exclusion** via a Ruby `Mutex`:

```ruby
class Device
  def initialize
    @mutex = Mutex.new
  end

  def synchronize(&block) = @mutex.synchronize(&block)
end
```

All hardware operations (`Display#show`, `Display#clear`, `Display#init`) synchronize through
the Device's mutex. `Framebuffer#set_pixel` and other pure-memory operations are **not locked**
— they have no hardware interaction and contention is the caller's responsibility.

The GVL release (Section 5.3) composes correctly with this: the mutex is acquired before
entering C, the GVL is released inside C for the busy-wait, and the mutex is released after
the C call returns. Other Ruby threads can run during the busy-wait but cannot start a
concurrent hardware operation.

---

## 6. Expected C Footprint

| Component           | Vendor Lines | After Refactor | Notes                           |
|---------------------|-------------|----------------|---------------------------------|
| DEV_Config + backends| ~1,200     | ~1,200         | Used as-is                      |
| EPD_*.c drivers     | ~25,000     | ~8,000         | Data tables + ~20 custom files  |
| GUI_Paint + BMPfile | ~1,200      | ~100           | Pixel packing only              |
| Fonts               | ~15,000     | 0              | Not vendored                    |
| FreeType bindings   | 0           | ~200           | New: glyph rasterization bridge |
| **Total**           | **~42,400** | **~9,500**     | **22% of original**             |

The refactored C footprint is roughly **22% of the original**, with the rest replaced by
Ruby code or eliminated as duplication.

---

## 7. Implementation Strategy Summary

1. **Extract pixel-packing core** from GUI_Paint.c (~100 lines) into `framebuffer.c`.
   Parameterize with a `Framebuffer*` struct. Do **not** fork the full 850-line file.
2. **Factor I/O primitives** (`Reset`, `SendCommand`, `SendData`, `ReadBusy`) into shared
   Device-level functions parameterized by model config. Eliminate ~1,400 lines of duplication.
3. **Build a two-tier driver registry** (`driver_registry.c`): static config data for simple
   models, optional code overrides for complex ones (~20 models).
4. **Model `PixelFormat` as a single value object** shared by Framebuffer and Display.
   Eliminate redundant scale/color_type/bpp representations.
5. **Model `Color` as an RGBA value type** with named constants (`Color::BLACK`, etc.),
   per-pixel alpha compositing (Porter-Duff source-over), and palette symbol bridging.
6. **Define the `Surface` protocol** as a Ruby module with `set_pixel`, `get_pixel`, `clear`,
   `width`, `height`, and mixin drawing primitives (see step 8).
7. **Implement `Canvas`** as a pure-Ruby RGBA pixel buffer that includes `Surface`. Canvas
   stores colors in a rich intermediate format, independent of any Display or PixelFormat.
8. **Implement drawing primitives** as `Surface` mixin methods: line, polyline, rect,
   rounded_rect, circle, ellipse, arc, polygon, flood_fill. All with `stroke_width:` and
   `fill:` support.
9. **Implement `Layer`** as a clipped, offset sub-region of any Surface. Enables widget-based
   UI composition where each component draws in its own local coordinate space.
10. **Implement `Renderer`** to bridge Canvas → Framebuffer. Owns palette mapping, dithering
    strategy selection (Floyd-Steinberg, ordered, threshold), and dual-buffer channel
    splitting. The only place quantization occurs.
11. **Compose display capabilities via Ruby modules** (`PartialRefresh`, `FastRefresh`,
    `GrayscaleMode`, `DualBuffer`). `DualBuffer` is hardware-only (SPI send); channel
    splitting is delegated to the Renderer.
12. **Link FreeType in the C extension** (`freetype.c`). Expose glyph rasterization and
    metrics as private C methods on `ChromaWave::Font`. Ruby-side `Font` class handles font
    discovery, measurement, and `draw_text` layout (alignment, word wrapping).
13. **Implement `IconFont`** as a `Font` subclass with symbol → codepoint registry. Bundle
    Lucide (~120KB TTF, ISC license) in `data/fonts/`. Add `rake icons:generate` task to
    produce the glyph map from Lucide's metadata.
14. **Implement `Image`** as a ruby-vips wrapper. Handles loading any image format,
    resize/crop, RGBA conversion, and blitting onto Canvas.
15. **Compile all drivers unconditionally** -- total binary size is negligible.
16. **Detect platform in `extconf.rb`**, set `-D` flags for the appropriate GPIO/SPI backend.
    Also detect and link `libfreetype`.
17. **Add a mock backend** for development and CI testing without hardware.
18. **Release the GVL** during display refresh operations via `rb_thread_call_without_gvl()`.
19. **Add timeout to busy-wait** with an interruptible loop and configurable max duration.
