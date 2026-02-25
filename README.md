# ChromaWave

Ruby C bindings for Waveshare e-paper displays. Draw with a clean, idiomatic API. Render text, icons, and images. Drive 70+ display models from a single gem.

```ruby
display = ChromaWave::Display.open(model: :epd_2in13_v4) do |display|
  canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)

  canvas.draw_rect(10, 10, 100, 50, color: Color::BLACK, fill: true)
  canvas.draw_text("Hello, e-paper!", x: 20, y: 20, font: Font.new("DejaVuSans", size: 16), color: Color::WHITE)

  display.show(canvas)
end
```

---

## 📦 Installation

### On Raspberry Pi (with hardware)

```bash
# Install system dependencies
sudo apt install libvips-dev libfreetype-dev

# Add to your Gemfile
gem "chroma_wave"
```

ChromaWave auto-detects your GPIO/SPI backend. It prefers `lgpio` (Raspberry Pi 5 and modern Raspberry Pi OS), falls back to `gpiod`, and supports `bcm2835` and `wiringPi` for older setups. Override with:

```bash
gem install chroma_wave -- --with-epd-backend=lgpio
```

### On a development machine (no hardware)

```bash
gem "chroma_wave"
```

**The gem always installs.** When no GPIO/SPI library is found, ChromaWave compiles with a mock backend automatically. Drawing, rendering, and image processing all work normally — only hardware operations (`Display#show`, `Device.new`) raise `ChromaWave::DeviceError` with a clear message. Develop and test anywhere, deploy to the Pi.

### Optional dependencies

| Dependency | Required for | Install |
|------------|-------------|---------|
| libvips | `Image` loading (JPEG, PNG, WebP, etc.) | `apt install libvips-dev` |
| libfreetype | `Font` and `draw_text` | `apt install libfreetype-dev` |

Both are optional. Canvas, drawing primitives, and the full rendering pipeline work without them.

---

## 🖥️ Supported Displays

ChromaWave supports **70+ Waveshare e-paper display models** across all color capabilities and sizes — from 1.02" to 13.3".

| Category | Pixel Format | Examples |
|----------|-------------|---------|
| Monochrome (B/W) | 1-bit | EPD 2.13" V4, 7.5" V2, 13.3" |
| Grayscale (4-level) | 2-bit | EPD 3.7", 7.5" V2 (4-gray mode) |
| Tri-color (B/W/R or B/W/Y) | Dual 1-bit buffers | EPD 2.13b V4, 4.2bc |
| 7-color (ACeP) | 4-bit | EPD 5.65f, 4.01f |

Capabilities are discovered automatically from the model registry:

```ruby
display = ChromaWave::Display.new(model: :epd_2in13_v4)
display.respond_to?(:display_partial)  # => true  — supports partial refresh
display.respond_to?(:init_fast)        # => true  — supports fast mode

ChromaWave::Display.models  # => [:epd_2in13_v4, :epd_7in5_v2, ...]
```

Typos raise `ModelNotFoundError` with did-you-mean suggestions.

---

## 🎨 Usage

### Drawing

Every surface — Canvas, Framebuffer, Layer — shares the same drawing API through the `Surface` protocol:

```ruby
canvas = ChromaWave::Canvas.new(width: 800, height: 480)

# Shapes
canvas.draw_line(0, 0, 200, 100, color: Color::BLACK)
canvas.draw_rect(10, 10, 200, 100, color: Color::BLACK, stroke_width: 2)
canvas.draw_rounded_rect(10, 120, 200, 80, radius: 12, color: Color::RED, fill: true)
canvas.draw_circle(400, 240, 60, color: Color::BLUE, fill: true)
canvas.draw_ellipse(600, 240, 80, 40, color: Color::BLACK)
canvas.draw_polygon([[10, 400], [100, 350], [190, 400]], color: Color::BLACK, fill: true)

# Text with TrueType fonts
font = ChromaWave::Font.new("DejaVuSans", size: 24)
canvas.draw_text("Temperature: 72°F", x: 50, y: 20, font: font, color: Color::BLACK)
canvas.draw_text("A longer paragraph that wraps cleanly within bounds.",
                 x: 50, y: 60, font: font, max_width: 300, align: :center)

# Icons (bundled Lucide set — 1,500+ icons, zero config)
icons = ChromaWave::IconFont.lucide(size: 32)
icons.draw(canvas, :wifi, x: 10, y: 10)
icons.draw(canvas, :battery_full, x: 50, y: 10)
icons.draw(canvas, :thermometer, x: 90, y: 10)

# Images (JPEG, PNG, WebP — any format libvips handles)
photo = ChromaWave::Image.load("photo.jpg").resize(width: 400)
photo.draw_onto(canvas, x: 200, y: 40)
```

### Layers

Layers are clipped, offset sub-regions of any surface. They're the foundation for widget-based composition:

```ruby
canvas = ChromaWave::Canvas.new(width: 800, height: 480)

# Each layer has its own local coordinate space
canvas.layer(x: 0, y: 0, width: 800, height: 60) do |header|
  header.clear(Color::BLACK)
  header.draw_text("Dashboard", x: 10, y: 10, font: title_font, color: Color::WHITE)
end

canvas.layer(x: 10, y: 70, width: 380, height: 200) do |chart_area|
  chart_area.draw_rect(0, 0, chart_area.width, chart_area.height, color: Color::BLACK)
  # Draw chart contents in local coordinates...
end

# Layers compose — a Layer of a Layer works correctly
canvas.layer(x: 410, y: 70, width: 380, height: 400) do |sidebar|
  sidebar.layer(x: 10, y: 10, width: 360, height: 50) do |status_bar|
    status_bar.draw_text("Status: OK", x: 0, y: 0, font: body_font)
  end
end
```

### Colors

Colors are immutable RGBA value objects with alpha compositing:

```ruby
# Named constants
Color::BLACK, Color::WHITE, Color::RED, Color::YELLOW, Color::GREEN,
Color::BLUE, Color::ORANGE, Color::DARK_GRAY, Color::LIGHT_GRAY

# Custom colors
teal = ChromaWave::Color.new(r: 0, g: 128, b: 128)
translucent_red = ChromaWave::Color.new(r: 255, g: 0, b: 0, a: 128)

# Alpha compositing (source-over)
result = translucent_red.over(Color::WHITE)  # blended, always opaque
```

Alpha is fully supported in the Canvas layer. The Renderer flattens it during quantization — the display always receives opaque palette entries.

### Display Workflows

```ruby
# Common path: draw on Canvas, let Display handle rendering
display = ChromaWave::Display.new(model: :epd_7in5_v2)
canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
# ... draw on canvas ...
display.show(canvas)   # auto-renders with Floyd-Steinberg dithering

# Power-user path: control rendering directly
renderer = ChromaWave::Renderer.new(pixel_format: display.pixel_format, dither: :ordered)
fb = renderer.render(canvas)
display.show(fb)

# Partial refresh (on supported models)
display.display_base(fb)        # write base image
# ... update canvas ...
display.display_partial(fb)     # fast partial update

# Block-style lifecycle
ChromaWave::Display.open(model: :epd_2in13_v4) do |d|
  d.show(canvas)
end  # auto-closes, releases GPIO/SPI
```

---

## 🏗️ Architecture

ChromaWave separates drawing, rendering, and hardware into three distinct layers:

```
┌────────────────────────────────────────────────────────┐
│                  🎨 Drawing Layer                      │
│                                                        │
│  Surface ← duck-type protocol (set_pixel, dimensions)  │
│    ├── Canvas       RGBA packed String, C-accelerated  │
│    ├── Layer        clipped sub-region of any Surface  │
│    └── Framebuffer  device-format, C-backed            │
│                                                        │
│  Drawing primitives work on any Surface:               │
│    line, rect, circle, text, blit, flood_fill          │
│                                                        │
├────────────────────────────────────────────────────────┤
│                  🔄 Rendering Layer                    │
│                                                        │
│  Renderer: Canvas → Framebuffer                        │
│    • Palette mapping (RGBA → nearest palette entry)    │
│    • Dithering (Floyd-Steinberg, ordered, threshold)   │
│    • Dual-buffer splitting (Canvas → two mono FBs)     │
│                                                        │
├────────────────────────────────────────────────────────┤
│                  ⚡ Hardware Layer                     │
│                                                        │
│  Framebuffer → Display → Device                        │
│    • Pixel packing, SPI transfer, GPIO lifecycle       │
│    • GVL released during refresh (other threads run)   │
│    • Thread-safe via Mutex on all hardware ops         │
│                                                        │
└─────────────────────────────────────────────────────── ┘
```

**Canvas** stores pixels as packed RGBA bytes in a single Ruby String — two GC objects regardless of resolution. Three C-accelerated hot paths (clear, alpha blit, bulk RGBA load) have Ruby fallbacks for portability.

**Renderer** is the only place quantization and dithering occur. It converts full-color Canvas pixels to palette entries, keeping composition in RGBA until the last possible moment.

**Display** models are auto-built from a two-tier driver registry at gem load time. Simple displays are pure config data (~10 lines each). Complex models override with custom C functions for LUT selection, power cycling, or buffer transformations. Capabilities (partial refresh, fast mode, grayscale, dual-buffer, regional refresh) are composable Ruby modules — `respond_to?` and `is_a?` work naturally.

---

## 🧪 Develop Without Hardware

ChromaWave is designed to be developed, tested, and previewed without a physical display.

### MockDevice

`MockDevice` is a full `Display` subclass that replaces hardware calls with inspectable no-op stubs. Same model config, same capabilities, same API — just no SPI:

```ruby
mock = ChromaWave::MockDevice.new(model: :epd_7in5_v2)

canvas = ChromaWave::Canvas.new(width: mock.width, height: mock.height)
canvas.draw_rect(10, 10, 100, 50, color: Color::BLACK, fill: true)
mock.show(canvas)

# Inspect what happened
mock.operations           # => [{ op: :init, ... }, { op: :show, buffer_bytes: 48000, ... }]
mock.operation_count(:show)  # => 1
mock.last_framebuffer     # => the rendered Framebuffer

# Palette-accurate PNG export — see what the display would show
mock.save_png("preview.png")
```

The PNG export reflects the actual display output: mono displays produce black and white, tri-color shows black/white/red, and dithering artifacts are visible because the Renderer has already quantized.

### Testing with RSpec

```ruby
describe "weather widget", :hardware, model: :epd_7in5_v2 do
  subject(:device) { |example| example.metadata[:mock_device] }

  it "renders the temperature" do
    canvas = build_weather_canvas(temp: 72)
    device.show(canvas)

    expect(device.operations(:show).size).to eq(1)
    expect(device.last_framebuffer).not_to be_nil
  end
end
```

MockDevice also supports busy-wait simulation for testing timeout and interrupt paths:

```ruby
mock = ChromaWave::MockDevice.new(model: :epd_2in13_v4, busy_duration: 5.0)
mock.show(canvas)  # blocks for ~5 seconds, exercises timeout logic
```

---

## ⚡ Performance

Canvas uses a packed binary String buffer (4 bytes/pixel), not an Array of Color objects. Bulk operations bypass Ruby object creation entirely:

| Operation | Packed String (ChromaWave) | Array\<Color\> (naive) |
|-----------|--------------------------|----------------------|
| 800x480 Canvas memory | ~1.5 MB | ~15 MB |
| GC objects per Canvas | 2 | ~384,001 |
| Image blit (800x480) | ~5 ms (C accelerator) | ~800 ms |
| Alpha composite (400x300) | ~2 ms (C accelerator) | ~50 ms |

Display refresh takes 2–15 seconds depending on the model. ChromaWave releases the GVL during refresh so other Ruby threads continue running. Hardware operations are thread-safe via Mutex — concurrent display access is serialized cleanly.

---

## 🔧 Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt.

```bash
bundle install
rake compile    # build the C extension
rake spec       # run the test suite (uses MockDevice, no hardware needed)
```

### Regenerating the Lucide icon map

```bash
rake icons:generate   # parses Lucide metadata → lucide_glyphs.rb
```

---

## 🤝 Contributing

`chroma_wave` is open source, but not open contribution. If you have a bug fix or feature you'd like to see, please open an issue first to discuss. This helps ensure a high signal-to-noise ratio and maintain project vision. Cold pull requests without prior discussion will likely be closed, regardless of quality or origin.

---

## 📄 License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

ChromaWave vendors [Waveshare's e-paper driver library](https://github.com/waveshareteam/e-Paper) (MIT) and bundles the [Lucide](https://lucide.dev/) icon font (ISC).
