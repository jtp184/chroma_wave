# Feature 005: Flexbox-Lite Layout DSL

## Decision

A declarative layout DSL using Ruby blocks, inspired by CSS Flexbox but dramatically simpler.
Supports rows, columns, flex sizing, padding, alignment, and built-in styling (background,
border). No e-paper library in any language has this — it's ChromaWave's killer differentiator.

**Priority:** P1 (major differentiator)
**Effort:** Large
**Prerequisite for:** Feature 010 (Widget Library)

## Dependencies

**Blocked by:** None
**Blocks:** Feature 010 (Widget Library) — hard blocker. Widgets are built on the Layout
DSL and cannot be implemented until the DSL, calculator, and renderer are stable.

---

## Design

### API

```ruby
layout = ChromaWave::Layout.build(width: 800, height: 480) do
  row(height: 60, background: Color::BLACK, padding: 10) do
    text "Dashboard", font: title_font, color: Color::WHITE
    spacer
    icon :wifi, font: icons, color: Color::WHITE
    icon :battery_full, font: icons, color: Color::WHITE
  end

  columns(flex: 1, gap: 10, padding: 10) do
    column(flex: 2) do
      row(height: 40) { text "Temperature", font: label_font }
      row(flex: 1, background: Color::LIGHT_GRAY, border: Color::BLACK) do
        text "72°F", font: big_font, align: :center, valign: :center
      end
    end

    column(flex: 1) do
      row(height: 40) { text "Humidity", font: label_font }
      row(flex: 1) { text "45%", font: big_font, align: :center }
      row(height: 2, background: Color::BLACK)  # divider
      row(height: 40) { text "Updated 5m ago", font: small_font, align: :center }
    end
  end
end

# Render to canvas
canvas = layout.render

# Or render directly to display
display.show(layout)
```

### Core Concepts

**Containers** — structural elements that hold children:

| Container | Behavior |
|---|---|
| `row` | Lays children out horizontally (left to right) |
| `column` | Lays children out vertically (top to bottom) |
| `columns` | Shorthand: a row that expects column children |
| `rows` | Shorthand: a column that expects row children |

**Sizing**:

| Property | Meaning |
|---|---|
| `width: 200` | Fixed pixel width |
| `height: 60` | Fixed pixel height |
| `flex: 1` | Proportional share of remaining space |
| `min_width:` / `min_height:` | Minimum size constraint |
| `max_width:` / `max_height:` | Maximum size constraint |

**Styling** (built into containers):

| Property | Type | Meaning |
|---|---|---|
| `background:` | Color | Fill color for the container area |
| `border:` | Color | 1px border around the container |
| `border_width:` | Integer | Border thickness (default: 1) |
| `padding:` | Integer or [t,r,b,l] | Inner spacing |
| `gap:` | Integer | Space between children |

**Content elements** — leaf nodes that render content:

| Element | Usage |
|---|---|
| `text(str, font:, color:, align:, valign:)` | Renders text, auto-wraps within container |
| `icon(name, font:, color:)` | Renders a named icon from an IconFont |
| `image(source, fit:)` | Renders an Image, fit: :contain / :cover / :stretch |
| `spacer` | Flexible empty space (flex: 1 by default) |
| `canvas_block { \|c\| ... }` | Escape hatch: direct Canvas drawing in a sized area |

**Alignment**:

| Property | Values | Applies to |
|---|---|---|
| `align:` | `:left`, `:center`, `:right` | Horizontal content alignment within container |
| `valign:` | `:top`, `:center`, `:bottom` | Vertical content alignment within container |

### Architecture

```
Layout.build(width:, height:, &block)
  |
  v
Layout::DSL (instance_eval's the block)
  |  - Builds a tree of Layout::Node objects
  |  - Each node: Container or Content element
  v
Layout::Calculator
  |  - Two-pass layout algorithm:
  |    1. Measure pass: compute intrinsic sizes (text metrics, image dims)
  |    2. Layout pass: resolve flex, distribute space, apply constraints
  |  - Result: each node has absolute (x, y, width, height)
  v
Layout::Renderer
  |  - Walks the node tree
  |  - For each node: draw background, border, content onto Canvas
  |  - Uses Layer for clipping (each container is a Layer)
  v
Canvas (fully rendered layout)
```

### Layout Algorithm (Flexbox-Lite)

**Measure pass** (bottom-up):
1. Leaf nodes report intrinsic size (text metrics, image dims, fixed size, or 0)
2. Containers sum children along main axis, max across cross axis
3. Fixed sizes override intrinsic sizes

**Layout pass** (top-down):
1. Start with root container at (0, 0, total_width, total_height)
2. For each container:
   a. Subtract padding and borders from available space
   b. Allocate fixed-size children first
   c. Distribute remaining space proportionally among flex children
   d. Apply min/max constraints (re-distribute if constrained)
   e. Position children along main axis with gap spacing
   f. Align children on cross axis per `align:` / `valign:`

### Display Integration

`Display#show` should accept a `Layout` in addition to Canvas and Framebuffer:

```ruby
display.show(canvas)     # existing
display.show(framebuffer) # existing
display.show(layout)     # new — calls layout.render, then shows the resulting canvas
```

### Files to Create

- `lib/chroma_wave/layout.rb` — entry point, `Layout.build`
- `lib/chroma_wave/layout/dsl.rb` — block DSL interpreter
- `lib/chroma_wave/layout/node.rb` — base node class
- `lib/chroma_wave/layout/container.rb` — row/column container
- `lib/chroma_wave/layout/content.rb` — text/icon/image/spacer content elements
- `lib/chroma_wave/layout/calculator.rb` — two-pass layout algorithm
- `lib/chroma_wave/layout/renderer.rb` — node tree to Canvas
- `spec/chroma_wave/layout_spec.rb` — integration specs
- `spec/chroma_wave/layout/calculator_spec.rb` — layout math
- `spec/chroma_wave/layout/dsl_spec.rb` — DSL parsing

### Files to Modify

- `lib/chroma_wave.rb` — require layout module
- `lib/chroma_wave/display.rb` — accept Layout in `show`

## Acceptance Criteria

- [ ] `Layout.build(width:, height:) { ... }` produces a Layout object
- [ ] `layout.render` returns a Canvas with the layout rendered
- [ ] `display.show(layout)` works (auto-renders and displays)
- [ ] Row containers lay children out horizontally
- [ ] Column containers lay children out vertically
- [ ] Fixed-size children get exact dimensions
- [ ] Flex children divide remaining space proportionally
- [ ] `padding:` creates inner spacing (single value or [t,r,b,l])
- [ ] `gap:` creates space between children
- [ ] `background:` fills the container area
- [ ] `border:` / `border_width:` draws container borders
- [ ] `text()` renders with word wrap within container bounds
- [ ] `icon()` renders a named icon
- [ ] `image()` renders with fit modes (:contain, :cover, :stretch)
- [ ] `spacer` fills available flex space
- [ ] `align:` and `valign:` position content within containers
- [ ] Containers nest arbitrarily deep
- [ ] `canvas_block { |c| ... }` provides escape hatch for custom drawing
- [ ] MockDevice can render and export layouts to PNG
- [ ] Specs cover: nesting, flex distribution, overflow/underflow, alignment, styling
