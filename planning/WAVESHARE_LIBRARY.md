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
| EPD_*.c drivers| Yes     | Include per-model as separate compilation units.         |
| GUI_Paint      | Partial | Pixel packing logic is essential. Drawing primitives are |
|                |         | useful for basic shapes. Font system is limited.         |
| GUI_BMPfile    | No      | File I/O should be handled in Ruby, not C.               |
| Fonts          | No      | Hard-coded bitmaps. Replace with FreeType or similar.    |
| Debug.h        | Yes     | Redirect to Ruby `rb_warn()` instead of `printf`.        |

### 9.2 What Needs Wrapping / Replacing

**Must Replace:**
- **Global PAINT state** -- wrap in a Ruby object with `TypedData_Wrap_Struct`. Each
  `ChromaWave::Image` should own its own buffer and PAINT-equivalent metadata.
- **printf-based debug** -- redirect `Debug()` macro to `rb_warn()` or a configurable logger.
- **DEV_Module_Init / Exit** -- wrap in a Ruby `ChromaWave::Device` lifecycle object with
  proper `dfree` cleanup. Consider `Ensure`-style block patterns.
- **malloc for image buffers** -- allocate via `xmalloc` / `xfree` (Ruby's tracked allocator)
  or `ruby_xmalloc` for GC visibility.

**Must Abstract:**
- **Model selection** -- the vendor library is compile-time-selected. We need either:
  - **(A) Compile all drivers, select at runtime via function pointers**, or
  - **(B) Compile each driver as a separate shared object, load dynamically**
  - **(A) is strongly preferred** -- simpler, no dlopen complexity, and the total code size of
    all 70 drivers is modest (~500KB compiled).
- **Platform selection** -- similarly compile-time. For the gem, we should:
  - Default to `USE_LGPIO_LIB` for RPi 5 / modern Raspberry Pi OS
  - Allow `USE_DEV_LIB` as fallback (gpiod, most portable)
  - Detect platform in `extconf.rb` and set appropriate `-D` flags
  - Consider a "mock" backend for development/testing on non-RPi systems

### 9.3 Integration Architecture Recommendation

```
ChromaWave (Ruby gem)
  |
  +-- lib/chroma_wave/
  |     device.rb          # ChromaWave::Device -- lifecycle, model selection
  |     display.rb         # ChromaWave::Display -- model-specific config
  |     image.rb           # ChromaWave::Image -- pixel buffer + drawing
  |     color.rb           # ChromaWave::Color -- color spaces, conversion
  |     version.rb
  |
  +-- ext/chroma_wave/
        chroma_wave.c      # Init_chroma_wave: define module, classes
        device.c            # Device alloc/init/free, wraps DEV_Config lifecycle
        display.c           # Display init/clear/refresh/sleep, wraps EPD_* drivers
        image.c             # Image buffer alloc/draw/pixel-pack, wraps GUI_Paint
        display_registry.c  # Runtime model dispatch table (function pointers)
        |
        +-- vendor/         # Vendored C sources (symlinked or copied)
              config/       # DEV_Config.c, platform backends
              drivers/      # All EPD_*.c files, compiled unconditionally
              paint/        # GUI_Paint.c (modified: no global state)
```

### 9.4 Critical Integration Challenges

1. **Eliminating global state.** `PAINT Paint` is a global. Every `Paint_*` function reads it.
   Options:
   - **(A) Fork GUI_Paint.c** and rewrite all functions to take a `PAINT*` parameter.
     This is the cleanest approach and not difficult -- the functions are simple.
   - **(B) Protect the global with a mutex** and swap it before each call. Fragile, not
     thread-safe for multiple images.
   - **Recommendation: (A).** The GUI_Paint code is ~850 lines and straightforward. Forking
     and parameterizing it is a one-time cost that pays for itself in correctness.

2. **Runtime model dispatch.** Each driver has a different function signature set. We need a
   unified interface:
   ```c
   typedef struct {
       const char *name;
       UWORD width;
       UWORD height;
       UBYTE color_type;     // MONO, GRAY4, DUAL_BW_RED, COLOR7, etc.
       UBYTE scale;          // Paint scale value for this display
       void (*init)(void);
       void (*init_fast)(void);    // NULL if not supported
       void (*clear)(void);
       void (*display)(UBYTE *buf);
       void (*display_fast)(UBYTE *buf);       // NULL if not supported
       void (*display_partial)(UBYTE *buf);    // NULL if not supported
       void (*display_dual)(UBYTE *black, UBYTE *red);  // NULL if single-buf
       void (*sleep)(void);
   } epd_driver_t;
   ```
   Then build a registry array indexed by model enum. This unifies the API across all 70 drivers.

3. **Platform detection in extconf.rb.** Need to:
   - Check for `lgpio.h`, `bcm2835.h`, `wiringPi.h`, `gpiod.h` headers
   - Check for corresponding `-l` libraries
   - Auto-select the best available backend
   - Provide a `--with-epd-backend=` configure option for override
   - Define a `MOCK` backend for test environments (no hardware)

4. **Busy-wait blocking.** `EPD_*_ReadBusy()` spin-waits. This blocks the GVL. For the Ruby
   extension, wrap display/refresh operations with `rb_thread_call_without_gvl()` so other
   Ruby threads can run during the (potentially multi-second) refresh cycle.

5. **Buffer ownership.** The vendor library expects callers to `malloc` and `free` their own
   buffers. In the Ruby extension, buffers should be owned by a `TypedData_Wrap_Struct` object
   with proper `dfree`, `dmark`, and `dsize` callbacks. Use `xmalloc`/`xfree` so Ruby's GC
   tracks the memory.

### 9.5 What We Should NOT Use

- **GUI_BMPfile.c** -- BMP loading should happen in Ruby (or via a Ruby image library like
  ChunkyPNG, MiniMagick, or Vips). The C BMP loader is limited to 24-bit uncompressed BMP only.
- **Font bitmap tables** -- The built-in fonts are tiny (5x8 to 17x24) fixed-width bitmaps with
  only ASCII + limited GB2312. Replace with FreeType for proper text rendering, or handle text
  rendering entirely in Ruby and pass pre-rendered pixel buffers to C.
- **examples/** -- Test programs are useful as reference but should not be compiled into the gem.
- **Makefile** -- We'll use `extconf.rb` + `mkmf` instead.

---

## 10. Patterns and Code Quality Assessment

### 10.1 Strengths

- **Clean separation of concerns.** HAL, driver, drawing, and application layers are well-isolated.
- **Consistent driver structure.** Despite naming inconsistencies, every driver follows the same
  pattern: Reset -> SendCommand/SendData -> ReadBusy -> SetWindows/SetCursor.
- **No dynamic allocation.** The library never calls malloc internally. Buffer ownership is clear.
- **MIT license.** No licensing complications for vendoring into a gem.

### 10.2 Weaknesses

- **Massive code duplication.** Every EPD_*.c file re-implements `Reset()`, `SendCommand()`,
  `SendData()`, `ReadBusy()` as `static` functions with identical bodies (except busy polarity).
  These could be factored into shared helpers.
- **Inconsistent naming.** Mixed case (`EPD_2in13_V4` vs `EPD_2IN13B_V4`), inconsistent method
  names (`Clear_Black` vs `ClearBlack`), inconsistent return types (`void` vs `UBYTE`).
- **Global state everywhere.** `PAINT Paint`, GPIO pin globals, `#ifdef` platform selection.
- **No error handling.** Functions don't return error codes. SPI failures are silent. The only
  error path is `DEV_Module_Init()` returning 1.
- **Busy-wait with no timeout.** `ReadBusy()` loops forever if the display hangs.
- **`UDOUBLE` is `uint32_t`, not `double`.** Confusing typedef name.
- **DEV_SPI_SendnData uses sizeof(pointer).** Bug on line 316 of DEV_Config.c:
  `size = sizeof(Reg)` where `Reg` is `UBYTE*` -- this always gives 4 or 8, not the array length.

### 10.3 Code Size Estimate

| Component           | Files | ~Lines of C |
|---------------------|-------|-------------|
| DEV_Config + backends| ~8   | ~1,200      |
| EPD_*.c drivers     | ~70   | ~25,000     |
| GUI_Paint + BMPfile | 2     | ~1,200      |
| Fonts               | 7     | ~15,000     |
| **Total**           | ~87   | ~42,400     |

Most of the line count is in font bitmap tables and repetitive driver register sequences.

---

## 11. Recommended Integration Strategy Summary

1. **Vendor the C sources** into `ext/chroma_wave/vendor/` (copy, not symlink).
2. **Fork GUI_Paint.c** to eliminate global state. Parameterize all functions with `PAINT*`.
3. **Build a driver registry** (`display_registry.c`) with function pointers for runtime dispatch.
4. **Compile all drivers unconditionally** -- total binary size increase is negligible.
5. **Detect platform in extconf.rb**, set `-D` flags for the appropriate GPIO/SPI backend.
6. **Add a mock backend** for development and CI testing without hardware.
7. **Release the GVL** during display refresh operations.
8. **Handle image data in Ruby** -- use ChunkyPNG or Vips for image loading/manipulation,
   pass raw pixel buffers to C for display.
9. **Replace the font system** with FreeType or Ruby-side text rendering.
10. **Add timeout to busy-wait** with an interruptible loop and configurable max duration.
