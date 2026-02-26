#ifndef DEVICE_H
#define DEVICE_H

#include "chroma_wave.h"

/* Forward declare the config struct */
typedef struct epd_model_config epd_model_config_t;

/* Shared I/O primitives */
void epd_reset(const epd_model_config_t *cfg);
void epd_send_command(uint8_t cmd);
void epd_send_data(uint8_t data);
void epd_send_data_bulk(const uint8_t *data, size_t len);
int  epd_read_busy(const epd_model_config_t *cfg, uint32_t timeout_ms);
int  epd_wait_busy_high(const epd_model_config_t *cfg, uint32_t timeout_ms);
int  epd_wait_busy_low(const epd_model_config_t *cfg, uint32_t timeout_ms);

#endif /* DEVICE_H */
