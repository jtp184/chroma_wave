# ChromaWave Mock Hardware Strategy

Design decisions and interactive contracts for developing, testing, and previewing
ChromaWave without physical e-paper hardware.

**Parent document:** [EXTENSION_STRATEGY.md](EXTENSION_STRATEGY.md)

---

## 1. Goals

1. **The gem always installs.** No GPIO/SPI library? Extension compiles with a C
   mock backend. Users can draw, compose, and render — hardware ops fail clearly.
2. **Tests never need hardware.** A Ruby-level `MockDevice` captures every hardware
   operation as an inspectable log. Full integration tests run in CI.
3. **Developers can see what they're building.** Palette-accurate PNG export shows
   what the physical display would render, including quantization and dithering.

---

## 2. Two-Layer Mock Architecture

Mocking operates at two distinct layers, each serving a different purpose:

```
┌──────────────────────────────────────────────────────────┐
│              🧪 Ruby Layer: MockDevice                   │
│                                                          │
│  Instance-based, injectable, records high-level ops.     │
│  Used in test suites and development scripts.            │
│  Swappable at runtime — no recompilation.                │
│                                                          │
├──────────────────────────────────────────────────────────┤
│              ⚙️  C Layer: MOCK Backend                    │
│                                                          │
│  Compile-time selection in extconf.rb.                   │
│  No-op stubs for GPIO/SPI so the extension compiles      │
│  on any platform. Pure memory operations work normally.  │
│  Detected automatically when no GPIO library is found.   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 2.1 C-Level MOCK Backend

**When:** `extconf.rb` finds no GPIO/SPI library (lgpio, bcm2835, gpiod, etc.)

**What it does:**
- Provides no-op stubs for `DEV_Module_Init`, `DEV_Module_Exit`, `DEV_SPI_WriteByte`,
  `DEV_Digital_Write`, `DEV_Digital_Read`, and friends
- The extension compiles and links successfully
- `Framebuffer`, `Canvas`, `PixelFormat`, drawing, and rendering all work normally
  (pure memory — no hardware calls)
- Hardware operations (`Device.new`, `Display#show`, `Display#clear`) raise
  `ChromaWave::DeviceError` at runtime with a clear message explaining no hardware
  backend was found

**What it does NOT do:**
- No operation recording (that's the Ruby layer's job)
- No error simulation
- No timing simulation

**Compile-time flag:** `-DEPD_MOCK_BACKEND`

**Emits a warning** at gem install time:
```
WARNING: No GPIO/SPI library found. ChromaWave installed with MOCK backend.
Drawing and rendering work normally. Hardware operations will raise DeviceError.
```

### 2.2 Ruby-Level MockDevice

**When:** Test suites, development scripts, visual previewing

**What it does:**
- Subclass of `Display` that replaces C hardware calls with no-op stubs
- Records every hardware operation as a structured log entry
- Supports configurable busy-wait delay for timeout/interrupt testing
- Supports palette-accurate PNG export of the last displayed framebuffer

**Instance-based.** Each `MockDevice.new` is fully independent — its own operation log,
its own configuration. Tests are isolated. Multiple mocks can coexist.

---

## 3. MockDevice Contract

### 3.1 Construction

```ruby
mock = ChromaWave::MockDevice.new(
  model: :epd_2in13_v4,      # determines resolution, pixel_format, capabilities
  busy_duration: 0,           # seconds (default: instant)
)
```

`model:` is required — it loads the same model config the real Display uses, so the
mock enforces the same resolution, pixel format, and capability constraints.

`busy_duration:` defaults to `0` (instant). Set to a positive value (e.g., `2.0`) to
simulate real refresh timing for testing timeout and interrupt paths.

### 3.2 Operation Log

Every hardware-level operation appends an entry to `mock.operations`. Construction
logs `:init` automatically (mirroring real Display's auto-initialization):

```ruby
mock.operations
# => [
#   { op: :init,    model: :epd_2in13_v4, timestamp: <Time> },
#   { op: :show,    buffer_bytes: 4000,    timestamp: <Time> },
#   { op: :clear,   color: :white,         timestamp: <Time> },
#   { op: :sleep,                          timestamp: <Time> },
#   { op: :close,                          timestamp: <Time> },
# ]
```

- `buffer_bytes` is the byte length of the rendered Framebuffer sent to the display
- `timestamp` is `Time.now` at the moment the operation was recorded

**Granularity is high-level only.** Named operations with metadata — no raw SPI bytes.
Individual command/data bytes are a C-level concern tested separately against the real
HAL stubs.

**Thread safety:** The operation log is protected by a Mutex. Concurrent operations
from multiple threads append safely.

**Convenience queries:**

```ruby
mock.operations(:show)         # filter by op type
mock.last_operation             # most recent entry
mock.operation_count(:show)     # count by type
mock.clear_operations!          # reset log (e.g., between test phases)
```

### 3.3 Display Interface

MockDevice is a `Display` subclass and exposes the same public API:

```ruby
mock.show(canvas)               # records :show, stores last framebuffer
mock.clear(color: :white)       # records :clear
mock.sleep                      # records :sleep
mock.close                      # records :close

# All five capability modules are included based on model config:
mock.display_partial(fb)        # PartialRefresh
mock.init_fast                  # FastRefresh
mock.init_grayscale             # GrayscaleMode
mock.show(canvas)               # DualBuffer (overrides show for tri-color models)
mock.display_region(fb, ...)    # RegionalRefresh
```

`show` accepts a Canvas (auto-rendered via Renderer, just like real Display) or a
pre-rendered Framebuffer. The rendered framebuffer is stored as `mock.last_framebuffer`
for inspection and PNG export.

### 3.4 PNG Export

```ruby
mock.show(canvas)
mock.save_png("preview.png")    # palette-accurate render of last_framebuffer
```

**Palette-accurate** means the PNG reflects what the physical display would show:
- Mono display → black and white pixels only
- Tri-color display → black, white, and red/yellow pixels
- 7-color display → actual 7-color palette
- Dithering artifacts are visible (since the Renderer has already quantized)

The PNG is the display's native resolution. No scaling or upsampling — it's a
pixel-perfect representation.

**Dependency:** Uses ruby-vips (already a project dependency for Image loading).
No additional dependencies introduced.

### 3.5 Busy-Wait Simulation

When `busy_duration:` is set to a positive value:

```ruby
mock = ChromaWave::MockDevice.new(model: :epd_2in13_v4, busy_duration: 2.0)
mock.show(canvas)  # blocks for ~2 seconds (simulating refresh)
```

This exercises timeout and interrupt code paths:
- The mock simulates the wait with `Kernel#sleep(busy_duration)` inside a
  background thread, allowing the main thread's timeout mechanism to fire
- `BusyTimeoutError` is raised if the configured display timeout is shorter
  than `busy_duration`
- Thread interruption via `Thread#raise` exercises the unblocking path

When `busy_duration: 0` (default), operations complete instantly.

---

## 4. Test Integration

### 4.1 RSpec Helper

```ruby
# spec/support/mock_device.rb

RSpec.configure do |config|
  config.around(:each, :hardware) do |example|
    mock = ChromaWave::MockDevice.new(model: example.metadata[:model] || :epd_2in13_v4)
    example.metadata[:mock_device] = mock
    example.run
  end
end
```

Usage in specs:

```ruby
describe "showing a canvas", :hardware, model: :epd_7in5_v2 do
  subject(:device) { |example| example.metadata[:mock_device] }

  it "records the show operation" do
    canvas = ChromaWave::Canvas.new(width: 800, height: 480)
    device.show(canvas)

    expect(device.operations(:show).size).to eq(1)
    expect(device.last_framebuffer).not_to be_nil
  end
end
```

### 4.2 What Each Layer Tests

| Test concern                        | Uses MockDevice? | Uses C MOCK? |
|-------------------------------------|------------------|--------------|
| Drawing primitives on Canvas        | No               | No           |
| Framebuffer pixel packing           | No               | No           |
| Renderer quantization / dithering   | No               | No           |
| Display#show integration            | **Yes**          | No           |
| Capability module dispatch          | **Yes**          | No           |
| Operation sequence (init→show→sleep)| **Yes**          | No           |
| GVL release / timeout paths         | **Yes** (with delay) | No      |
| C extension compiles on CI          | No               | **Yes**      |
| SPI byte-level protocol correctness | No               | **Yes**      |
| extconf.rb platform detection       | No               | **Yes**      |

The majority of the test suite needs neither mock — Canvas, Framebuffer, Renderer,
drawing, and all value objects are pure-memory and fully testable directly.

---

## 5. Injection Point

MockDevice is a `Display` subclass — it IS-A Display with the same capability modules,
loaded from the same model registry. Anywhere code accepts a Display, a MockDevice
works:

```ruby
# Real hardware:
display = ChromaWave::Display.new(model: :epd_2in13_v4)

# Testing — direct substitution:
display = ChromaWave::MockDevice.new(model: :epd_2in13_v4)
display.show(canvas)          # logs :show instead of sending SPI
display.respond_to?(:display_partial)  # => true (same capabilities)
display.is_a?(ChromaWave::Display)     # => true
```

The only behavioral difference: where real Display delegates to C hardware functions
(`_epd_display`, `_epd_clear`, etc.), MockDevice overrides those private methods with
Ruby stubs that record the operation and return immediately (or sleep for
`busy_duration`).

---

## 6. Scope Boundaries

### In scope (v1)
- C MOCK backend with no-op GPIO/SPI stubs
- Ruby MockDevice with operation logging
- High-level operation log (init, show, clear, sleep, close)
- Palette-accurate PNG export via `save_png`
- Configurable busy-wait delay
- Instance-based (independent mocks, isolated tests)
- RSpec test helper integration

### Out of scope (future)
- Raw SPI byte-level recording
- Network-based display simulation (remote preview)
- Live GUI preview window
- Mock failure injection (simulate SPI errors, GPIO failures)
- Multi-display mock coordination
- Performance profiling hooks
