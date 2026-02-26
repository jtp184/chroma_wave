#ifndef FRAMEBUFFER_H
#define FRAMEBUFFER_H

#include "chroma_wave.h"

typedef struct {
    uint8_t       *buffer;
    uint16_t       width;
    uint16_t       height;
    pixel_format_t pixel_format;
    uint16_t       width_byte;   /* bytes per row */
    size_t         buffer_size;  /* width_byte * height */
} framebuffer_t;

void Init_framebuffer(void);

#endif /* FRAMEBUFFER_H */
