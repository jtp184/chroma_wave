#ifndef DRIVER_REGISTRY_H
#define DRIVER_REGISTRY_H

#include "chroma_wave.h"

/* Model config struct - full definition needed by device.c */
struct epd_model_config {
    const char    *name;           /* e.g. "2in13_V4" */
    uint16_t       width;
    uint16_t       height;
    pixel_format_t pixel_format;
    busy_polarity_t busy_polarity;
    uint32_t       busy_timeout_ms;
    uint32_t       capabilities;   /* EPD_CAP_* bitfield */
    uint16_t       reset_ms[3];    /* delays: pre-low, low, post-low */
    const uint8_t *init_seq_full;  /* init sequence for full refresh */
    const uint8_t *init_seq_fast;  /* init sequence for fast refresh (may be NULL) */
    const uint8_t *init_seq_partial; /* init sequence for partial refresh (may be NULL) */
};

void Init_driver_registry(void);

#endif /* DRIVER_REGISTRY_H */
