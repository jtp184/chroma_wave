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
| Canvas Operations          | Ruby  | Composing images declaratively in layers      |
| Drawing primitives         | Ruby  | Bresenham algorithms, calls C `set_pixel`     |
| Text rendering             | Ruby  | FreeType or pre-rendered, not bitmap fonts    |
| Image loading/conversion   | Ruby  | MiniMagick, quantize to display palette       |
| Color space conversion     | Ruby  | RGB->display palette mapping, dithering       |
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
format, not as a special pixel format. The Display's `DualBuffer` capability module knows it
needs two buffers and provides a layered Canvas for convenience (see Section 3.3).

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
  framebuffer.rb                      # Ruby wrapper for C-backed Framebuffer
  canvas.rb                           # Drawing primitives, color routing, layer management
  transform.rb                        # Rotation, mirroring, coordinate mapping
  device.rb                           # Hardware lifecycle, connection management, Mutex
  display.rb                          # Display factory (symbol registry), base methods
  registry.rb                         # Model registry: builds subclasses from C config data
  capabilities/                       # Composable capability modules (wrap private C methods)
    partial_refresh.rb                #   display_partial, display_base
    fast_refresh.rb                   #   init_fast, display_fast
    grayscale_mode.rb                 #   init_grayscale, display_grayscale
    dual_buffer.rb                    #   show(black_fb, red_fb), layered Canvas support
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
      def show(black_framebuffer, red_framebuffer)
        [black_framebuffer, red_framebuffer].each { validate_format!(_1) }
        _epd_display_dual(black_framebuffer, red_framebuffer)
      end
    end
  end
end
```

#### Dual-Buffer Canvas UX

For dual-color displays (B+R, B+Y), the `DualBuffer` capability provides a **layered Canvas**
as the default workflow, with an escape hatch to raw framebuffers for power users:

```ruby
# Simple path: single Canvas with color routing
canvas = display.canvas                              # auto-creates dual framebuffers
canvas.draw_rect(10, 10, 100, 50, color: :black)
canvas.draw_circle(60, 60, 30, color: :red)
display.show(canvas)                                 # extracts both layers

# Power-user escape hatch: direct layer access
canvas.layers[:black]                                # => Framebuffer
canvas.layers[:red]                                  # => Framebuffer

# Or bypass Canvas entirely with raw framebuffers
display.show(custom_black_fb, custom_red_fb)
```

The Canvas detects whether the underlying display uses `DualBuffer` and routes colors to the
appropriate layer. For single-buffer displays, `canvas.layers` returns `{ default: fb }`.

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
the timeout/interruptibility improvement (see Section 4.3) in one place.

### 3.7 Framebuffer: Pixel Storage Without Drawing

The vendor's `PAINT` struct conflates pixel storage, coordinate transforms, and drawing state
into a single global. In our design, these are three separate concerns:

```
Framebuffer (C-backed, TypedData)
  +-- Owns: raw byte buffer (xmalloc'd)
  +-- Knows: width, height, PixelFormat
  +-- Methods: set_pixel, get_pixel, clear, buffer_bytes, buffer_size
  +-- No drawing, no transforms, no global state

Canvas (Ruby)
  +-- Wraps: a Framebuffer + a Transform
  +-- Methods: draw_line, draw_rect, draw_circle, draw_text, ...
  +-- Delegates pixel writes to Framebuffer#set_pixel after transform

Transform (Ruby value object)
  +-- Knows: rotation (0/90/180/270), mirror mode, logical dimensions
  +-- Method: apply(x, y) -> [physical_x, physical_y]
```

The Framebuffer's C implementation extracts only the pixel-packing logic from `GUI_Paint.c`
(~100 lines: the `Scale`-dependent bit-twiddling in `Paint_SetPixel` and `Paint_Clear`).
No forking of GUI_Paint.c is needed. The drawing primitives are reimplemented in Ruby where
they can be tested, extended, and composed with Ruby's image processing ecosystem.

> **Padding invariant:** For non-byte-aligned widths (e.g., 122px mono = 15.25 bytes/row),
> the trailing bits in the last byte of each row are **always zero**. `set_pixel` never writes
> to padding positions, and `clear` zeros the entire buffer including padding. This invariant
> must be preserved by `framebuffer.c` to prevent display artifacts from garbage padding bits.

---

## 4. Integration Challenges

### 4.1 Platform Detection in `extconf.rb`

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

### 4.2 Buffer Ownership and GC Integration

Framebuffers own pixel data allocated via `xmalloc`/`xfree` (Ruby's tracked allocator).
Wrapped with `TypedData_Wrap_Struct` with:
- `dfree`: calls `xfree` on the pixel buffer
- `dsize`: reports `buffer_size` bytes to Ruby's GC for memory pressure tracking
- `dmark`: not needed (no `VALUE`s stored in the C struct)
- `flags`: `RUBY_TYPED_FREE_IMMEDIATELY` (no GVL needed for `xfree`)

### 4.3 Busy-Wait Blocking and GVL Release

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

### 4.4 EPD_7in5_V2 Destructive Buffer Inversion

`EPD_7IN5_V2_Display()` modifies the caller's buffer in-place (bitwise NOT) before sending
over SPI. This is a bug in the vendor code (violates the implied const contract). Our display
layer must either:
- **(A)** Copy the buffer before passing to the driver, or
- **(B)** Have the Framebuffer support an "inverted" flag and apply inversion during
  `buffer_bytes` export rather than modifying the source

**(A) is simpler** and the copy cost is negligible (800x480/8 = 48KB, microseconds to copy).

### 4.5 EPD_5in65f Dual Busy Polarity

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

### 4.6 Error Handling Strategy

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

### 4.7 Thread Safety

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

The GVL release (Section 4.3) composes correctly with this: the mutex is acquired before
entering C, the GVL is released inside C for the busy-wait, and the mutex is released after
the C call returns. Other Ruby threads can run during the busy-wait but cannot start a
concurrent hardware operation.

---

## 5. Expected C Footprint

| Component           | Vendor Lines | After Refactor | Notes                           |
|---------------------|-------------|----------------|---------------------------------|
| DEV_Config + backends| ~1,200     | ~1,200         | Used as-is                      |
| EPD_*.c drivers     | ~25,000     | ~8,000         | Data tables + ~20 custom files  |
| GUI_Paint + BMPfile | ~1,200      | ~100           | Pixel packing only              |
| Fonts               | ~15,000     | 0              | Not vendored                    |
| **Total**           | **~42,400** | **~9,300**     | **22% of original**             |

The refactored C footprint is roughly **22% of the original**, with the rest replaced by
Ruby code or eliminated as duplication.

---

## 6. Implementation Strategy Summary

1. **Extract pixel-packing core** from GUI_Paint.c (~100 lines) into `framebuffer.c`.
   Parameterize with a `Framebuffer*` struct. Do **not** fork the full 850-line file.
2. **Factor I/O primitives** (`Reset`, `SendCommand`, `SendData`, `ReadBusy`) into shared
   Device-level functions parameterized by model config. Eliminate ~1,400 lines of duplication.
3. **Build a two-tier driver registry** (`driver_registry.c`): static config data for simple
   models, optional code overrides for complex ones (~20 models).
4. **Model `PixelFormat` as a single value object** shared by Framebuffer and Display.
   Eliminate redundant scale/color_type/bpp representations.
5. **Implement drawing primitives in Ruby** (`Canvas`). Delegate pixel writes to C-backed
   `Framebuffer#set_pixel`. Keep text rendering, image loading, and color conversion in Ruby.
6. **Compose display capabilities via Ruby modules** (`PartialRefresh`, `FastRefresh`,
   `GrayscaleMode`, `DualBuffer`). Each model includes only what it supports.
7. **Compile all drivers unconditionally** -- total binary size is negligible.
8. **Detect platform in `extconf.rb`**, set `-D` flags for the appropriate GPIO/SPI backend.
9. **Add a mock backend** for development and CI testing without hardware.
10. **Release the GVL** during display refresh operations via `rb_thread_call_without_gvl()`.
11. **Add timeout to busy-wait** with an interruptible loop and configurable max duration.
12. **Handle image data in Ruby** -- use ChunkyPNG or Vips for image loading/manipulation,
    quantize to display palette, pass raw pixel buffers to C for display.
13. **Replace the font system** with FreeType or Ruby-side text rendering.
