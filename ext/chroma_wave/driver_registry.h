#ifndef DRIVER_REGISTRY_H
#define DRIVER_REGISTRY_H

#include "chroma_wave.h"

/* Default busy-wait timeout (ms) used by generic init */
#define EPD_BUSY_TIMEOUT_MS 5000

/* Model config struct -- layout must match driver_configs_generated.h */
typedef struct epd_model_config {
    const char     *name;
    uint16_t        width, height;
    pixel_format_t  pixel_format;
    busy_polarity_t busy_polarity;
    uint16_t        reset_ms[3];       /* {pre_high, low, post_high} */
    uint8_t         display_cmd;       /* primary: 0x24 or 0x10 */
    uint8_t         display_cmd_2;     /* secondary: 0x26 or 0x13 or 0x00 */
    const uint8_t  *init_sequence;
    uint16_t        init_sequence_len;
    uint32_t        capabilities;      /* EPD_CAP_* bitfield */
    const uint8_t  *init_fast_sequence;
    uint16_t        init_fast_sequence_len;
    const uint8_t  *init_partial_sequence;
    uint16_t        init_partial_sequence_len;
    uint8_t         sleep_cmd;
    uint8_t         sleep_data;
} epd_model_config_t;

/* Tier 2 driver: per-model function overrides */
typedef struct epd_driver {
    const epd_model_config_t *config;
    int  (*custom_init)(const epd_model_config_t *cfg, uint8_t mode);
    int  (*custom_display)(const epd_model_config_t *cfg,
                           const uint8_t *buf, size_t len);
    void (*pre_display)(const epd_model_config_t *cfg);
    void (*post_display)(const epd_model_config_t *cfg);
} epd_driver_t;

/* Generic (Tier 1) operations -- interpret init sequences */
int  epd_generic_init(const epd_model_config_t *cfg, uint8_t mode);
int  epd_generic_display(const epd_model_config_t *cfg,
                         const uint8_t *buf, size_t len);
void epd_generic_sleep(const epd_model_config_t *cfg);

/* Registry lookup */
const epd_model_config_t *epd_find_config(const char *name);
const epd_driver_t       *epd_find_driver(const char *name);
size_t                     epd_model_count(void);
const epd_model_config_t *epd_model_at(size_t index);

/* Ruby init */
void Init_driver_registry(void);

#endif /* DRIVER_REGISTRY_H */
