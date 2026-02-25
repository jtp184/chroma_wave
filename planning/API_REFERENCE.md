# ChromaWave API Reference

Target API contracts for the ChromaWave C extension and Ruby library. These are
**implementation targets** — the code examples show the intended public interfaces
and key internal patterns.

For architectural rationale and design decisions, see
[EXTENSION_STRATEGY.md](EXTENSION_STRATEGY.md). For content pipeline details (color,
drawing, text, icons, images), see [CONTENT_PIPELINE.md](CONTENT_PIPELINE.md).

---

## 1. Core Value Types

### 1.1 Palette

```ruby
module ChromaWave
  class Palette
    include Enumerable

    attr_reader :entries

    def self.[](*entries) = new(entries)

    def initialize(entries)
      entries.each do |name|
        unless Color::NAME_MAP.key?(name)
          raise ArgumentError, "unknown palette color #{name.inspect}; " \
                "registered colors: #{Color::NAME_MAP.keys.join(', ')}"
        end
      end
      @entries = entries.freeze
      @index = entries.each_with_index.to_h.freeze
      # Pre-resolve palette entries → RGBA for distance calculations.
      # Avoids repeated Color.from_name lookups during quantization.
      @rgba_by_entry = entries.map { |name| [name, Color.from_name(name)] }.to_h.freeze
      # Memoization cache: packed RGBA integer → nearest palette entry.
      # Dashboard UIs reuse the same few colors across thousands of pixels;
      # this cache turns O(palette_size) per pixel into O(1) for repeats.
      # Key is a packed 32-bit integer (not a String) to avoid allocation per lookup.
      @nearest_cache = {}
    end

    def each(&) = entries.each(&)
    def size = entries.size

    def include?(color) = @index.key?(color)
    def index_of(color) = @index.fetch(color)
    def color_at(index) = entries.fetch(index)

    # Map an RGBA Color to the nearest palette entry.
    # Used by the Renderer during quantization. Results are memoized
    # by a packed integer key — zero allocation per cache hit.
    def nearest_color(rgba)
      key = (rgba.r << 24) | (rgba.g << 16) | (rgba.b << 8) | rgba.a
      @nearest_cache[key] ||=
        entries.min_by { |name| color_distance(rgba, @rgba_by_entry[name]) }
    end

    private

    # Redmean color distance — a cheap perceptual approximation that weights
    # RGB channels based on human vision sensitivity. Dramatically better than
    # Euclidean RGB for palette mapping (e.g., dark blues correctly map to blue
    # instead of black). See https://www.compuphase.com/cmetric.htm
    def color_distance(a, b)
      rmean = (a.r + b.r) / 2.0
      dr = a.r - b.r
      dg = a.g - b.g
      db = a.b - b.b
      (2 + rmean / 256.0) * dr**2 + 4 * dg**2 + (2 + (255 - rmean) / 256.0) * db**2
    end
  end
end
```

### 1.2 PixelFormat

```ruby
module ChromaWave
  PixelFormat = Data.define(:name, :bits_per_pixel, :palette) do
    def pixels_per_byte = 8 / bits_per_pixel

    MONO   = new(name: :mono,   bits_per_pixel: 1, palette: Palette[:black, :white])
    GRAY4  = new(name: :gray4,  bits_per_pixel: 2,
                 palette: Palette[:black, :dark_gray, :light_gray, :white])
    COLOR4 = new(name: :color4, bits_per_pixel: 4,
                 palette: Palette[:black, :white, :yellow, :red])
    COLOR7 = new(name: :color7, bits_per_pixel: 4,
                 palette: Palette[:black, :white, :green, :blue, :red, :yellow, :orange])

    def buffer_size(width, height)
      bytes_per_row = (width + pixels_per_byte - 1) / pixels_per_byte
      bytes_per_row * height
    end

    def valid_color?(color) = palette.include?(color)
  end
end
```

> **Palette ordering:** The vendor library names grayscale values in reverse
> (`GRAY1` = blackest, `GRAY4` = white). Our `GRAY4` format intentionally reorders to
> `[:black, :dark_gray, :light_gray, :white]` (dark-to-light). The numeric mapping to
> vendor values happens at the C boundary.

> **Scale:** The vendor's `Scale` integer (2, 4, 6, 7) is **not exposed** in the Ruby
> `PixelFormat` API — it is an internal detail used only at the C boundary where
> `framebuffer.c` maps `pixel_format` enum values to packing logic.

---

## 2. Surface Protocol & Implementations

### 2.1 Surface Module

```ruby
module ChromaWave
  module Surface
    # Required by includers:
    #   #width, #height     → Integer
    #   #set_pixel(x, y, color = Color::BLACK)
    #   #get_pixel(x, y) → color

    def in_bounds?(x, y) = x >= 0 && x < width && y >= 0 && y < height

    # Default clear: fill the entire surface via set_pixel.
    # Includers (Canvas, Framebuffer) override with optimized versions.
    # Layer inherits this and correctly fills only its own bounds.
    def clear(color = Color::WHITE)
      height.times { |y| width.times { |x| set_pixel(x, y, color) } }
    end

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

> **Bounds contract:** `set_pixel` silently drops out-of-bounds writes (clipping behavior).
> `get_pixel` returns `nil` for out-of-bounds coordinates — callers that read pixels near
> edges must check for `nil` or use `in_bounds?` first. Drawing primitives (which only call
> `set_pixel`) are naturally safe. Code that reads pixels (e.g., `blit` compositing) must
> guard against `nil` returns from the destination surface. This asymmetry is intentional:
> silent clipping on writes avoids bounds-check overhead in the hot drawing path, while
> explicit `nil` on reads prevents silent use of garbage data.

For the full set of drawing primitives (polyline, rounded_rect, ellipse, arc, polygon,
flood_fill), see [CONTENT_PIPELINE.md, Section 2](CONTENT_PIPELINE.md#2-shape-primitives).

### 2.2 Canvas

```ruby
module ChromaWave
  class Canvas
    include Surface

    attr_reader :width, :height

    BYTES_PER_PIXEL = 4  # RGBA

    def initialize(width:, height:, background: Color::WHITE)
      @width = width
      @height = height
      # Packed RGBA String — one contiguous allocation, single GC object.
      # C accelerators operate directly on this buffer via RSTRING_PTR.
      @buffer = (background.to_rgba_bytes * (width * height)).b
    end

    def set_pixel(x, y, color = Color::BLACK)
      return unless in_bounds?(x, y)
      @buffer[(y * width + x) * BYTES_PER_PIXEL, BYTES_PER_PIXEL] =
        color.to_rgba_bytes
    end

    def get_pixel(x, y)
      return unless in_bounds?(x, y)
      Color.from_rgba_bytes(
        @buffer[(y * width + x) * BYTES_PER_PIXEL, BYTES_PER_PIXEL]
      )
    end

    # C-accelerated: memset-equivalent fill of packed RGBA bytes.
    # Falls back to Ruby loop if C extension unavailable.
    def clear(color = Color::WHITE)
      _canvas_clear(color.r, color.g, color.b, color.a)
    rescue NoMethodError
      # Build a full-size RGBA string from the 4-byte color pattern, then
      # replace the buffer contents. This allocates one transient String
      # (~1.5MB for 800×480) but avoids 384K individual String#[]= calls.
      # The transient is eligible for GC immediately after replace returns.
      pixel = color.to_rgba_bytes
      @buffer.replace(pixel * (width * height))
    end

    # C-accelerated: per-pixel alpha composite of source onto self.
    # Falls back to Ruby loop if C extension unavailable.
    def blit(source, x:, y:)
      if source.is_a?(Canvas) && respond_to?(:_canvas_blit_alpha, true)
        _canvas_blit_alpha(source, x, y)
      else
        blit_ruby(source, x:, y:)
      end
    end

    # Bulk-load packed RGBA bytes (from Image#write_to_memory or similar).
    # C-accelerated: single memcpy into the buffer. Falls back to Ruby.
    def load_rgba_bytes(bytes, width: @width, height: @height, x: 0, y: 0)
      if respond_to?(:_canvas_load_rgba, true)
        _canvas_load_rgba(bytes, width, height, x, y)
      else
        load_rgba_bytes_ruby(bytes, width:, height:, x:, y:)
      end
    end

    # Raw buffer access — used by Renderer for direct byte iteration
    # without per-pixel Color materialization.
    def rgba_bytes = @buffer

    # Create a clipped sub-region for independent drawing
    def layer(x:, y:, width:, height:, &block)
      Layer.new(self, x:, y:, width:, height:).tap { |l| yield l if block }
    end

    private

    def blit_ruby(source, x:, y:)
      source.height.times do |sy|
        source.width.times do |sx|
          src_color = source.get_pixel(sx, sy)
          next if src_color.transparent?
          dest_x, dest_y = x + sx, y + sy
          next unless in_bounds?(dest_x, dest_y)
          bg = get_pixel(dest_x, dest_y)
          set_pixel(dest_x, dest_y, src_color.over(bg))
        end
      end
    end

    def load_rgba_bytes_ruby(bytes, width:, height:, x:, y:)
      height.times do |row|
        width.times do |col|
          src_off = (row * width + col) * BYTES_PER_PIXEL
          dst_off = ((y + row) * @width + (x + col)) * BYTES_PER_PIXEL
          next unless in_bounds?(x + col, y + row)
          @buffer[dst_off, BYTES_PER_PIXEL] = bytes[src_off, BYTES_PER_PIXEL]
        end
      end
    end
  end
end
```

### 2.3 Layer

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

> **Layer bounds are not validated against the parent.** `Layer.new` does not check that the
> region falls within the parent's dimensions. A Layer extending past the parent edge will
> delegate out-of-bounds coordinates to the parent's `set_pixel`/`get_pixel`, which clip
> silently (writes) or return `nil` (reads). This is by design — it avoids validation
> overhead and allows intentional "overflow" patterns where a Layer is used as a logical
> coordinate space even if partially off-screen.

### 2.4 Framebuffer (C-backed)

```
Framebuffer (C-backed, TypedData)
  +-- Includes: Surface protocol
  +-- Owns: raw byte buffer (xmalloc'd)
  +-- Knows: width, height, PixelFormat
  +-- Methods: set_pixel, get_pixel, clear, buffer_bytes, buffer_size
  +-- set_pixel/get_pixel: format-aware bit-packing (C, ~100 lines from GUI_Paint.c)
  +-- No drawing state, no transforms, no global state
```

> **`set_pixel` color contract:** Framebuffer's `set_pixel` accepts a **palette entry**
> (`:black`, `:red`, etc.) — the same lowercase symbols used in `Palette` entries. The C
> implementation maps the palette entry to its integer index via `Palette#index_of`, then
> bit-packs that index into the buffer at the correct position. `get_pixel` does the reverse:
> extracts the integer index and returns the palette entry via `Palette#color_at`.
>
> ```ruby
> fb.set_pixel(10, 20, :black)     # palette entry → index → bit-packed
> fb.get_pixel(10, 20)             # → :black
> ```
>
> The `Surface` mixin's drawing primitives accept a `color:` keyword. On a Canvas, this is a
> `Color` (RGBA). On a Framebuffer, this is a palette entry. The `Surface` protocol doesn't
> constrain the type — it just passes whatever `color:` value through to `set_pixel`. This
> duck-typing means the same `draw_rect` call works on both, with the color type matching the
> surface's storage format. The `Renderer` is the bridge: it maps `Color` → palette entry
> during quantization, writing palette entries into the Framebuffer.

> **Padding invariant:** For non-byte-aligned widths, the trailing bits in the last byte of
> each row are **always zero**. This applies to all sub-byte formats: MONO (1 bpp, e.g.,
> 122px = 15.25 bytes/row → 16 bytes with 6 padding bits) and GRAY4 (2 bpp, e.g., 122px =
> 30.5 bytes/row → 31 bytes with 4 padding bits). `set_pixel` never writes to padding
> positions, and `clear` zeros the entire buffer including padding. This invariant must be
> preserved by `framebuffer.c` to prevent display artifacts from garbage padding bits.

---

## 3. Display & Capabilities

### 3.1 Display Base Class

```ruby
module ChromaWave
  class Display
    def show(canvas_or_fb)
      ensure_initialized!
      fb = case canvas_or_fb
           when Canvas     then renderer.render(canvas_or_fb)
           when Framebuffer then canvas_or_fb
           else raise TypeError, "expected Canvas or Framebuffer, got #{canvas_or_fb.class}"
           end
      validate_format!(fb)
      device.synchronize { _epd_display(fb) }
    end

    def clear(color: :white)
      ensure_initialized!
      device.synchronize { _epd_clear(color) }
    end

    def sleep
      device.synchronize { _epd_sleep }
      @initialized = false
    end

    def close
      sleep rescue nil
      device.close
    end

    # Block-style lifecycle: auto-closes when the block exits.
    def self.open(model:, &block)
      display = new(model:)
      return display unless block
      begin
        yield display
      ensure
        display.close
      end
    end

    private

    # Lazy initialization: the hardware init sequence runs on first use,
    # not at construction time. This allows Display objects to be created
    # without hardware present (useful for testing, configuration, and
    # querying model capabilities). The MOCK backend's init is a no-op.
    def ensure_initialized!
      return if @initialized

      device.synchronize { _epd_init }
      @initialized = true
    end
  end
end
```

### 3.2 C Bridge Methods

All C-backed display operations are defined as **private methods on the Display base class**
in `Init_chroma_wave`. The Ruby capability modules provide the public API with validation:

```c
/* In chroma_wave.c Init_chroma_wave(): */
rb_define_private_method(rb_cDisplay, "_epd_init",
                         rb_epd_init, 0);
rb_define_private_method(rb_cDisplay, "_epd_clear",
                         rb_epd_clear, 1);
rb_define_private_method(rb_cDisplay, "_epd_sleep",
                         rb_epd_sleep, 0);
rb_define_private_method(rb_cDisplay, "_epd_display_base",
                         rb_epd_display_base, 1);
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

/* Canvas C accelerators (canvas.c): operate on Canvas's String buffer */
rb_define_private_method(rb_cCanvas, "_canvas_clear",
                         rb_canvas_clear, 4);        /* r, g, b, a */
rb_define_private_method(rb_cCanvas, "_canvas_blit_alpha",
                         rb_canvas_blit_alpha, 3);   /* source, x, y */
rb_define_private_method(rb_cCanvas, "_canvas_load_rgba",
                         rb_canvas_load_rgba, 5);    /* bytes, w, h, x, y */
```

### 3.3 Capability Modules

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
      # Canvas → dual-FB splitting is handled by Renderer.

      # Common path: Canvas is auto-split into two mono FBs via Renderer.
      def show(canvas)
        black_fb, red_fb = renderer.render_dual(canvas)
        device.synchronize { _epd_display_dual(black_fb, red_fb) }
      end

      # Power-user path: provide two pre-rendered mono Framebuffers directly.
      def show_raw(black_fb, red_fb)
        [black_fb, red_fb].each { validate_format!(_1) }
        device.synchronize { _epd_display_dual(black_fb, red_fb) }
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

### 3.4 Model Registry

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

---

## 4. Renderer

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
      # Iterate canvas.rgba_bytes directly (4-byte stride per pixel).
      # For each pixel, materialize a Color only for the Palette#nearest_color
      # call (memoized — repeated colors hit the cache). Map the result to a
      # palette entry, apply dithering to distribute quantization error, and
      # write the palette entry to fb.set_pixel.
    end

    def split_channels(canvas, black_fb, red_fb)
      # Route :black/:dark pixels → black_fb
      # Route :red/:yellow pixels → red_fb
      # Everything else → black_fb (default layer)
    end
  end
end
```

---

## 5. Two-Tier Driver Registry (C)

### 5.1 Tier 1: Static Configuration

```c
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
```

### 5.2 Tier 2: Optional Code Overrides

```c
typedef struct {
    const epd_model_config_t *config;
    int  (*custom_init)(const epd_model_config_t *cfg, uint8_t mode);
    int  (*custom_display)(const epd_model_config_t *cfg, const uint8_t *buf, size_t len);
    void (*pre_display)(const epd_model_config_t *cfg);   /* e.g. 5in65f power-on */
    void (*post_display)(const epd_model_config_t *cfg);  /* e.g. 5in65f power-off */
} epd_driver_t;
```

### 5.3 Tier 2 Override Example (EPD_4in2 LUT selection)

```c
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

### 5.4 Shared Device I/O

```c
/* Shared I/O functions on Device — called by all drivers */
void epd_reset(const epd_model_config_t *cfg);
void epd_send_command(uint8_t cmd);
void epd_send_data(uint8_t data);
void epd_send_data_bulk(const uint8_t *data, size_t len);
int  epd_read_busy(const epd_model_config_t *cfg, uint32_t timeout_ms);
```

### 5.5 Busy-Wait with Timeout

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

### 5.6 EPD_5in65f Dual Busy Polarity Override

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

---

## 6. Error Hierarchy

```ruby
# Hardware errors (runtime failures, things go wrong with the device)
ChromaWave::Error < StandardError              # base class for all gem errors
ChromaWave::DeviceError < ChromaWave::Error    # SPI/GPIO failures
ChromaWave::InitError < ChromaWave::DeviceError    # DEV_Module_Init failed
ChromaWave::BusyTimeoutError < ChromaWave::DeviceError  # ReadBusy exceeded timeout
ChromaWave::SPIError < ChromaWave::DeviceError     # SPI transfer failed
ChromaWave::DependencyError < ChromaWave::Error  # optional dep missing (FreeType)

# API misuse (programmer errors, fail fast)
ChromaWave::FormatMismatchError < ArgumentError  # wrong PixelFormat for display
ChromaWave::ModelNotFoundError < ArgumentError   # unknown model symbol
```

---

## 7. Thread Safety

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

The GVL release composes correctly with this: the mutex is acquired before entering C, the GVL
is released inside C for the busy-wait, and the mutex is released after the C call returns.
Other Ruby threads can run during the busy-wait but cannot start a concurrent hardware
operation.

---

## 8. Transform Integration

```
Transform (Ruby value object)
  +-- Knows: rotation (0/90/180/270), mirror mode, logical dimensions
  +-- Method: apply(x, y) -> [physical_x, physical_y]
  +-- Composed with any Surface via TransformedSurface wrapper
```

> **Deferred design:** The concrete Transform API (wrapper class, composition semantics,
> integration with Renderer) will be designed during implementation. The key constraint is
> that Canvas always operates in logical (unrotated) coordinates — physical rotation is
> applied at the Renderer→Framebuffer boundary, not inside Canvas or Surface.

---

## 9. Usage Examples

### Dashboard Composition

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

### Display Workflows

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
display.show_raw(custom_black_fb, custom_red_fb)
```

### Model Discovery

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
