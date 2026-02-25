# ChromaWave Content Pipeline

The content that flows through the drawing architecture: colors, shapes, text, and images.
This document specifies the Ruby-side content layer — everything users interact with when
composing visuals for the display.

For the structural layers these content types flow through (Surface, Canvas, Renderer,
Framebuffer), see [EXTENSION_STRATEGY.md](EXTENSION_STRATEGY.md). For full code contracts
of all classes, see [API_REFERENCE.md](API_REFERENCE.md).

---

## 1. Color Model (RGBA)

Canvas compositing requires a richer color representation than the display's final palette.
Colors are modeled as **frozen RGBA value objects** using `Data.define` (Ruby 3.2+), with a
bridge to **palette entries** — the lowercase symbols (`:black`, `:red`, `:dark_gray`) that
Palettes, Framebuffers, and the Renderer use to identify colors in the display's native
format:

```ruby
module ChromaWave
  Color = Data.define(:r, :g, :b, :a) do
    def initialize(r:, g:, b:, a: 255)
      super(r:, g:, b:, a:)
    end

    def opaque?  = a == 255
    def transparent? = a == 0

    # Pack into 4-byte binary string (for Canvas packed buffer storage).
    def to_rgba_bytes = [r, g, b, a].pack("C4")

    # Unpack from 4-byte binary string (lazy materialization from Canvas).
    def self.from_rgba_bytes(bytes)
      r, g, b, a = bytes.unpack("C4")
      new(r:, g:, b:, a:)
    end

    # Alpha compositing: source over onto opaque background.
    # Always produces an opaque result (a=255). This is intentionally
    # simplified from full Porter-Duff — background is assumed opaque.
    # Alpha is only meaningful in the Canvas layer and is flattened by
    # the Renderer during quantization.
    #
    # NOTE: If background has a < 255, the background's alpha is silently
    # ignored (the result is still opaque). Full Porter-Duff compositing
    # with output alpha (for stacked semi-transparency) is deferred as a
    # future enhancement if real-world use cases require it.
    def over(background)
      return self if opaque?
      return background if transparent?
      alpha = a / 255.0
      Color.new(
        r: (r * alpha + background.r * (1 - alpha)).round,
        g: (g * alpha + background.g * (1 - alpha)).round,
        b: (b * alpha + background.b * (1 - alpha)).round
      )
    end

    # Reverse lookup: palette entry → Color. Used by Palette#nearest_color.
    # Keys are always lowercase symbols (:black, :red, etc.).
    NAME_MAP = {}
    def self.from_name(name) = NAME_MAP.fetch(name)

    # Register a named color. `name` is always a lowercase symbol (:black,
    # :dark_gray, etc.). This creates an uppercase constant (Color::BLACK)
    # and a NAME_MAP entry keyed by the original symbol.
    def self.register(name, color)
      const_set(name.upcase, color)
      NAME_MAP[name] = color
      color
    end

    # Named color constants — RGB values that map to common display palettes.
    # Registration names are lowercase symbols; constants are uppercase.
    register(:black,      new(r: 0,   g: 0,   b: 0))
    register(:white,      new(r: 255, g: 255, b: 255))
    register(:red,        new(r: 255, g: 0,   b: 0))
    register(:yellow,     new(r: 255, g: 255, b: 0))
    register(:green,      new(r: 0,   g: 128, b: 0))
    register(:blue,       new(r: 0,   g: 0,   b: 255))
    register(:orange,     new(r: 255, g: 165, b: 0))
    register(:dark_gray,  new(r: 85,  g: 85,  b: 85))
    register(:light_gray, new(r: 170, g: 170, b: 170))
    TRANSPARENT = new(r: 0, g: 0, b: 0, a: 0)
  end
end
```

### How RGBA Flows Through the Pipeline

| Stage              | Color representation | Alpha behavior                          |
|--------------------|----------------------|-----------------------------------------|
| `set_pixel`        | `Color` → 4 packed bytes | Direct replacement (no compositing) |
| `get_pixel`        | 4 packed bytes → `Color` | Lazy materialization on demand      |
| `blit` (C accel)   | Packed bytes directly | Per-pixel alpha composite, no Color objects |
| `blit` (Ruby fallback) | `Color` (RGBA) | Per-pixel alpha compositing (source over)|
| `load_rgba_bytes`  | Raw RGBA bytes → buffer | Bulk memcpy, no Color objects       |
| `render_glyph`     | `Color` (RGBA)       | Per-pixel alpha compositing (source over)|
| Renderer quantize  | `rgba_bytes` → palette | Iterates packed bytes directly, no Color |
| Framebuffer        | Palette name (symbol)| No alpha — device format is opaque      |

Alpha exists only in the Canvas layer. The Renderer flattens it during quantization
(compositing against a configurable background, typically white for e-paper). The
Framebuffer and Display never see alpha — they work with opaque palette indices.

> **Minimal Color object creation:** In the common pipeline (load image → compose → render
> → display), Color objects are created only for drawing primitive calls (`set_pixel`,
> `draw_line`, etc.) and glyph rendering. Bulk operations (image loading, blit, clear,
> quantization) operate directly on packed bytes, bypassing Color entirely. A typical
> dashboard render creates dozens of Color objects (one per drawing call), not hundreds of
> thousands (one per pixel).

> **Color vs palette entry:** The two color representations serve different layers.
> `Color` objects (`Color::RED`, `Color.new(r: 255, g: 0, b: 0)`) are RGBA values used on
> Canvas for compositing. **Palette entries** (`:red`, `:black`, `:dark_gray`) are the
> lowercase symbols used on Framebuffer for direct pixel access. The `Renderer` bridges
> the two: it maps each Canvas `Color` to the nearest palette entry during quantization.
> Users drawing on a Canvas use `Color` objects; users drawing directly on a Framebuffer
> use palette entries. The `Surface` protocol is agnostic — `set_pixel` accepts whatever
> the concrete surface expects.

---

## 2. Shape Primitives

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

---

## 3. Text Rendering

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

### 3.1 Font Loading

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
      # bitmap is a packed binary String (1 byte per pixel, alpha values 0-255).
      # Row-major layout: width * height bytes. Matches Canvas's packed-buffer
      # philosophy and avoids allocating nested Arrays per glyph.
    end
  end

  TextMetrics = Data.define(:width, :height, :ascent, :descent)
end
```

### 3.2 Drawing Text on a Surface

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
      bitmap = glyph[:bitmap]
      w, h = glyph[:width], glyph[:height]
      h.times do |gy|
        w.times do |gx|
          alpha = bitmap.getbyte(gy * w + gx)
          next if alpha == 0
          set_pixel(x + gx, y + gy, Color.new(r: color.r, g: color.g, b: color.b, a: alpha))
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

### 3.3 Font Discovery

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

---

## 4. Icon Support (Bundled Lucide + IconFont)

Icons are a special case of text rendering — icon fonts are TTF files where glyphs are
symbols instead of letters. Since we already have FreeType, the infrastructure is free. The
gap is **convenience**: mapping human-readable names to Unicode codepoints.

### 4.1 Bundled Font

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

### 4.2 IconFont Class

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

### 4.3 Usage

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

---

## 5. Image Loading (ruby-vips)

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

    # Load into a new Canvas. Uses Canvas#load_rgba_bytes for bulk transfer —
    # the packed RGBA bytes from vips go directly into Canvas's packed String
    # buffer without materializing any Color objects.
    def to_canvas
      Canvas.new(width:, height:).tap do |canvas|
        canvas.load_rgba_bytes(@vips_image.write_to_memory)
      end
    end

    # Blit directly onto an existing Canvas at (x, y). Uses Canvas#load_rgba_bytes
    # for bulk transfer — C-accelerated memcpy with bounds clipping.
    def draw_onto(canvas, x:, y:)
      canvas.load_rgba_bytes(@vips_image.write_to_memory,
                             width:, height:, x:, y:)
    end

    private

    def ensure_rgba(vips_image)
      # Normalize non-RGB color spaces (CMYK, LAB, etc.) to sRGB first.
      # Without this, a 4-band CMYK image would be misinterpreted as RGBA.
      img = if vips_image.interpretation != :srgb &&
                vips_image.interpretation != :b_w
               vips_image.colourspace(:srgb)
             else
               vips_image
             end

      case img.bands
      when 1 then img.colourspace(:srgb)                        # grayscale → RGB
                     .bandjoin(img.new_from_image(255))         # + full alpha
      when 2                                                     # grayscale + alpha
        gray = img[0].colourspace(:srgb)                        # gray → 3-band RGB
        gray.bandjoin(img[1])                                   # + original alpha
      when 3 then img.bandjoin(img.new_from_image(255))         # RGB → RGBA
      when 4 then img                                            # already RGBA
      end.cast(:uchar)
    end
  end
end
```

### 5.1 End-to-End Image Workflow

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

> **Performance note:** `to_canvas` and `draw_onto` use `Canvas#load_rgba_bytes`, which
> bulk-copies vips' packed RGBA output directly into Canvas's packed String buffer. With the
> C accelerator, this is a row-by-row `memcpy` (~5ms for 800x480). Without the C accelerator,
> the Ruby fallback does byte-slice copying (~50ms). Neither path creates any Color objects.
> This is a ~160x improvement over the naive per-pixel `Color.new` approach.

---

## 6. Content-Related File Inventory

These files are added by the content pipeline (see
[EXTENSION_STRATEGY.md, Section 3.2](EXTENSION_STRATEGY.md#32-directory-structure) for
the full project tree):

```
data/
  fonts/
    lucide.ttf                        # Bundled icon font (~120KB, ISC license)
    LICENSE-lucide.txt                # Lucide license text

lib/chroma_wave/
  color.rb                            # Color (RGBA Data.define, named constants, compositing)
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
  canvas.c                            # Canvas C accelerators: clear, blit_alpha,
  |                                   #   load_rgba (~80 lines, optional)
  freetype.c                          # FreeType C bindings: load_face, render_glyph,
  |                                   #   measure_width, line_height, ascent, descent
  freetype.h                          # FT_Library lifecycle, FT_Face struct wrapper
```
