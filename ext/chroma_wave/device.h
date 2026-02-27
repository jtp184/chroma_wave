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

/* Global cancel flag: set by display_without_gvl, checked by epd_read_busy */
extern volatile int *epd_cancel_flag;

/* Device state enum */
typedef enum { DEVICE_CLOSED = 0, DEVICE_OPEN = 1 } device_state_t;

/* Device wrapper: holds config, driver, and HAL lifecycle state */
typedef struct {
    const epd_model_config_t *config;  /* pointer into static configs (not owned) */
    const epd_driver_t       *driver;  /* pointer into static drivers (nullable, not owned) */
    device_state_t            state;
    volatile int              cancel;  /* UBF cancellation flag for WS5 */
} device_t;

extern VALUE rb_cDevice;
extern const rb_data_type_t device_type;
void Init_device(void);

#endif /* DEVICE_H */
