/*
 * tier2_overrides.c -- Per-model driver overrides for Tier 2 displays
 *
 * Implements real per-model override functions extracted from vendor
 * source files (vendor/waveshare_epd/lib/e-Paper/EPD_*.c).
 *
 * Override categories:
 *   1. LUT-based (SSD1680 family): TurnOnDisplay refresh sequences
 *   2. Color (4-color/7-color ACeP): Power-on + refresh + power-off
 *   3. Power-managed (ACeP 7-color): Explicit power management
 *   4. Dual-buffer (UC8176/UC8179): Two-buffer display writes
 *   5. Non-standard: Unusual command sequences
 */

#include "driver_registry.h"
#include "device.h"
#include "mock_hal.h"

/* ------------------------------------------------------------------ */
/* Helper: find a driver slot by model name                            */
/* ------------------------------------------------------------------ */

static epd_driver_t *
find_driver_slot(epd_driver_t *drivers, size_t count,
                 const char **names, const char *target)
{
    size_t i;
    for (i = 0; i < count; i++) {
        if (strcmp(names[i], target) == 0) return &drivers[i];
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* LUT data arrays extracted from vendor sources                       */
/* ------------------------------------------------------------------ */

/* EPD_1in54: 30-byte LUT (SSD1681 / IL3829) */
static const uint8_t lut_1in54_full[] = {
    0x02, 0x02, 0x01, 0x11, 0x12, 0x12, 0x22, 0x22,
    0x66, 0x69, 0x69, 0x59, 0x58, 0x99, 0x99, 0x88,
    0x00, 0x00, 0x00, 0x00, 0xF8, 0xB4, 0x13, 0x51,
    0x35, 0x51, 0x51, 0x19, 0x01, 0x00
};

static const uint8_t lut_1in54_partial[] = {
    0x10, 0x18, 0x18, 0x08, 0x18, 0x18, 0x08, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x13, 0x14, 0x44, 0x12,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

/* EPD_2in13: 30-byte LUT (SSD1680 / IL3897) */
static const uint8_t lut_2in13_full[] = {
    0x22, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x11,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00
};

static const uint8_t lut_2in13_partial[] = {
    0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x0F, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

/* EPD_2in9: 30-byte LUT (SSD1680 / IL3820) */
static const uint8_t lut_2in9_full[] = {
    0x50, 0xAA, 0x55, 0xAA, 0x11, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xFF, 0xFF, 0x1F, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static const uint8_t lut_2in9_partial[] = {
    0x10, 0x18, 0x18, 0x08, 0x18, 0x18,
    0x08, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x13, 0x14, 0x44, 0x12,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

/* ================================================================== */
/* Category 1: LUT-based models (SSD1680 family)                      */
/* TurnOnDisplay: 0x22 + data + 0x20 + 0xFF + busy-wait              */
/* ================================================================== */

/* Shared TurnOnDisplay for SSD1680-family (1in54, 2in13, 2in9):
 * cmd 0x22 (Display Update Control 2), data 0xC4,
 * cmd 0x20 (Master Activation), cmd 0xFF (Terminate),
 * then wait busy. */
static void
ssd1680_turn_on_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x22);
    epd_send_data(0xC4);
    epd_send_command(0x20);
    epd_send_command(0xFF);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_1in54 ---------------------------------------------------- */

static int
epd_1in54_init(const epd_model_config_t *cfg, uint8_t mode)
{
    int rc = epd_generic_init(cfg, mode);
    if (rc != EPD_OK) return rc;

    /* Load LUT via command 0x32 */
    epd_send_command(0x32);
    if (mode == EPD_MODE_PARTIAL)
        epd_send_data_bulk(lut_1in54_partial, sizeof(lut_1in54_partial));
    else
        epd_send_data_bulk(lut_1in54_full, sizeof(lut_1in54_full));

    return EPD_OK;
}

static void
epd_1in54_post_display(const epd_model_config_t *cfg)
{
    ssd1680_turn_on_display(cfg);
}

/* -- epd_2in13 ---------------------------------------------------- */

static int
epd_2in13_init(const epd_model_config_t *cfg, uint8_t mode)
{
    int rc = epd_generic_init(cfg, mode);
    if (rc != EPD_OK) return rc;

    epd_send_command(0x32);
    if (mode == EPD_MODE_PARTIAL)
        epd_send_data_bulk(lut_2in13_partial, sizeof(lut_2in13_partial));
    else
        epd_send_data_bulk(lut_2in13_full, sizeof(lut_2in13_full));

    return EPD_OK;
}

static void
epd_2in13_post_display(const epd_model_config_t *cfg)
{
    ssd1680_turn_on_display(cfg);
}

/* -- epd_2in9 ----------------------------------------------------- */

static int
epd_2in9_init(const epd_model_config_t *cfg, uint8_t mode)
{
    int rc = epd_generic_init(cfg, mode);
    if (rc != EPD_OK) return rc;

    epd_send_command(0x32);
    if (mode == EPD_MODE_PARTIAL)
        epd_send_data_bulk(lut_2in9_partial, sizeof(lut_2in9_partial));
    else
        epd_send_data_bulk(lut_2in9_full, sizeof(lut_2in9_full));

    return EPD_OK;
}

static void
epd_2in9_post_display(const epd_model_config_t *cfg)
{
    ssd1680_turn_on_display(cfg);
}

/* -- epd_4in2 (UC8176) -------------------------------------------- */
/* TurnOnDisplay: 0x12 (Display Refresh) + delay + busy-wait */

static void
epd_4in2_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x12);
    DEV_Delay_ms(100);
    /* UC8176 busy: poll via 0x71 command, active-low */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_4in2_v2 (SSD1683) --------------------------------------- */
/* TurnOnDisplay: 0x22 + 0xF7 + 0x20 + busy-wait */

static void
epd_4in2_v2_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x22);
    epd_send_data(0xF7);
    epd_send_command(0x20);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_4in26 (SSD1677) ----------------------------------------- */
/* TurnOnDisplay: 0x22 + 0xF7 + 0x20 + busy-wait */

static void
epd_4in26_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x22);
    epd_send_data(0xF7);
    epd_send_command(0x20);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_13in3k (SSD1677-like) ------------------------------------ */
/* TurnOnDisplay: 0x22 + 0xF7 + 0x20 + busy-wait */

static void
epd_13in3k_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x22);
    epd_send_data(0xF7);
    epd_send_command(0x20);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* ================================================================== */
/* Category 2: Color displays (4-color gate-driver)                   */
/* Pre-display: power-on (0x04) + busy                                */
/* Post-display: refresh (0x12) + busy + power-off (0x02) + busy      */
/* ================================================================== */

/* Shared pre_display for color gate-driver models */
static void
color_pre_display(const epd_model_config_t *cfg)
{
    /* Enable charge pump output (0x68 0x01) for models that need it */
    epd_send_command(0x68);
    epd_send_data(0x01);

    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* Shared post_display: refresh + power-off */
static void
color_post_display(const epd_model_config_t *cfg)
{
    /* Disable charge pump output */
    epd_send_command(0x68);
    epd_send_data(0x00);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    epd_send_data(0x01);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x02);  /* POWER_OFF */
    epd_send_data(0x00);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* Color models without charge pump control (7in3 family) */
static void
color_7in3_pre_display(const epd_model_config_t *cfg)
{
    (void)cfg;
    /* No pre-display needed; power-on happens in post_display */
}

/* 7in3e: complex TurnOnDisplay with booster re-configuration */
static void
epd_7in3e_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    /* Second booster setting (from vendor source) */
    epd_send_command(0x06);
    epd_send_data(0x6F);
    epd_send_data(0x1F);
    epd_send_data(0x17);
    epd_send_data(0x17);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    epd_send_data(0x00);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x02);  /* POWER_OFF */
    epd_send_data(0x00);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* 7in3f / 7in3g: standard color refresh */
static void
color_7in3_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    epd_send_data(0x00);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x02);  /* POWER_OFF */
    epd_send_data(0x00);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* ================================================================== */
/* Category 3: Power-managed (ACeP 7-color: 4in01f, 5in65f, 5in83bc) */
/* These need explicit power-on before display data and power-off      */
/* after refresh.                                                      */
/* ================================================================== */

/* 4in01f / 5in65f: ACeP 7-color panel
 * Sequence: send data -> 0x04 (power on) -> busy -> 0x12 (refresh)
 *           -> busy -> 0x02 (power off) -> busy-low */

static void
acep_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x02);  /* POWER_OFF */
    /* 5in65f uses dual-polarity: wait for busy-low after power-off */
    epd_wait_busy_low(EPD_BUSY_TIMEOUT_MS);
    DEV_Delay_ms(200);
}

/* 5in83bc: UC8179 tri-color
 * TurnOnDisplay: 0x04 + busy + 0x12 + delay + busy */

static void
epd_5in83bc_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    DEV_Delay_ms(100);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* ================================================================== */
/* Category 4: Dual-buffer displays                                    */
/* These write data to two separate RAM buffers before refresh.        */
/* ================================================================== */

/* -- epd_2in7 (UC8176) -------------------------------------------- */
/* Display: send 0x10 + data (buf 1), then 0x13 + data (buf 2),
 * then 0x12 (refresh) + busy-wait */

static int
epd_2in7_display(const epd_model_config_t *cfg,
                 const uint8_t *buf, size_t len)
{
    if (!buf || len == 0) return EPD_ERR_PARAM;

    /* Buffer 1: DATA_START_TRANSMISSION_1 (old data) */
    epd_send_command(cfg->display_cmd);   /* 0x10 */
    epd_send_data_bulk(buf, len);

    /* Buffer 2: DATA_START_TRANSMISSION_2 (new data) */
    epd_send_command(cfg->display_cmd_2); /* 0x13 */
    epd_send_data_bulk(buf, len);

    return EPD_OK;
}

static void
epd_2in7_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_2in7_v2 (SSD1680-class, dual buffer 0x24/0x26) ----------- */
/* TurnOnDisplay: 0x22 + 0xF7 + 0x20 + busy */

static int
epd_2in7_v2_display(const epd_model_config_t *cfg,
                    const uint8_t *buf, size_t len)
{
    if (!buf || len == 0) return EPD_ERR_PARAM;

    /* Buffer 1 */
    epd_send_command(cfg->display_cmd);   /* 0x24 */
    epd_send_data_bulk(buf, len);

    /* Buffer 2: same data */
    epd_send_command(cfg->display_cmd_2); /* 0x26 */
    epd_send_data_bulk(buf, len);

    return EPD_OK;
}

static void
epd_2in7_v2_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x22);
    epd_send_data(0xF7);
    epd_send_command(0x20);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_7in5_v2 (UC8179) ---------------------------------------- */
/* Display: buf 1 = 0x10 + data, buf 2 = 0x13 + ~data (inverted) */

static int
epd_7in5_v2_display(const epd_model_config_t *cfg,
                    const uint8_t *buf, size_t len)
{
    size_t i;
    uint8_t *inv;
    if (!buf || len == 0) return EPD_ERR_PARAM;

    /* Buffer 1: original data */
    epd_send_command(cfg->display_cmd);   /* 0x10 */
    epd_send_data_bulk(buf, len);

    /* Buffer 2: byte-inverted copy sent in bulk for performance.
     * malloc/free intentional: this runs without the GVL where xmalloc
     * could trigger GC unsafely.  Allocation is bounded by display
     * resolution (~480 KB max for 7.5" panel). */
    inv = (uint8_t *)malloc(len);
    if (!inv) return EPD_ERR_PARAM;
    for (i = 0; i < len; i++) {
        inv[i] = (uint8_t)(~buf[i]);
    }
    epd_send_command(cfg->display_cmd_2); /* 0x13 */
    epd_send_data_bulk(inv, len);
    free(inv);

    return EPD_OK;
}

static void
epd_7in5_v2_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    DEV_Delay_ms(100);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_7in5bc (UC8159 tri-color) -------------------------------- */
/* TurnOnDisplay: 0x04 + busy + 0x12 + delay + busy */

static int
epd_7in5bc_display(const epd_model_config_t *cfg,
                   const uint8_t *buf, size_t len)
{
    if (!buf || len == 0) return EPD_ERR_PARAM;

    /* Single data command for this tri-color display */
    epd_send_command(cfg->display_cmd);  /* 0x10 */
    epd_send_data_bulk(buf, len);

    return EPD_OK;
}

static void
epd_7in5bc_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    DEV_Delay_ms(100);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* ================================================================== */
/* Category 5: Non-standard models                                     */
/* ================================================================== */

/* -- epd_1in02d --------------------------------------------------- */
/* Uses custom LUT loading: separate W and B LUT commands (0x23, 0x24)
 * and a non-standard TurnOnDisplay sequence (0x04 + 0x12 + busy). */

static void
epd_1in02d_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x04);  /* POWER_ON */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);

    epd_send_command(0x02);  /* POWER_OFF */
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_3in52 (SSD1680-class with UC8176 LUT registers) ---------- */
/* TurnOnDisplay: 0x12 + delay + busy-wait
 * Same as 4in2 UC8176 pattern */

static void
epd_3in52_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    DEV_Delay_ms(100);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* -- epd_3in7 (SSD1677-based, 4-level gray) ---------------------- */
/* Uses command 0x12 for refresh with busy-wait */

static void
epd_3in7_post_display(const epd_model_config_t *cfg)
{
    epd_send_command(0x12);  /* DISPLAY_REFRESH */
    DEV_Delay_ms(100);
    epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
}

/* ================================================================== */
/* Registration function: wire overrides into driver table             */
/* ================================================================== */

void
tier2_register_overrides(epd_driver_t *drivers, size_t count,
                         const char **names)
{
    epd_driver_t *d;

    /* ---- Category 1: LUT-based ---- */

    d = find_driver_slot(drivers, count, names, "epd_1in54");
    if (d) {
        d->custom_init  = epd_1in54_init;
        d->post_display = epd_1in54_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_2in13");
    if (d) {
        d->custom_init  = epd_2in13_init;
        d->post_display = epd_2in13_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_2in9");
    if (d) {
        d->custom_init  = epd_2in9_init;
        d->post_display = epd_2in9_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_4in2");
    if (d) {
        d->post_display = epd_4in2_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_4in2_v2");
    if (d) {
        d->post_display = epd_4in2_v2_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_4in26");
    if (d) {
        d->post_display = epd_4in26_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_13in3k");
    if (d) {
        d->post_display = epd_13in3k_post_display;
    }

    /* ---- Category 2: Color displays ---- */

    d = find_driver_slot(drivers, count, names, "epd_1in64g");
    if (d) {
        d->pre_display  = color_pre_display;
        d->post_display = color_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_2in15g");
    if (d) {
        d->pre_display  = color_pre_display;
        d->post_display = color_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_2in36g");
    if (d) {
        d->pre_display  = color_pre_display;
        d->post_display = color_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_3in0g");
    if (d) {
        d->pre_display  = color_pre_display;
        d->post_display = color_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_4in37g");
    if (d) {
        d->pre_display  = color_pre_display;
        d->post_display = color_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_7in3e");
    if (d) {
        d->pre_display  = color_7in3_pre_display;
        d->post_display = epd_7in3e_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_7in3f");
    if (d) {
        d->pre_display  = color_7in3_pre_display;
        d->post_display = color_7in3_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_7in3g");
    if (d) {
        d->pre_display  = color_7in3_pre_display;
        d->post_display = color_7in3_post_display;
    }

    /* ---- Category 3: Power-managed ---- */

    d = find_driver_slot(drivers, count, names, "epd_4in01f");
    if (d) {
        d->post_display = acep_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_5in65f");
    if (d) {
        d->post_display = acep_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_5in83bc");
    if (d) {
        d->post_display = epd_5in83bc_post_display;
    }

    /* ---- Category 4: Dual-buffer ---- */

    d = find_driver_slot(drivers, count, names, "epd_2in7");
    if (d) {
        d->custom_display = epd_2in7_display;
        d->post_display   = epd_2in7_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_2in7_v2");
    if (d) {
        d->custom_display = epd_2in7_v2_display;
        d->post_display   = epd_2in7_v2_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_7in5_v2");
    if (d) {
        d->custom_display = epd_7in5_v2_display;
        d->post_display   = epd_7in5_v2_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_7in5bc");
    if (d) {
        d->custom_display = epd_7in5bc_display;
        d->post_display   = epd_7in5bc_post_display;
    }

    /* ---- Category 5: Non-standard ---- */

    d = find_driver_slot(drivers, count, names, "epd_1in02d");
    if (d) {
        d->post_display = epd_1in02d_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_3in52");
    if (d) {
        d->post_display = epd_3in52_post_display;
    }

    d = find_driver_slot(drivers, count, names, "epd_3in7");
    if (d) {
        d->post_display = epd_3in7_post_display;
    }
}
