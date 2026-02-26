#ifndef DEVICE_H
#define DEVICE_H

#include "driver_registry.h"

/* Shared I/O primitives */
void epd_reset(const epd_model_config_t *cfg);
void epd_send_command(uint8_t cmd);
void epd_send_data(uint8_t data);
void epd_send_data_bulk(const uint8_t *data, size_t len);
int  epd_read_busy(busy_polarity_t polarity, uint32_t timeout_ms);
int  epd_wait_busy_high(uint32_t timeout_ms);
int  epd_wait_busy_low(uint32_t timeout_ms);

#endif /* DEVICE_H */
