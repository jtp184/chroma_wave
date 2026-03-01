# Feature 010: Widget Library

## Decision

Part of the gem, shipped in `lib/chroma_wave/widgets/`. Built on top of the Layout DSL
(Feature 005 is a hard prerequisite). Pre-built, composable UI components that serve as both
ready-to-use building blocks and architecture examples.

**Priority:** P3 (depends on Layout DSL)
**Effort:** Large
**Prerequisites:** Feature 005 (Layout DSL)

## Dependencies

**Blocked by:** Feature 005 (Layout DSL) — **hard blocker.** Widgets compose with the
Layout DSL via the `widget` method in the DSL. The Widget protocol's `intrinsic_size` is
consumed by the Layout calculator. Implementation cannot begin until Feature 005's DSL,
calculator, and renderer are stable and merged.

**Blocks:** None
**Enhanced by:**
- Feature 006 (QR/Barcodes) — a `QRWidget` wrapping `draw_qr` would be a natural
  addition, but is not in the initial widget set. Can be added later.
- Feature 007 (CIE Lab) — widgets rendering color content benefit from accurate palette
  mapping, but this is transparent (widgets draw on Canvas, renderer handles quantization).

---

## Design

### Widget Set

Based on product owner decisions, the initial widget set includes:

| Widget | Description |
|---|---|
| `ClockWidget` | Time display with configurable format (12/24hr, date, analog face) |
| `ProgressBar` | Horizontal/vertical fill bar with percentage label |
| `StatusBar` | Icon + text row (battery, wifi, etc.) |
| `Chart` | Bar charts, sparklines, line graphs from numeric arrays |
| `DataTable` | Tabular data with headers, column alignment, row separators |
| `WebContent` | Fetch and render web content (HTML-to-text extraction) |

### API

```ruby
# Widgets compose with the Layout DSL
layout = Layout.build(width: 800, height: 480) do
  row(height: 40) do
    widget Widgets::StatusBar.new(
      items: [
        { icon: :wifi, text: "Connected" },
        { icon: :battery_full, text: "85%" }
      ],
      icon_font: icons,
      text_font: small_font
    )
  end

  columns(flex: 1, gap: 10, padding: 10) do
    column(flex: 1) do
      widget Widgets::Clock.new(
        format: :digital_24h,
        font: big_font,
        show_date: true,
        date_font: small_font
      )
    end

    column(flex: 1) do
      widget Widgets::Chart.new(
        data: [72, 74, 71, 69, 73, 75, 72],
        labels: %w[Mon Tue Wed Thu Fri Sat Sun],
        type: :bar,
        font: small_font
      )
    end
  end

  row(height: 100) do
    widget Widgets::DataTable.new(
      headers: ["Sensor", "Value", "Status"],
      rows: [
        ["Temperature", "72°F", "Normal"],
        ["Humidity", "45%", "Normal"],
        ["Pressure", "29.92 inHg", "Stable"]
      ],
      font: body_font
    )
  end
end

# Standalone widget rendering (without Layout DSL)
clock = Widgets::Clock.new(format: :digital_12h, font: big_font)
clock.render(canvas, x: 10, y: 10, width: 200, height: 80)
```

### Widget Protocol

All widgets implement a common interface:

```ruby
module Widgets
  module Widget
    # Measure intrinsic size (for layout flex calculation)
    def intrinsic_size(available_width:, available_height:)
      # => { width:, height: }
    end

    # Render into a bounded area
    def render(surface, x:, y:, width:, height:)
    end
  end
end
```

### Individual Widget Designs

**ClockWidget:**
```ruby
Clock.new(
  format: :digital_24h,     # :digital_12h, :digital_24h, :analog
  font: Font,               # for digital display
  show_date: false,          # show date below time
  date_format: "%B %d, %Y", # strftime format
  date_font: Font,           # smaller font for date
  color: Color::BLACK
)
```

**ProgressBar:**
```ruby
ProgressBar.new(
  value: 0.75,              # 0.0 to 1.0
  orientation: :horizontal, # :horizontal, :vertical
  show_label: true,         # "75%"
  label_font: Font,
  fill_color: Color::BLACK,
  background_color: Color::LIGHT_GRAY,
  border_color: Color::BLACK
)
```

**StatusBar:**
```ruby
StatusBar.new(
  items: [{ icon: :wifi, text: "Connected" }, ...],
  icon_font: IconFont,
  text_font: Font,
  color: Color::BLACK,
  separator: "|"            # between items
)
```

**Chart:**
```ruby
Chart.new(
  data: [1, 2, 3],          # numeric array
  labels: ["A", "B", "C"],  # optional x-axis labels
  type: :bar,               # :bar, :line, :sparkline
  font: Font,                # for labels/values
  color: Color::BLACK,
  fill: true,               # fill bars / area under line
  show_values: false,        # show value above each bar
  y_range: [0, 100]         # optional fixed y-axis range
)
```

**DataTable:**
```ruby
DataTable.new(
  headers: ["Col1", "Col2"],
  rows: [["val1", "val2"], ...],
  font: Font,
  header_font: Font,          # bold/larger for headers (optional)
  column_widths: :auto,       # :auto, :equal, or [100, 200, ...]
  align: [:left, :right],     # per-column alignment
  row_separator: true,        # horizontal lines between rows
  header_separator: true,     # line below header
  striped: false              # alternating row backgrounds
)
```

**WebContent:**
```ruby
WebContent.new(
  url: "https://api.example.com/data",
  parser: ->(body) { JSON.parse(body)["temperature"] },
  font: Font,
  refresh_interval: 300,     # seconds between fetches (for daemon mode)
  fallback: "No data"        # shown on fetch failure
)
```

Uses `net/http` (stdlib). Lazy-loaded. The `parser:` lambda extracts displayable text
from the response body.

### Files to Create

- `lib/chroma_wave/widgets.rb` — widget module, autoloads
- `lib/chroma_wave/widgets/widget.rb` — Widget protocol module
- `lib/chroma_wave/widgets/clock.rb`
- `lib/chroma_wave/widgets/progress_bar.rb`
- `lib/chroma_wave/widgets/status_bar.rb`
- `lib/chroma_wave/widgets/chart.rb`
- `lib/chroma_wave/widgets/data_table.rb`
- `lib/chroma_wave/widgets/web_content.rb`
- `spec/chroma_wave/widgets/clock_spec.rb`
- `spec/chroma_wave/widgets/progress_bar_spec.rb`
- `spec/chroma_wave/widgets/status_bar_spec.rb`
- `spec/chroma_wave/widgets/chart_spec.rb`
- `spec/chroma_wave/widgets/data_table_spec.rb`
- `spec/chroma_wave/widgets/web_content_spec.rb`

### Files to Modify

- `lib/chroma_wave.rb` — require widgets
- `lib/chroma_wave/layout/dsl.rb` — add `widget` method to DSL

## Acceptance Criteria

- [ ] All widgets implement the Widget protocol (`intrinsic_size`, `render`)
- [ ] All widgets work standalone (`widget.render(canvas, x:, y:, width:, height:)`)
- [ ] All widgets compose with Layout DSL (`widget Widgets::Clock.new(...)`)
- [ ] ClockWidget renders current time in 12h and 24h formats
- [ ] ClockWidget optionally shows date with configurable format
- [ ] ProgressBar renders horizontal and vertical fill bars with labels
- [ ] StatusBar renders icon+text items in a row
- [ ] Chart renders bar, line, and sparkline charts from numeric data
- [ ] DataTable renders tabular data with headers, alignment, and separators
- [ ] WebContent fetches URL, parses response, and renders text
- [ ] WebContent shows fallback text on network failure
- [ ] All widgets accept color and font configuration
- [ ] All widgets render correctly on MockDevice (PNG export verifiable)
- [ ] Specs cover each widget's rendering, configuration, and edge cases
