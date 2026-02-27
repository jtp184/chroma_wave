#ifndef CHROMA_WAVE_H
#define CHROMA_WAVE_H

#include "ruby.h"
#include <stdint.h>
#include <string.h>

/* Pixel format enum */
typedef enum {
    PIXEL_FORMAT_MONO   = 1,  /* 1bpp, 8 pixels/byte */
    PIXEL_FORMAT_GRAY4  = 2,  /* 2bpp, 4 pixels/byte */
    PIXEL_FORMAT_COLOR4 = 3,  /* 4bpp, 2 pixels/byte (tri-color) */
    PIXEL_FORMAT_COLOR7 = 4   /* 4bpp, 2 pixels/byte (7-color ACeP) */
} pixel_format_t;

/* Busy pin polarity */
typedef enum {
    BUSY_ACTIVE_LOW  = 0,  /* Busy when pin reads LOW (SSD1680 family) */
    BUSY_ACTIVE_HIGH = 1   /* Busy when pin reads HIGH (UC8179 family) */
} busy_polarity_t;

/* Capability bitfield flags */
#define EPD_CAP_PARTIAL    (1 << 0)
#define EPD_CAP_FAST       (1 << 1)
#define EPD_CAP_GRAYSCALE  (1 << 2)
#define EPD_CAP_DUAL_BUF   (1 << 3)
#define EPD_CAP_REGIONAL   (1 << 4)

/* Init mode constants */
#define EPD_MODE_FULL      0
#define EPD_MODE_FAST      1
#define EPD_MODE_PARTIAL   2
#define EPD_MODE_GRAYSCALE 3

/* Maximum framebuffer dimension (width or height) */
#define EPD_MAX_DIMENSION 4096

/* Error codes for C-level functions */
#define EPD_OK            0
#define EPD_ERR_TIMEOUT  -1
#define EPD_ERR_INIT     -2
#define EPD_ERR_PARAM    -3

/* Init sequence sentinel opcodes (0xF0-0xFF range).
 * SEQ_DELAY_MS takes a single uint8_t argument (max 255ms per opcode).
 * Delays >255ms require multiple consecutive SEQ_DELAY_MS opcodes. */
#define SEQ_SET_CURSOR   0xF9
#define SEQ_SET_WINDOW   0xFA
#define SEQ_SW_RESET     0xFB
#define SEQ_HW_RESET     0xFC
#define SEQ_DELAY_MS     0xFD
#define SEQ_END          0xFE
#define SEQ_WAIT_BUSY    0xFF

/* Module and class VALUE externs */
extern VALUE rb_mChromaWave;
extern VALUE rb_mChromaWaveNative;
extern VALUE rb_cFramebuffer;
extern VALUE rb_cCanvas;
extern VALUE rb_cDevice;
extern VALUE rb_eChromaWaveError;
extern VALUE rb_eDeviceError;
extern VALUE rb_eInitError;
extern VALUE rb_eBusyTimeoutError;
extern VALUE rb_eSPIError;
extern VALUE rb_eDependencyError;
extern VALUE rb_eFormatMismatchError;
extern VALUE rb_eModelNotFoundError;

/* Shared pixel format helpers */
pixel_format_t cw_sym_to_pixel_format(VALUE sym);
VALUE          cw_pixel_format_to_sym(pixel_format_t fmt);

/* Init functions for sub-modules */
void Init_framebuffer(void);
void Init_driver_registry(void);
void Init_canvas(void);
void Init_device(void);

#endif /* CHROMA_WAVE_H */
