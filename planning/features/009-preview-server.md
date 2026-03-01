# Feature 009: Browser Preview Server

## Decision

A WebSocket-based live preview server that renders Canvas output to a browser window in
real-time, showing the exact palette and dimensions of the target display. Zero frontend
dependencies — just vanilla HTML/JS served by the gem.

**Priority:** P2 (developer experience)
**Effort:** Medium

## Dependencies

**Blocked by:** None
**Blocks:** None
**Enhanced by:**
- Feature 002 (Rotation) — if rotation is implemented, the preview should display the
  rotated orientation. Preview wraps MockDevice which inherits Display rotation, so this
  comes for free if 002 lands first. If 009 lands before 002, rotation support can be
  added later with no API changes.
- Feature 008 (Dirty Region Tracking) — if dirty tracking is available, the preview could
  highlight the dirty region in the browser overlay. Nice-to-have, not blocking.

---

## Design

### API

```ruby
# Start a preview server for a specific display model
preview = ChromaWave::Preview.start(model: :epd_7in5_v2, port: 4567)

# Preview acts like a Display — same API
canvas = Canvas.new(width: preview.width, height: preview.height)
canvas.draw_text("Hello", x: 10, y: 10, font: font, color: Color::BLACK)
preview.show(canvas)  # pushes to browser instead of hardware

# Block form
ChromaWave::Preview.open(model: :epd_2in13_v4) do |preview|
  preview.show(canvas)
  sleep  # keep server running until Ctrl+C
end

# Stop
preview.stop
```

### Architecture

```
Ruby Process                          Browser
┌──────────────────────┐              ┌─────────────────────┐
│  Preview (Display)   │              │  HTML/JS viewer     │
│                      │   WebSocket  │                     │
│  show(canvas)        │──────────────│  <canvas> element   │
│    → render to FB    │  PNG base64  │  Exact palette      │
│    → render to PNG   │              │  Exact dimensions   │
│    → push via WS     │              │  Auto-scale to fit  │
│                      │              │  Model info overlay  │
│  WEBrick server      │   HTTP GET   │                     │
│    /                 │──────────────│  index.html         │
│    /ws               │              │  WebSocket client   │
└──────────────────────┘              └─────────────────────┘
```

### Components

**1. Preview class** (subclass of Display or Display-like duck type):

- Wraps a MockDevice for rendering
- On `show(canvas)`: renders to framebuffer, converts to PNG, pushes via WebSocket
- Manages WEBrick HTTP server in a background thread
- Serves static HTML/JS at `/`
- WebSocket endpoint at `/ws`

**2. HTML viewer** (embedded in gem, served by WEBrick):

- Single HTML file with inline CSS/JS
- `<canvas>` element at exact display dimensions
- WebSocket client receives base64 PNG, draws to canvas
- Auto-scales to fit browser window while maintaining aspect ratio
- Overlay showing: model name, dimensions, pixel format, refresh count
- Dark background to simulate display bezel

**3. Dependencies**:

- `webrick` — stdlib in Ruby < 3.0, bundled gem in 3.0+. Already widely available.
- No external frontend dependencies (no npm, no bundler for JS)
- WebSocket: use a minimal pure-Ruby WebSocket server (or `faye-websocket` + WEBrick)

### Server Lifecycle

```ruby
Preview.start(model:, port:)
  → Create MockDevice for the model
  → Start WEBrick in a background Thread
  → Register WebSocket upgrade handler
  → Print "Preview running at http://localhost:4567"
  → Return Preview instance

preview.show(canvas)
  → MockDevice.show(canvas)  # render + dither
  → MockDevice.save_png(StringIO)  # palette-accurate PNG
  → Base64 encode
  → Push to all connected WebSocket clients

preview.stop
  → Shutdown WEBrick
  → Join background thread
```

### Files to Create

- `lib/chroma_wave/preview.rb` — Preview class, server lifecycle
- `lib/chroma_wave/preview/server.rb` — WEBrick setup, WebSocket handler
- `lib/chroma_wave/preview/viewer.html` — embedded HTML/JS viewer
- `spec/chroma_wave/preview_spec.rb`

### Files to Modify

- `lib/chroma_wave.rb` — require preview (lazy-loaded)
- `chroma_wave.gemspec` — add webrick dependency (if not already present)

## Acceptance Criteria

- [ ] `Preview.start(model:)` launches a local HTTP server
- [ ] Browser at `http://localhost:port` shows display dimensions and model info
- [ ] `preview.show(canvas)` pushes a palette-accurate PNG to the browser
- [ ] Browser auto-updates on each `show()` call (no manual refresh)
- [ ] Display dimensions are exact (pixel-for-pixel, no interpolation)
- [ ] Browser auto-scales to fit window while maintaining aspect ratio
- [ ] `preview.stop` cleanly shuts down the server
- [ ] Block form `Preview.open { }` auto-stops on block exit
- [ ] Works with all pixel formats (MONO, GRAY4, COLOR4, COLOR7)
- [ ] Rotation (Feature 002) is reflected in the preview
- [ ] Multiple browser clients can connect simultaneously
- [ ] Missing webrick raises `DependencyError` with install hint
- [ ] Server runs in background thread, doesn't block the main thread
- [ ] Specs verify server starts, accepts connections, and pushes data
