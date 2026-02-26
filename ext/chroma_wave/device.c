#include "device.h"
#include "driver_registry.h"
#include "mock_hal.h"

/* ---- Hardware reset sequence ---- */
void
epd_reset(const epd_model_config_t *cfg)
{
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(cfg->reset_ms[0]);
    DEV_Digital_Write(EPD_RST_PIN, 0);
    DEV_Delay_ms(cfg->reset_ms[1]);
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(cfg->reset_ms[2]);
}

/* ---- SPI command/data ---- */
void
epd_send_command(uint8_t cmd)
{
    DEV_Digital_Write(EPD_DC_PIN, 0);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(cmd);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

void
epd_send_data(uint8_t data)
{
    DEV_Digital_Write(EPD_DC_PIN, 1);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(data);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

void
epd_send_data_bulk(const uint8_t *data, size_t len)
{
    DEV_Digital_Write(EPD_DC_PIN, 1);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    /* Cast away const: vendor API doesn't take const but won't modify data */
    DEV_SPI_Write_nByte((uint8_t *)data, (uint32_t)len);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

/* ---- Busy-wait polling ---- */
int
epd_read_busy(const epd_model_config_t *cfg, uint32_t timeout_ms)
{
    uint32_t i;
    uint8_t  pin_val;

    for (i = 0; i < timeout_ms; i++) {
        pin_val = DEV_Digital_Read(EPD_BUSY_PIN);

        if (cfg->busy_polarity == BUSY_ACTIVE_HIGH) {
            /* Busy while HIGH, done when LOW */
            if (pin_val == 0) return EPD_OK;
        } else {
            /* Busy while LOW, done when HIGH */
            if (pin_val == 1) return EPD_OK;
        }

        DEV_Delay_ms(1);
    }

    return EPD_ERR_TIMEOUT;
}

int
epd_wait_busy_high(const epd_model_config_t *cfg, uint32_t timeout_ms)
{
    /* Create a temporary config with HIGH polarity */
    epd_model_config_t tmp = *cfg;
    tmp.busy_polarity = BUSY_ACTIVE_HIGH;
    return epd_read_busy(&tmp, timeout_ms);
}

int
epd_wait_busy_low(const epd_model_config_t *cfg, uint32_t timeout_ms)
{
    /* Create a temporary config with LOW polarity */
    epd_model_config_t tmp = *cfg;
    tmp.busy_polarity = BUSY_ACTIVE_LOW;
    return epd_read_busy(&tmp, timeout_ms);
}
