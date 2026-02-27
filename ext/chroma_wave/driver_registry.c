#include "driver_registry.h"
#include "device.h"
#include "mock_hal.h"
#include "driver_configs_generated.h"

/* ------------------------------------------------------------------ */
/* Tier 2 overrides -- wired by tier2_overrides.c                      */
/* ------------------------------------------------------------------ */

/* Defined in tier2_overrides.c */
extern void tier2_register_overrides(epd_driver_t *drivers, size_t count,
                                     const char **names);

/* Names of models that need Tier 2 overrides */
static const char *tier2_model_names[] = {
    "epd_13in3k",
    "epd_1in02d",
    "epd_1in54",
    "epd_1in64g",
    "epd_2in13",
    "epd_2in15g",
    "epd_2in36g",
    "epd_2in7",
    "epd_2in7_v2",
    "epd_2in9",
    "epd_3in0g",
    "epd_3in52",
    "epd_3in7",
    "epd_4in01f",
    "epd_4in2",
    "epd_4in26",
    "epd_4in2_v2",
    "epd_4in37g",
    "epd_5in65f",
    "epd_5in83bc",
    "epd_7in3e",
    "epd_7in3f",
    "epd_7in3g",
    "epd_7in5_v2",
    "epd_7in5bc"
};

#define TIER2_COUNT (sizeof(tier2_model_names) / sizeof(tier2_model_names[0]))

static epd_driver_t tier2_drivers[TIER2_COUNT];
static int tier2_initialized = 0;

/* Resolve tier2 driver .config pointers from model names and wire
 * real per-model overrides from tier2_overrides.c. */
static void
tier2_resolve_configs(void)
{
    size_t i;
    if (tier2_initialized) return;

    for (i = 0; i < TIER2_COUNT; i++) {
        tier2_drivers[i].config         = epd_find_config(tier2_model_names[i]);
        tier2_drivers[i].custom_init    = NULL;
        tier2_drivers[i].custom_display = NULL;
        tier2_drivers[i].pre_display    = NULL;
        tier2_drivers[i].post_display   = NULL;
    }

    /* Wire real per-model overrides */
    tier2_register_overrides(tier2_drivers, TIER2_COUNT, tier2_model_names);
    tier2_initialized = 1;
}

/* ------------------------------------------------------------------ */
/* Generic (Tier 1) init sequence interpreter                          */
/* ------------------------------------------------------------------ */

/* Select the init sequence for the requested mode.
 * Falls back to full-init if the requested mode has no dedicated sequence. */
static const uint8_t *
select_init_sequence(const epd_model_config_t *cfg, uint8_t mode,
                     uint16_t *out_len)
{
    switch (mode) {
    case EPD_MODE_FAST:
        if (cfg->init_fast_sequence) {
            *out_len = cfg->init_fast_sequence_len;
            return cfg->init_fast_sequence;
        }
        break;
    case EPD_MODE_PARTIAL:
        if (cfg->init_partial_sequence) {
            *out_len = cfg->init_partial_sequence_len;
            return cfg->init_partial_sequence;
        }
        break;
    default:
        break;
    }
    /* Default: full init */
    *out_len = cfg->init_sequence_len;
    return cfg->init_sequence;
}

int
epd_generic_init(const epd_model_config_t *cfg, uint8_t mode)
{
    uint16_t       seq_len;
    const uint8_t *seq = select_init_sequence(cfg, mode, &seq_len);
    uint16_t       pos = 0;
    uint8_t        cmd, count, delay_val;
    uint16_t       x_end, y_end;
    int            rc;

    if (!seq || seq_len == 0) return EPD_ERR_PARAM;

    while (pos < seq_len) {
        uint8_t byte = seq[pos++];

        if (byte >= 0xF0) {
            /* Sentinel opcode */
            switch (byte) {
            case SEQ_END:
                return EPD_OK;

            case SEQ_WAIT_BUSY:
                rc = epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
                if (rc != EPD_OK) return rc;
                break;

            case SEQ_DELAY_MS:
                if (pos >= seq_len) return EPD_ERR_PARAM;
                delay_val = seq[pos++];
                DEV_Delay_ms(delay_val);
                break;

            case SEQ_HW_RESET:
                epd_reset(cfg);
                break;

            case SEQ_SW_RESET:
                epd_send_command(0x12);
                rc = epd_read_busy(cfg->busy_polarity, EPD_BUSY_TIMEOUT_MS);
                if (rc != EPD_OK) return rc;
                break;

            case SEQ_SET_WINDOW:
                /* Set RAM X address range: 0x44, start, end */
                x_end = (cfg->width - 1) / 8;
                epd_send_command(0x44);
                epd_send_data(0x00);
                epd_send_data((uint8_t)x_end);
                /* Set RAM Y address range: 0x45, y_start_lo, y_start_hi,
                 *                                y_end_lo,   y_end_hi */
                y_end = cfg->height - 1;
                epd_send_command(0x45);
                epd_send_data(0x00);
                epd_send_data(0x00);
                epd_send_data((uint8_t)(y_end & 0xFF));
                epd_send_data((uint8_t)(y_end >> 8));
                break;

            case SEQ_SET_CURSOR:
                /* Set RAM X counter: 0x4E, 0 */
                epd_send_command(0x4E);
                epd_send_data(0x00);
                /* Set RAM Y counter: 0x4F, 0, 0 */
                epd_send_command(0x4F);
                epd_send_data(0x00);
                epd_send_data(0x00);
                break;

            default:
                /* Unknown sentinel -- skip */
                break;
            }
        } else {
            /* Regular command: byte is command, next byte is data count */
            cmd = byte;
            if (pos >= seq_len) return EPD_ERR_PARAM;
            count = seq[pos++];

            epd_send_command(cmd);
            for (uint8_t i = 0; i < count; i++) {
                if (pos >= seq_len) return EPD_ERR_PARAM;
                epd_send_data(seq[pos++]);
            }
        }
    }

    return EPD_OK;
}

/* ------------------------------------------------------------------ */
/* Generic display: send framebuffer to display RAM.                   */
/* NOTE: This only writes pixel data to the controller's RAM.          */
/* It does NOT trigger a display refresh (TurnOnDisplay).  The caller  */
/* is responsible for issuing the appropriate refresh command sequence, */
/* which varies by model.  Tier 2 overrides and the high-level Ruby    */
/* API will handle refresh in a future phase.                          */
/* ------------------------------------------------------------------ */

int
epd_generic_display(const epd_model_config_t *cfg,
                    const uint8_t *buf, size_t len)
{
    if (!buf || len == 0) return EPD_ERR_PARAM;

    epd_send_command(cfg->display_cmd);
    epd_send_data_bulk(buf, len);

    /* Dual-buffer displays use a second command for the secondary buffer.
     * In the generic case, we send the command but NOT a second data payload;
     * Tier 2 overrides handle the actual second-buffer data when needed. */
    if (cfg->display_cmd_2 != 0x00) {
        epd_send_command(cfg->display_cmd_2);
    }

    return EPD_OK;
}

/* ------------------------------------------------------------------ */
/* Generic sleep                                                       */
/* ------------------------------------------------------------------ */

void
epd_generic_sleep(const epd_model_config_t *cfg)
{
    epd_send_command(cfg->sleep_cmd);
    epd_send_data(cfg->sleep_data);
}

/* ------------------------------------------------------------------ */
/* Registry lookup                                                     */
/* ------------------------------------------------------------------ */

const epd_model_config_t *
epd_find_config(const char *name)
{
    size_t i;
    if (!name) return NULL;

    for (i = 0; i < EPD_MODEL_COUNT; i++) {
        if (strcmp(epd_model_configs[i].name, name) == 0) {
            return &epd_model_configs[i];
        }
    }
    return NULL;
}

const epd_driver_t *
epd_find_driver(const char *name)
{
    size_t i;
    if (!name) return NULL;

    tier2_resolve_configs();

    for (i = 0; i < TIER2_COUNT; i++) {
        if (tier2_drivers[i].config &&
            strcmp(tier2_drivers[i].config->name, name) == 0) {
            return &tier2_drivers[i];
        }
    }
    return NULL;
}

size_t
epd_model_count(void)
{
    return (size_t)EPD_MODEL_COUNT;
}

const epd_model_config_t *
epd_model_at(size_t index)
{
    if (index >= EPD_MODEL_COUNT) return NULL;
    return &epd_model_configs[index];
}

/* ------------------------------------------------------------------ */
/* Ruby API                                                            */
/* ------------------------------------------------------------------ */

/* pixel_format_t -> Ruby Symbol: uses shared cw_pixel_format_to_sym() */

/* Helper: convert busy_polarity_t to Ruby symbol */
static VALUE
busy_polarity_sym(busy_polarity_t pol)
{
    switch (pol) {
    case BUSY_ACTIVE_LOW:  return ID2SYM(rb_intern("active_low"));
    case BUSY_ACTIVE_HIGH: return ID2SYM(rb_intern("active_high"));
    default:               return ID2SYM(rb_intern("unknown"));
    }
}

/* Helper: convert capabilities bitfield to Ruby Array of Symbols */
static VALUE
capabilities_to_array(uint32_t caps)
{
    VALUE ary = rb_ary_new();

    if (caps & EPD_CAP_PARTIAL)   rb_ary_push(ary, ID2SYM(rb_intern("partial")));
    if (caps & EPD_CAP_FAST)      rb_ary_push(ary, ID2SYM(rb_intern("fast")));
    if (caps & EPD_CAP_GRAYSCALE) rb_ary_push(ary, ID2SYM(rb_intern("grayscale")));
    if (caps & EPD_CAP_DUAL_BUF)  rb_ary_push(ary, ID2SYM(rb_intern("dual_buf")));
    if (caps & EPD_CAP_REGIONAL)  rb_ary_push(ary, ID2SYM(rb_intern("regional")));

    return ary;
}

/* ChromaWave::Native.model_count -> Integer */
static VALUE
rb_model_count(VALUE self)
{
    (void)self;
    return SIZET2NUM(epd_model_count());
}

/* ChromaWave::Native.model_config(name) -> Hash or nil */
static VALUE
rb_model_config(VALUE self, VALUE rb_name)
{
    const epd_model_config_t *cfg;
    const char *name;
    VALUE hash;

    (void)self;
    Check_Type(rb_name, T_STRING);
    name = StringValueCStr(rb_name);

    cfg = epd_find_config(name);
    if (!cfg) return Qnil;

    hash = rb_hash_new();
    rb_hash_aset(hash, ID2SYM(rb_intern("name")),
                 rb_str_new_cstr(cfg->name));
    rb_hash_aset(hash, ID2SYM(rb_intern("width")),
                 UINT2NUM(cfg->width));
    rb_hash_aset(hash, ID2SYM(rb_intern("height")),
                 UINT2NUM(cfg->height));
    rb_hash_aset(hash, ID2SYM(rb_intern("pixel_format")),
                 cw_pixel_format_to_sym(cfg->pixel_format));
    rb_hash_aset(hash, ID2SYM(rb_intern("busy_polarity")),
                 busy_polarity_sym(cfg->busy_polarity));
    rb_hash_aset(hash, ID2SYM(rb_intern("capabilities")),
                 capabilities_to_array(cfg->capabilities));
    rb_hash_aset(hash, ID2SYM(rb_intern("display_cmd")),
                 UINT2NUM(cfg->display_cmd));
    rb_hash_aset(hash, ID2SYM(rb_intern("display_cmd_2")),
                 UINT2NUM(cfg->display_cmd_2));
    rb_hash_aset(hash, ID2SYM(rb_intern("sleep_cmd")),
                 UINT2NUM(cfg->sleep_cmd));
    rb_hash_aset(hash, ID2SYM(rb_intern("sleep_data")),
                 UINT2NUM(cfg->sleep_data));
    rb_hash_aset(hash, ID2SYM(rb_intern("tier2")),
                 epd_find_driver(name) ? Qtrue : Qfalse);

    return hash;
}

/* ChromaWave::Native.model_names -> Array of Strings */
static VALUE
rb_model_names(VALUE self)
{
    VALUE ary;
    size_t i, count;

    (void)self;
    count = epd_model_count();
    ary = rb_ary_new_capa((long)count);

    for (i = 0; i < count; i++) {
        rb_ary_push(ary, rb_str_new_cstr(epd_model_configs[i].name));
    }

    return ary;
}

/* ------------------------------------------------------------------ */
/* Init                                                                */
/* ------------------------------------------------------------------ */

void
Init_driver_registry(void)
{
    rb_define_module_function(rb_mChromaWaveNative,
                             "model_count", rb_model_count, 0);
    rb_define_module_function(rb_mChromaWaveNative,
                             "model_config", rb_model_config, 1);
    rb_define_module_function(rb_mChromaWaveNative,
                             "model_names", rb_model_names, 0);

    /* Eagerly resolve tier2 driver config pointers */
    tier2_resolve_configs();
}
