# Waveshare E-Paper Display Library Evaluation

## 1. Overview

The vendor library at `vendor/waveshare_epd/` is Waveshare's official C SDK for driving their
e-Paper display product line from Linux single-board computers (Raspberry Pi, Jetson Nano). It is
a compile-time-configured, flat C library with no dynamic dispatch, no runtime polymorphism, and
no allocator abstraction. Every display model is a separate pair of `.h`/`.c` files that
hard-code controller register sequences, LUT waveform tables, and buffer layout math.

**License:** MIT (all files).

---

## 2. Directory Structure

```
vendor/waveshare_epd/
  lib/
    Config/                 # Hardware Abstraction Layer (HAL)
      DEV_Config.h/c          Platform-agnostic GPIO/SPI/delay interface
      Debug.h                 Conditional printf macro (compile-time -DDEBUG)
      RPI_gpiod.h/c           gpiod backend for RPi (USE_DEV_LIB)
      dev_hardware_SPI.h/c    /dev/spidev0.0 backend for RPi
      sysfs_gpio.h/c          sysfs GPIO backend for Jetson
      sysfs_software_spi.h/c  Bit-bang SPI backend for Jetson
    e-Paper/                # Display Model Drivers (~70 .h + ~70 .c files)
      EPD_<model>.h/c         One pair per hardware SKU
    Fonts/                  # Bitmap Font Tables
      fonts.h                 sFONT (ASCII) and cFONT (GB2312) typedefs
      font8.c .. font24.c    Bitmap data for 8/12/16/20/24px ASCII fonts
      font12CN.c, font24CN.c Bitmap data for Chinese character fonts
    GUI/                    # Drawing / Image Layer
      GUI_Paint.h/c           2D primitives, text, rotation, mirroring
      GUI_BMPfile.h/c         BMP file loading (1-bit, 4-gray, 7-color, etc.)
  examples/                 # Test programs, one per display model
    EPD_<model>_test.c
    main.c                    Entry point that calls the selected test
    ImageData.h/c             Embedded test image bitmaps
  pic/                      # Sample BMP images for testing
  Makefile                  # Compile-time model + platform selection
```

---

## 3. Architecture and Layering

The library uses a strict four-layer stack, all resolved at compile time:

```
  Application Code (examples / our Ruby extension)
        |
        v
  +------------------+
  | GUI_Paint         |  Drawing primitives, text rendering, BMP loading.
  | GUI_BMPfile       |  Operates on a caller-allocated byte buffer.
  +------------------+
        |
        v
  +------------------+
  | EPD_<model>       |  Model-specific driver. Knows resolution, controller
  |                    |  register protocol, LUT waveforms, busy-wait polarity.
  |                    |  Calls DEV_* HAL functions directly.
  +------------------+
        |
        v
  +------------------+
  | DEV_Config        |  Thin HAL: GPIO read/write, SPI byte/block,
  |                    |  delay_ms, module_init/exit.
  +------------------+
        |
        v
  +------------------+
  | Platform Backend  |  One of: bcm2835, wiringPi, lgpio, gpiod,
  |                    |  sysfs GPIO, software SPI (Jetson).
  |                    |  Selected via #ifdef at compile time.
  +------------------+
```

**Key architectural facts:**

- **No vtable / function pointers.** Display model selection is a compile-time Makefile choice
  (`EPD=epd2in13V4`). Only one driver compiles into any given binary.
- **Global mutable state.** `PAINT Paint` is a single global struct. `Paint_SelectImage()` swaps
  the active buffer pointer. Only one image context is active at a time.
- **GPIO pin assignments are global ints**, set once in `DEV_GPIO_Init()`.
- **No memory management abstraction.** Callers `malloc` image buffers and pass raw `UBYTE*`
  pointers. The library never allocates.

---

## 4. Key Data Types

### 4.1 Primitive Aliases (`DEV_Config.h`)

| Alias     | C Type     | Notes                                    |
|-----------|-----------|------------------------------------------|
| `UBYTE`   | `uint8_t` | Pixel data, register values              |
| `UWORD`   | `uint16_t`| Coordinates, dimensions, colors          |
| `UDOUBLE` | `uint32_t`| Buffer addresses, byte counts (misnomer) |

### 4.2 Image Context (`GUI_Paint.h`)

```c
typedef struct {
    UBYTE *Image;          // Pointer to caller-owned pixel buffer
    UWORD  Width;          // Logical width  (after rotation)
    UWORD  Height;         // Logical height (after rotation)
    UWORD  WidthMemory;    // Physical width  (before rotation)
    UWORD  HeightMemory;   // Physical height (before rotation)
    UWORD  Color;          // Default background color
    UWORD  Rotate;         // 0, 90, 180, 270
    UWORD  Mirror;         // MIRROR_NONE / HORIZONTAL / VERTICAL / ORIGIN
    UWORD  WidthByte;      // Bytes per row (depends on Scale)
    UWORD  HeightByte;     // Rows (== HeightMemory)
    UWORD  Scale;          // Bits-per-pixel mode: 2, 4, 6, 7, or 16
} PAINT;
```

`Scale` controls pixel packing in the buffer:

| Scale | BPP  | Pixels/Byte | Packing                         | Use Case                          |
|-------|------|-------------|---------------------------------|-----------------------------------|
| 2     | 1    | 8           | MSB-first bitmask               | Monochrome (black/white)          |
| 4     | 2    | 4           | 2-bit pairs, MSB-first          | 4-level grayscale                 |
| 6     | 4    | 2           | High/low nibble                 | 6-color displays                  |
| 7     | 4    | 2           | High/low nibble                 | 7-color (5.65" ACeP)             |
| 16    | 4    | 2           | High/low nibble                 | Dithered output                   |

### 4.3 Enumerations

| Enum           | Values                                  | Purpose                     |
|----------------|-----------------------------------------|-----------------------------|
| `MIRROR_IMAGE` | NONE, HORIZONTAL, VERTICAL, ORIGIN      | Buffer mirroring mode       |
| `DOT_PIXEL`    | 1x1 through 8x8                        | Brush/point size            |
| `DOT_STYLE`    | FILL_AROUND, FILL_RIGHTUP               | Point expansion direction   |
| `LINE_STYLE`   | SOLID, DOTTED                           | Line rendering mode         |
| `DRAW_FILL`    | EMPTY, FULL                             | Shape fill mode             |

### 4.4 Color Constants

```c
// Monochrome
#define WHITE  0xFF
#define BLACK  0x00
#define RED    BLACK  // Alias used for secondary color layer

// 4-level Grayscale
#define GRAY1  0x03   // Blackest
#define GRAY2  0x02
#define GRAY3  0x01
#define GRAY4  0x00   // White

// 7-color (EPD_5in65f only, defined in its header)
#define EPD_5IN65F_BLACK   0x0
#define EPD_5IN65F_WHITE   0x1
#define EPD_5IN65F_GREEN   0x2
#define EPD_5IN65F_BLUE    0x3
#define EPD_5IN65F_RED     0x4
#define EPD_5IN65F_YELLOW  0x5
#define EPD_5IN65F_ORANGE  0x6
#define EPD_5IN65F_CLEAN   0x7  // Afterimage artifact, not usable
```

---

## 5. Display Model Taxonomy

### 5.1 Model Count

~70 header files in `lib/e-Paper/`, representing **95+ distinct hardware SKUs** when version
suffixes are counted. The Makefile enumerates 66 named build targets.

### 5.2 Classification by Color Capability

| Category                | Suffix Pattern      | Buffer(s)      | Example Models                      |
|-------------------------|---------------------|----------------|-------------------------------------|
| Monochrome (B/W)        | no suffix, V2-V4    | 1 (1-bit)      | EPD_2in13_V4, EPD_7in5_V2          |
| Grayscale (4-level)     | `g`, `_4Gray` init  | 1 (2-bit)      | EPD_1in64g, EPD_3in7, EPD_7in5_V2* |
| Black + Red/Yellow      | `b`, `bc`, `c`      | 2 (1-bit each) | EPD_2in13b_V4, EPD_4in2bc          |
| 7-color (ACeP)          | `f`                 | 1 (4-bit)      | EPD_5in65f, EPD_4in01f             |
| Extended color           | `e`                 | 1 (4-bit)      | EPD_7in3e                           |

*Some monochrome models support an alternate 4-gray initialization mode (e.g., `EPD_7IN5_V2_Init_4Gray`).

### 5.3 Classification by Refresh Capability

| Capability        | API Pattern                    | Notes                                |
|-------------------|--------------------------------|--------------------------------------|
| Full refresh only | `Init()`, `Display(buf)`       | Simplest models, B+R/Y dual-buffer   |
| Full + Fast       | `Init()`, `Init_Fast()`        | Faster full refresh via temp trick    |
| Full + Partial    | `Init()`, `Display_Partial()`  | Region update without full redraw    |
| Full + Base + Part| `Display_Base()`, `_Partial()` | Write base frame, then diff updates  |
| Partial + region  | `Display_Part(buf,x,y,w,h)`   | Sub-rectangle partial refresh        |

### 5.4 Per-Model API Surface (Representative)

**Monochrome with partial refresh** (`EPD_2in13_V4.h`):
```c
EPD_2in13_V4_Init()              // Standard full-refresh init
EPD_2in13_V4_Init_Fast()         // Fast refresh via temp register trick
EPD_2in13_V4_Init_GUI()          // GUI-optimized init
EPD_2in13_V4_Clear()             // Clear to white
EPD_2in13_V4_Clear_Black()       // Clear to black
EPD_2in13_V4_Display(buf)        // Full refresh from buffer
EPD_2in13_V4_Display_Fast(buf)   // Fast refresh from buffer
EPD_2in13_V4_Display_Base(buf)   // Write base image (for partial)
EPD_2in13_V4_Display_Partial(buf)// Partial refresh from buffer
EPD_2in13_V4_Sleep()             // Enter deep sleep
```

**Dual-buffer black+red** (`EPD_2in13b_V4.h`):
```c
EPD_2IN13B_V4_Init()
EPD_2IN13B_V4_Clear()
EPD_2IN13B_V4_Display(blackBuf, redBuf)  // Two buffers!
EPD_2IN13B_V4_Sleep()
```

**Large monochrome with grayscale** (`EPD_7in5_V2.h`):
```c
EPD_7IN5_V2_Init()
EPD_7IN5_V2_Init_Fast()
EPD_7IN5_V2_Init_Part()
EPD_7IN5_V2_Init_4Gray()
EPD_7IN5_V2_Clear()
EPD_7IN5_V2_ClearBlack()
EPD_7IN5_V2_Display(buf)
EPD_7IN5_V2_Display_Part(buf, x1, y1, x2, y2)
EPD_7IN5_V2_Display_4Gray(buf)
EPD_7IN5_V2_Sleep()
```

### 5.5 Naming Inconsistencies

The library has no consistent naming convention across models:

- Case: `EPD_2in13_V4` vs `EPD_2IN13B_V4` vs `EPD_7IN5_V2`
- Init return: some `void`, some `UBYTE` (return status)
- Clear variants: `Clear()` + `Clear_Black()` vs `ClearBlack()` vs just `Clear(color)`
- Display signature: `Display(buf)` vs `Display(blackBuf, redBuf)` vs `Display_part(buf,x,y,w,h)`
- Partial: `Display_Partial()` vs `Display_Part()` vs `Display_part()`
- Busy polarity: some wait for HIGH, some for LOW (per controller chip)

---

## 6. Hardware Abstraction Layer (DEV_Config)

### 6.1 Interface

```c
// GPIO
void  DEV_Digital_Write(UWORD Pin, UBYTE Value);
UBYTE DEV_Digital_Read(UWORD Pin);
void  DEV_GPIO_Mode(UWORD Pin, UWORD Mode);  // 0=input, 1=output

// SPI
void  DEV_SPI_WriteByte(UBYTE Value);
void  DEV_SPI_Write_nByte(uint8_t *pData, uint32_t Len);
void  DEV_SPI_SendData(UBYTE Reg);     // Bit-bang SPI (software fallback)
UBYTE DEV_SPI_ReadData(void);          // Bit-bang SPI read

// Lifecycle
UBYTE DEV_Module_Init(void);    // Returns 0 on success, 1 on failure
void  DEV_Module_Exit(void);
void  DEV_Delay_ms(UDOUBLE xms);
```

### 6.2 GPIO Pin Mapping

| Signal       | RPi BCM | Function                          |
|-------------|---------|-----------------------------------|
| EPD_RST_PIN | 17      | Hardware reset (active low pulse) |
| EPD_DC_PIN  | 25      | Data/Command select (0=cmd, 1=data)|
| EPD_CS_PIN  | 8       | SPI chip select (active low)      |
| EPD_BUSY_PIN| 24      | Display busy status (input)       |
| EPD_PWR_PIN | 18      | Power control (active high)       |
| EPD_MOSI_PIN| 10      | SPI MOSI (for bit-bang fallback)  |
| EPD_SCLK_PIN| 11      | SPI clock (for bit-bang fallback) |

### 6.3 Platform Backends

| Macro              | Library     | Platform   | Notes                              |
|--------------------|-------------|------------|------------------------------------|
| `USE_BCM2835_LIB`  | bcm2835     | RPi 1-4    | Direct register access, fastest    |
| `USE_WIRINGPI_LIB` | wiringPi    | RPi 1-4    | Deprecated upstream                |
| `USE_LGPIO_LIB`    | lgpio       | RPi 5      | Default in Makefile, newest        |
| `USE_DEV_LIB`      | gpiod+spidev| RPi (any)  | Most portable Linux GPIO           |
| `USE_DEV_LIB`      | sysfs       | Jetson     | sysfs GPIO + software SPI          |

### 6.4 SPI Configuration

All backends configure SPI mode 0, MSB-first, ~10 MHz clock. The display protocol is:
1. Pull DC low for command byte
2. Pull DC high for data byte(s)
3. CS is toggled around each byte transfer

### 6.5 Display Lifecycle (Common Pattern)

```
DEV_Module_Init()                  // Open GPIO/SPI handles, set pin directions
  |
EPD_<model>_Init()                 // Reset pulse -> SW reset cmd -> register config
  |                                // Load LUT waveform tables (model-specific)
EPD_<model>_Clear()                // Optional: fill display RAM with 0xFF
  |
[Caller allocates image buffer]    // size = ceil(width/8) * height  (for 1-bit)
  |
Paint_NewImage(buf, w, h, rot, bg) // Initialize PAINT global with buffer geometry
Paint_Clear(WHITE)                 // Fill buffer
Paint_Draw*(...)                   // Draw into buffer
  |
EPD_<model>_Display(buf)           // Send buffer over SPI -> trigger refresh
EPD_<model>_ReadBusy()             // Spin-wait until refresh completes
  |
EPD_<model>_Sleep()                // Enter deep sleep (display retains image)
  |
DEV_Module_Exit()                  // Release GPIO/SPI handles
```

---

## 7. GUI / Drawing Layer

### 7.1 API Summary

**Image Management:**
- `Paint_NewImage(buf, w, h, rotate, color)` -- configure global PAINT struct
- `Paint_SelectImage(buf)` -- switch active buffer pointer
- `Paint_SetRotate(0|90|180|270)` -- logical rotation
- `Paint_SetMirroring(MIRROR_*)` -- horizontal/vertical flip
- `Paint_SetScale(2|4|6|7|16)` -- set bits-per-pixel mode
- `Paint_Clear(color)` -- fill entire buffer
- `Paint_ClearWindows(x1,y1,x2,y2,color)` -- fill rectangle

**Drawing Primitives:**
- `Paint_SetPixel(x, y, color)` -- single pixel (handles rotation, mirror, scale)
- `Paint_DrawPoint(x, y, color, size, style)` -- sized point (1x1 to 8x8)
- `Paint_DrawLine(x1,y1,x2,y2, color, width, style)` -- Bresenham line
- `Paint_DrawRectangle(x1,y1,x2,y2, color, width, fill)` -- rect or filled rect
- `Paint_DrawCircle(cx,cy,r, color, width, fill)` -- Bresenham circle

**Text:**
- `Paint_DrawChar(x, y, char, font, fg, bg)` -- single ASCII character
- `Paint_DrawString_EN(x, y, str, font, fg, bg)` -- English string with wrapping
- `Paint_DrawString_CN(x, y, str, font, fg, bg)` -- Chinese (GB2312) string
- `Paint_DrawNum(x, y, int, font, fg, bg)` -- integer
- `Paint_DrawNumDecimals(x, y, double, font, digits, fg, bg)` -- decimal number
- `Paint_DrawTime(x, y, time, font, fg, bg)` -- HH:MM:SS from PAINT_TIME struct

**Image Loading:**
- `Paint_DrawBitMap(buf)` -- raw byte copy from embedded bitmap
- `GUI_ReadBmp(path, x, y)` -- load 1-bit BMP from file
- `GUI_ReadBmp_4Gray(path, x, y)` -- load and quantize to 4-gray
- `GUI_ReadBmp_16Gray(path, x, y)` -- load and quantize to 16-gray
- `GUI_ReadBmp_RGB_4Color(path, x, y)` -- load and quantize to 4-color
- `GUI_ReadBmp_RGB_6Color(path, x, y)` -- quantize to 6-color
- `GUI_ReadBmp_RGB_7Color(path, x, y)` -- quantize to 7-color (ACeP)

### 7.2 Font System

Two font types:

```c
typedef struct { const uint8_t *table; uint16_t Width; uint16_t Height; } sFONT;    // ASCII bitmap
typedef struct { const CH_CN *table; uint16_t size, ASCII_Width, Width, Height; } cFONT; // GB2312
```

Available sizes: Font8 (5x8), Font12 (7x12), Font16 (11x16), Font20 (14x20), Font24 (17x24),
Font12CN, Font24CN.

Fonts are hard-coded bitmap arrays. No TTF/OTF support. No kerning. Fixed-width only.

### 7.3 Design Limitations

1. **Single global PAINT struct.** Cannot compose multiple image contexts simultaneously.
   `Paint_SelectImage()` is the only way to switch, and it doesn't save/restore state.
2. **No clipping.** Out-of-bounds writes silently fail via bounds check in `Paint_SetPixel`,
   but drawing a shape that partially extends off-screen will just drop pixels.
3. **No alpha / compositing.** All drawing is opaque replacement.
4. **No anti-aliasing.** Circle and line algorithms are pixel-exact Bresenham.
5. **Paint_DrawNum has a bug**: it swaps fg/bg arguments when calling `Paint_DrawString_EN`.

---

## 8. Build System

The Makefile uses a massive `ifeq` chain (66 entries) to select one driver `.c` + one test `.c`
based on the `EPD` variable:

```bash
make RPI EPD=epd2in13V4    # Build for 2.13" V4 on Raspberry Pi with lgpio
make JETSON EPD=epd7in5V2  # Build for 7.5" V2 on Jetson Nano
```

**Compilation units for a typical build:**
1. `DEV_Config.c` + platform backend `.c` files (compiled separately as RPI_DEV/JETSON_DEV)
2. `EPD_<model>.c` (the selected driver)
3. `GUI_Paint.c`, `GUI_BMPfile.c`
4. All `Fonts/*.c` files
5. `EPD_<model>_test.c`, `main.c`, `ImageData.c`

Output: a single `epd` executable.

**Compiler flags:** `-g -O -ffunction-sections -fdata-sections -Wall`
**Linker flags:** `-Wl,--gc-sections` + platform library (`-llgpio`, `-lbcm2835`, etc.)

---

## 9. Assessment for Ruby C Extension Integration

### 9.1 What We Can Use Directly

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
|                |         | Ruby. See Section 9.3 for rationale.                     |
| GUI_BMPfile    | No      | File I/O should be handled in Ruby, not C.               |
| Fonts          | No      | Hard-coded bitmaps. Replace with FreeType or similar.    |
| Debug.h        | Yes     | Redirect to Ruby `rb_warn()` instead of `printf`.        |

### 9.2 What Needs Wrapping / Replacing

**Must Replace:**
- **Global PAINT state** -- the `PAINT Paint` global conflates pixel storage, coordinate
  transforms, and drawing context. Replace with a C-backed `Framebuffer` struct (owns buffer
  + pixel format metadata) wrapped via `TypedData_Wrap_Struct`. Coordinate transforms and
  drawing move to Ruby entirely (see Section 9.3).
- **printf-based debug** -- redirect `Debug()` macro to `rb_warn()` or a configurable logger.
- **DEV_Module_Init / Exit** -- wrap in a Ruby `ChromaWave::Device` lifecycle object with
  proper `dfree` cleanup. Consider `Ensure`-style block patterns.
- **malloc for image buffers** -- allocate via `xmalloc` / `xfree` (Ruby's tracked allocator)
  so Ruby's GC tracks the memory pressure.
- **Duplicated I/O primitives** -- `Reset()`, `SendCommand()`, `SendData()`, `ReadBusy()`
  are copy-pasted identically across all 70 driver files (~1,400 lines of duplication). These
  belong on the Device layer as shared functions, parameterized by busy polarity and reset
  timing.

**Must Abstract:**
- **Model selection** -- the vendor library is compile-time-selected. We compile all drivers
  and select at runtime via a two-tier registry (config data + optional code overrides).
  Total code size of all 70 drivers is modest (~500KB compiled). See Section 9.4.
- **Platform selection** -- similarly compile-time. For the gem, we should:
  - Default to `USE_LGPIO_LIB` for RPi 5 / modern Raspberry Pi OS
  - Allow `USE_DEV_LIB` as fallback (gpiod, most portable)
  - Detect platform in `extconf.rb` and set appropriate `-D` flags
  - Define a `MOCK` backend for development/testing on non-RPi systems

### 9.3 Responsibility Split: Ruby vs C

A critical design decision is where to draw the line between C and Ruby. The guiding principle:
**C handles hardware I/O and bit-level buffer manipulation. Ruby handles everything else.**

#### 9.3.1 Why Drawing Belongs in Ruby

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
worst case (filling every pixel on an 800x480 display = ~384K Ruby→C FFI calls for `set_pixel`)
completes well under a second.

**By keeping drawing in Ruby, we gain:**
- Extensibility (anti-aliasing, compositing, alpha) without touching C
- Testability (no hardware needed to test drawing logic)
- Ecosystem integration (ChunkyPNG, Vips, FreeType interop at the Ruby level)
- No need to fork/maintain a modified GUI_Paint.c

#### 9.3.2 Responsibility Matrix

| Concern                    | Layer | Rationale                                    |
|----------------------------|-------|----------------------------------------------|
| GPIO/SPI lifecycle         | C     | Hardware handles, platform-specific           |
| SPI command/data protocol  | C     | Bit-level timing, CS/DC pin toggling          |
| Display init/sleep/refresh | C     | Register sequences, busy-wait, GVL release    |
| Pixel packing into buffer  | C     | Bit-twiddling (MSB bitmask, nibble packing)   |
| Buffer allocation/free     | C     | `xmalloc`/`xfree` with `TypedData` lifecycle  |
| Bulk buffer clear/fill     | C     | Format-aware memset, faster than per-pixel    |
| Coordinate transforms      | Ruby  | Rotation/mirror matrix math, no hardware      |
| Drawing primitives         | Ruby  | Bresenham algorithms, calls C `set_pixel`     |
| Text rendering             | Ruby  | FreeType or pre-rendered, not bitmap fonts    |
| Image loading/conversion   | Ruby  | ChunkyPNG/Vips, quantize to display palette   |
| Color space conversion     | Ruby  | RGB→display palette mapping, dithering        |
| Display capability queries | Ruby  | `respond_to?` / module inclusion checks       |
| Model configuration        | Ruby  | Resolution, format, capabilities per model    |

### 9.4 Integration Architecture

#### 9.4.1 The `PixelFormat` Unifying Concept

The vendor library's `Scale` value, the color constants, and the buffer size math all express
the same underlying concept: **how pixels are packed into bytes**. This concept appears in at
least four places in the original design (Image buffer, Display config, Color validation,
driver registry). It should be modeled once.

```ruby
module ChromaWave
  class PixelFormat
    attr_reader :name, :bits_per_pixel, :pixels_per_byte, :scale, :palette

    MONO   = new(name: :mono,   bpp: 1, scale: 2,  palette: %i[black white])
    GRAY4  = new(name: :gray4,  bpp: 2, scale: 4,  palette: %i[black dark_gray light_gray white])
    COLOR4 = new(name: :color4, bpp: 4, scale: 6,  palette: %i[black white yellow red])
    COLOR7 = new(name: :color7, bpp: 4, scale: 7,
                 palette: %i[black white green blue red yellow orange])

    def buffer_size(width, height)
      bytes_per_row = (width + pixels_per_byte - 1) / pixels_per_byte
      bytes_per_row * height
    end

    def valid_color?(color) = palette.include?(color)
  end
end
```

Both `Display` and `Framebuffer` reference a `PixelFormat`. The Display declares what format it
requires. The Framebuffer declares what format it contains. Compatibility is checked once at
the point of use (`display.show(framebuffer)`), not scattered across layers.

**Dual-buffer displays** (black + red/yellow) are modeled as two Framebuffers, both `MONO`
format, not as a special pixel format. The Display's capability module knows it needs two
buffers.

#### 9.4.2 Directory Structure

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
  vendor/                             # Vendored C sources (copied from vendor/waveshare_epd)
    config/                           #   DEV_Config.c, platform backends (as-is)
    drivers/                          #   All EPD_*.c files -- compiled unconditionally.
    |                                 #   Boilerplate (Reset/SendCommand/SendData/ReadBusy)
    |                                 #   is stripped; these files provide only Init register
    |                                 #   sequences, LUT tables, and model-specific Display
    |                                 #   logic for complex models.

lib/chroma_wave/                    # Ruby -- everything that doesn't need to be C
  chroma_wave.rb                      # Top-level require, autoloads
  version.rb                          # VERSION constant
  pixel_format.rb                     # PixelFormat value object (MONO, GRAY4, COLOR7, etc.)
  framebuffer.rb                      # Ruby wrapper for C-backed Framebuffer
  canvas.rb                           # Drawing primitives + coordinate transforms
  transform.rb                        # Rotation, mirroring, coordinate mapping
  device.rb                           # Hardware lifecycle, connection management
  display.rb                          # Base Display class (init, clear, show, sleep)
  capabilities/                       # Composable capability modules
    partial_refresh.rb                #   display_partial, display_base
    fast_refresh.rb                   #   init_fast, display_fast
    grayscale_mode.rb                 #   init_grayscale, display_grayscale
    dual_buffer.rb                    #   show(black_fb, red_fb)
    regional_refresh.rb               #   display_region(fb, x, y, w, h)
  models/                             # One file per model family, not per SKU
    mono.rb                           #   Simple monochrome (2in13_V4, 13in3k, etc.)
    dual_color.rb                     #   B+R / B+Y displays (2in13b_V4, 4in2bc, etc.)
    grayscale.rb                      #   4-gray displays (1in64g, 3in7, etc.)
    multicolor.rb                     #   7-color ACeP displays (5in65f, 4in01f, etc.)
```

#### 9.4.3 Capabilities as Composable Modules

The vendor drivers expose capabilities as inconsistently-named optional functions
(`Init_Fast`, `Display_Partial`, `Display_Part`, `Display_part`). Rather than modeling these
as nullable function pointers in a flat C struct, use Ruby modules:

```ruby
module ChromaWave
  module Capabilities
    module PartialRefresh
      def display_partial(framebuffer)
        # Validates framebuffer format, calls C: epd_display_partial(driver, buf)
      end

      def display_base(framebuffer)
        # Write base frame for subsequent partials
      end
    end

    module FastRefresh
      def init_fast  = ... # C: epd_init_fast(driver)
      def display_fast(framebuffer) = ...
    end

    module GrayscaleMode
      def init_grayscale = ...
      def display_grayscale(framebuffer) = ...
    end

    module DualBuffer
      def show(black_framebuffer, red_framebuffer)
        # Validates both are MONO format, calls C: epd_display_dual(driver, black, red)
      end
    end
  end

  # Each model class includes only its supported capabilities
  class EPD_2in13_V4 < Display
    include Capabilities::PartialRefresh
    include Capabilities::FastRefresh
    # Inherits base: init, clear, show, sleep
  end

  class EPD_2in13b_V4 < Display
    include Capabilities::DualBuffer
    # Full refresh only, dual-buffer
  end
end
```

**Advantages over nullable function pointers:**
- Shared behavior is defined once per capability, reused across all models that support it
- `display.respond_to?(:display_partial)` works naturally for capability checking
- `display.is_a?(Capabilities::FastRefresh)` for type-based dispatch
- New capabilities are added without changing existing code (Open/Closed Principle)
- Documentation and tests live with each capability module

#### 9.4.4 Two-Tier Driver Registry

Analysis of all 70 driver files reveals that **60-70% of driver code is identical boilerplate**:
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
| LUT waveform tables     | Data     | Yes -- raw byte arrays |
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

**Impact:** Adding support for a new simple display model is adding ~10 lines of config data
rather than writing a new C file.

#### 9.4.5 Device Owns I/O Primitives

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
the timeout/interruptibility improvement (see Section 9.5.3) in one place.

#### 9.4.6 Framebuffer: Pixel Storage Without Drawing

The vendor's `PAINT` struct conflates pixel storage, coordinate transforms, and drawing state
into a single global. In our design, these are three separate concerns:

```
Framebuffer (C-backed, TypedData)
  ├── Owns: raw byte buffer (xmalloc'd)
  ├── Knows: width, height, PixelFormat
  ├── Methods: set_pixel, get_pixel, clear, buffer_bytes, buffer_size
  └── No drawing, no transforms, no global state

Canvas (Ruby)
  ├── Wraps: a Framebuffer + a Transform
  ├── Methods: draw_line, draw_rect, draw_circle, draw_text, ...
  └── Delegates pixel writes to Framebuffer#set_pixel after transform

Transform (Ruby value object)
  ├── Knows: rotation (0/90/180/270), mirror mode, logical dimensions
  └── Method: apply(x, y) → [physical_x, physical_y]
```

The Framebuffer's C implementation extracts only the pixel-packing logic from `GUI_Paint.c`
(~100 lines: the `Scale`-dependent bit-twiddling in `Paint_SetPixel` and `Paint_Clear`).
No forking of GUI_Paint.c is needed. The drawing primitives are reimplemented in Ruby where
they can be tested, extended, and composed with Ruby's image processing ecosystem.

### 9.5 Critical Integration Challenges

#### 9.5.1 Platform Detection in `extconf.rb`

Need to:
- Check for `lgpio.h`, `bcm2835.h`, `wiringPi.h`, `gpiod.h` headers
- Check for corresponding `-l` libraries
- Auto-select the best available backend
- Provide a `--with-epd-backend=` configure option for override
- Define a `MOCK` backend for test environments (no hardware)

#### 9.5.2 Buffer Ownership and GC Integration

Framebuffers own pixel data allocated via `xmalloc`/`xfree` (Ruby's tracked allocator).
Wrapped with `TypedData_Wrap_Struct` with:
- `dfree`: calls `xfree` on the pixel buffer
- `dsize`: reports `buffer_size` bytes to Ruby's GC for memory pressure tracking
- `dmark`: not needed (no `VALUE`s stored in the C struct)
- `flags`: `RUBY_TYPED_FREE_IMMEDIATELY` (no GVL needed for `xfree`)

#### 9.5.3 Busy-Wait Blocking and GVL Release

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

#### 9.5.4 EPD_7in5_V2 Destructive Buffer Inversion

`EPD_7IN5_V2_Display()` modifies the caller's buffer in-place (bitwise NOT) before sending
over SPI. This is a bug in the vendor code (violates the implied const contract). Our display
layer must either:
- **(A)** Copy the buffer before passing to the driver, or
- **(B)** Have the Framebuffer support an "inverted" flag and apply inversion during
  `buffer_bytes` export rather than modifying the source

**(A) is simpler** and the copy cost is negligible (800x480/8 = 48KB, microseconds to copy).

### 9.6 What We Should NOT Use

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

## 10. Driver Variation Analysis

Examination of 8 representative drivers across all categories reveals how much of the vendor
code is truly unique vs duplicated boilerplate. This informs the hybrid data+code registry
design described in Section 9.4.4.

### 10.1 Identical Boilerplate (Present in All 70 Drivers)

Every driver file contains `static` copies of these four functions with identical bodies:

```c
static void EPD_<model>_Reset(void)        // DEV_Digital_Write RST pin sequence
static void EPD_<model>_SendCommand(UBYTE)  // DC=0, CS=0, SPI write, CS=1
static void EPD_<model>_SendData(UBYTE)     // DC=1, CS=0, SPI write, CS=1
void EPD_<model>_ReadBusy(void)             // Spin-wait on BUSY pin
```

`SendCommand` and `SendData` are byte-for-byte identical across all 70 files.
`Reset` varies only in timing (`{20,2,20}` ms for most, `{200,2,200}` for EPD_5in65f,
`{100,2,100}` for EPD_13in3k, `{30,3,30}` for EPD_3in7).
`ReadBusy` varies only in polarity (wait for HIGH vs wait for LOW).

### 10.2 What Actually Varies Per Driver

| Driver          | LOC | Init Pattern      | Display Pattern     | Unique Logic?  |
|-----------------|-----|-------------------|---------------------|----------------|
| EPD_2in13_V4    | 370 | cmd/data sequence | cmd 0x24 + byte loop | No             |
| EPD_2in13b_V4   | 228 | cmd/data sequence | 0x24 + 0x26 dual buf | No             |
| EPD_13in3k      | 549 | cmd/data sequence | cmd 0x24 + byte loop | No             |
| EPD_4in2        | 767 | cmd/data + **5 LUT tables** | std mono     | **Yes** (LUT selection) |
| EPD_3in7        | 641 | cmd/data + **LUT load**     | std + **4-gray repack** | **Yes** (mode logic) |
| EPD_7in5_V2     | 466 | cmd/data + power  | **inverts buffer in-place** | **Yes** (destructive) |
| EPD_1in64g      | 231 | cmd/data sequence | 4-bit nibble pairs  | No (format only) |
| EPD_5in65f      | 242 | cmd/data sequence | **power on/off per refresh** | **Yes** (lifecycle) |

**Findings:** Of 8 drivers examined, 4 can be fully described as config data. The other 4 need
custom code for specific operations but still share 60%+ of their logic with the generic path.

### 10.3 Reset Timing Variation

| Category          | Timing (pre/low/post ms) | Models                          |
|-------------------|--------------------------|----------------------------------|
| Standard          | 20 / 2 / 20             | Most mono, dual-buffer models    |
| Large display     | 100 / 2 / 100           | EPD_13in3k                       |
| Color display     | 200 / 2 / 200           | EPD_5in65f                       |
| Medium variant    | 30 / 3 / 30             | EPD_3in7                         |

### 10.4 Busy-Wait Polarity

| Polarity                              | Models                                    |
|---------------------------------------|-------------------------------------------|
| Active-LOW (0=busy, wait for HIGH)    | EPD_2in13_V4, EPD_2in13b_V4, EPD_13in3k  |
| Active-HIGH (1=busy, wait for LOW)    | EPD_7in5_V2, EPD_1in64g, EPD_3in7        |
| Both (separate BusyHigh/BusyLow)      | EPD_5in65f                                |

No universal standard -- polarity is determined by the display controller IC.

### 10.5 Init Sequence Structure

All Init functions follow the same structural pattern regardless of complexity:

```
Reset() → ReadBusy() → [SendCommand(cmd) → SendData(d0) → SendData(d1) → ...] × N → ReadBusy()
```

The sequences differ only in which commands/data bytes are sent and in what order. This is
directly expressible as a byte array: `{cmd, n_bytes, byte0, byte1, ..., cmd, n_bytes, ...}`.

Exception: models with LUT tables (EPD_4in2, EPD_3in7) have **multiple** init sequences
selected at runtime based on display mode (full refresh, partial, 4-gray). These need the
Tier 2 code override.

---

## 11. Vendor Code Quality Assessment

### 11.1 Strengths

- **Clean layer separation.** HAL, driver, drawing, and application layers are well-isolated.
- **Consistent driver structure.** Despite naming inconsistencies, every driver follows the same
  pattern: Reset -> SendCommand/SendData -> ReadBusy -> SetWindows/SetCursor.
- **No dynamic allocation.** The library never calls malloc internally. Buffer ownership is clear.
- **MIT license.** No licensing complications for vendoring into a gem.

### 11.2 Weaknesses

- **Massive code duplication.** Every EPD_*.c file re-implements `Reset()`, `SendCommand()`,
  `SendData()`, `ReadBusy()` as `static` functions with identical bodies (except busy polarity).
  ~1,400 lines of pure duplication across 70 files.
- **Inconsistent naming.** Mixed case (`EPD_2in13_V4` vs `EPD_2IN13B_V4`), inconsistent method
  names (`Clear_Black` vs `ClearBlack`), inconsistent return types (`void` vs `UBYTE`).
- **Global state everywhere.** `PAINT Paint`, GPIO pin globals, `#ifdef` platform selection.
- **No error handling.** Functions don't return error codes. SPI failures are silent. The only
  error path is `DEV_Module_Init()` returning 1.
- **Busy-wait with no timeout.** `ReadBusy()` loops forever if the display hangs.
- **`UDOUBLE` is `uint32_t`, not `double`.** Confusing typedef name.
- **DEV_SPI_SendnData uses sizeof(pointer).** Bug on line 316 of DEV_Config.c:
  `size = sizeof(Reg)` where `Reg` is `UBYTE*` -- this always gives 4 or 8, not the array length.
- **EPD_7IN5_V2_Display inverts the caller's buffer in-place.** The API implies const-correctness
  but destructively modifies the input. This is a data-corruption bug if the caller reuses the
  buffer.

### 11.3 Code Size Estimate

| Component           | Files | ~Lines of C | After DRY Refactor |
|---------------------|-------|-------------|-------------------|
| DEV_Config + backends| ~8   | ~1,200      | ~1,200 (as-is)   |
| EPD_*.c drivers     | ~70   | ~25,000     | ~8,000 (data tables + ~20 custom) |
| GUI_Paint + BMPfile | 2     | ~1,200      | ~100 (pixel packing only) |
| Fonts               | 7     | ~15,000     | 0 (not vendored)  |
| **Total vendored**  | ~87   | ~42,400     | **~9,300**        |

The refactored C footprint is roughly **22% of the original**, with the rest replaced by
Ruby code or eliminated as duplication.

---

## 12. Recommended Integration Strategy Summary

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
