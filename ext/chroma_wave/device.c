#include "device.h"
#include "driver_registry.h"
#include "framebuffer.h"
#include "mock_hal.h"
#include <ruby/thread.h>

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

/* Global cancel flag: set by display_without_gvl, checked by epd_read_busy.
 * Acceptable as a global because real hardware only has one SPI bus.
 *
 * TODO: Under the mock backend, two Device instances running concurrent
 * GVL-released operations could race on this global.  Consider making
 * epd_read_busy accept a device_t* and read the cancel flag from the
 * per-device struct instead. */
volatile int *epd_cancel_flag = NULL;

int
epd_read_busy(busy_polarity_t polarity, uint32_t timeout_ms)
{
    uint32_t i;
    uint8_t  pin_val;

    for (i = 0; i < timeout_ms; i++) {
        /* Check cancellation flag (set by UBF when thread is interrupted) */
        if (epd_cancel_flag && *epd_cancel_flag) {
            return EPD_ERR_TIMEOUT;
        }

        pin_val = DEV_Digital_Read(EPD_BUSY_PIN);

        if (polarity == BUSY_ACTIVE_HIGH) {
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
epd_wait_busy_high(uint32_t timeout_ms)
{
    return epd_read_busy(BUSY_ACTIVE_HIGH, timeout_ms);
}

int
epd_wait_busy_low(uint32_t timeout_ms)
{
    return epd_read_busy(BUSY_ACTIVE_LOW, timeout_ms);
}

/* ================================================================== */
/* Device TypedData class                                              */
/* ================================================================== */

VALUE rb_cDevice;

/* ---- TypedData callbacks ---- */
static void
device_dfree(void *ptr)
{
    device_t *dev = (device_t *)ptr;
    if (dev->state == DEVICE_OPEN) {
        DEV_Module_Exit();
        dev->state = DEVICE_CLOSED;
    }
    xfree(dev);
}

static size_t
device_dsize(const void *ptr)
{
    (void)ptr;
    return sizeof(device_t);
}

const rb_data_type_t device_type = {
    .wrap_struct_name = "ChromaWave::Device",
    .function = {
        .dmark  = NULL,    /* no VALUEs stored in C struct */
        .dfree  = device_dfree,
        .dsize  = device_dsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* ---- Allocation ---- */
static VALUE
device_alloc(VALUE klass)
{
    device_t *dev;
    VALUE obj = TypedData_Make_Struct(klass, device_t, &device_type, dev);
    dev->config = NULL;
    dev->driver = NULL;
    dev->state  = DEVICE_CLOSED;
    dev->cancel = 0;
    return obj;
}

/* ---- initialize(model_name) ---- */
static VALUE
device_initialize(VALUE self, VALUE rb_model_name)
{
    device_t *dev;
    const char *name;
    int rc;

    TypedData_Get_Struct(self, device_t, &device_type, dev);
    Check_Type(rb_model_name, T_STRING);
    name = StringValueCStr(rb_model_name);

    dev->config = epd_find_config(name);
    if (!dev->config) {
        rb_raise(rb_eModelNotFoundError, "unknown model: %s", name);
    }

    dev->driver = epd_find_driver(name);  /* may be NULL for Tier 1 */

    rc = DEV_Module_Init();
    if (rc != 0) {
        rb_raise(rb_eInitError, "DEV_Module_Init failed (rc=%d)", rc);
    }
    dev->state = DEVICE_OPEN;

    return self;
}

/* ---- close -> nil ---- */
static VALUE
device_close(VALUE self)
{
    device_t *dev;
    TypedData_Get_Struct(self, device_t, &device_type, dev);
    if (dev->state == DEVICE_OPEN) {
        DEV_Module_Exit();
        dev->state = DEVICE_CLOSED;
    }
    return Qnil;
}

/* ---- open? -> true/false ---- */
static VALUE
device_open_p(VALUE self)
{
    device_t *dev;
    TypedData_Get_Struct(self, device_t, &device_type, dev);
    return dev->state == DEVICE_OPEN ? Qtrue : Qfalse;
}

/* ---- model_name -> String ---- */
static VALUE
device_model_name(VALUE self)
{
    device_t *dev;
    TypedData_Get_Struct(self, device_t, &device_type, dev);
    if (!dev->config) return Qnil;
    return rb_str_new_cstr(dev->config->name);
}

/* ---- Helper: assert device is open ---- */
static device_t *
device_require_open(VALUE self)
{
    device_t *dev;
    TypedData_Get_Struct(self, device_t, &device_type, dev);
    if (dev->state != DEVICE_OPEN) {
        rb_raise(rb_eDeviceError, "device is closed");
    }
    return dev;
}

/* ================================================================== */
/* GVL release helpers for display operations                          */
/* ================================================================== */

/* Arguments passed to display_without_gvl (no VALUE fields!) */
typedef struct {
    device_t       *dev;
    const uint8_t  *buf;
    size_t          buf_len;
    int             result;
} display_args_t;

/* Runs WITHOUT the GVL -- must NOT call any Ruby API functions. */
static void *
display_without_gvl(void *arg)
{
    display_args_t *args = (display_args_t *)arg;
    const epd_model_config_t *cfg = args->dev->config;
    const epd_driver_t *drv = args->dev->driver;

    /* Install cancel flag so epd_read_busy can check for interruption */
    epd_cancel_flag = &args->dev->cancel;

    /* Pre-display hook */
    if (drv && drv->pre_display) {
        drv->pre_display(cfg);
    }

    /* Display data */
    if (drv && drv->custom_display) {
        args->result = drv->custom_display(cfg, args->buf, args->buf_len);
    } else {
        args->result = epd_generic_display(cfg, args->buf, args->buf_len);
    }

    /* Post-display hook (only if display succeeded) */
    if (args->result == EPD_OK && drv && drv->post_display) {
        drv->post_display(cfg);
    }

    /* Clear cancel flag */
    epd_cancel_flag = NULL;

    return NULL;
}

/* Unblocking function: called by Ruby when another thread interrupts us.
 * Runs in a different thread context -- only simple operations allowed. */
static void
display_ubf(void *arg)
{
    display_args_t *args = (display_args_t *)arg;
    args->dev->cancel = 1;  /* volatile write signals busy-wait to abort */
}

/* ---- _epd_init(mode) ---- */
static VALUE
device_epd_init(VALUE self, VALUE rb_mode)
{
    device_t *dev = device_require_open(self);
    uint8_t mode = (uint8_t)NUM2INT(rb_mode);
    int rc;

    if (dev->driver && dev->driver->custom_init) {
        rc = dev->driver->custom_init(dev->config, mode);
    } else {
        rc = epd_generic_init(dev->config, mode);
    }

    if (rc != EPD_OK) {
        if (rc == EPD_ERR_TIMEOUT) {
            rb_raise(rb_eBusyTimeoutError, "busy timeout during init (mode=%d)", mode);
        }
        rb_raise(rb_eInitError, "EPD init failed (rc=%d, mode=%d)", rc, mode);
    }

    return Qnil;
}

/* ---- _epd_display(fb) ---- */
static VALUE
device_epd_display(VALUE self, VALUE rb_fb)
{
    device_t *dev = device_require_open(self);
    framebuffer_t *fb;
    display_args_t args;

    TypedData_Get_Struct(rb_fb, framebuffer_t, &framebuffer_type, fb);

    /* Prepare args for non-GVL execution */
    args.dev     = dev;
    args.buf     = fb->buffer;
    args.buf_len = fb->buffer_size;
    args.result  = EPD_OK;

    /* Reset cancel flag before starting */
    dev->cancel = 0;

    /* Release GVL so other Ruby threads can run during display */
    rb_thread_call_without_gvl(display_without_gvl, &args,
                               display_ubf, &args);

    /* Back under GVL -- safe to raise exceptions */
    if (args.result == EPD_ERR_TIMEOUT) {
        rb_raise(rb_eBusyTimeoutError, "busy timeout during display");
    }
    if (args.result != EPD_OK) {
        rb_raise(rb_eDeviceError, "EPD display failed (rc=%d)", args.result);
    }

    return Qnil;
}

/* ---- Dual-buffer display without GVL ---- */

/* Arguments passed to display_dual_without_gvl (no VALUE fields!) */
typedef struct {
    device_t       *dev;
    const uint8_t  *black_buf;
    size_t          black_len;
    const uint8_t  *red_buf;
    size_t          red_len;
    int             result;
} display_dual_args_t;

/* Runs WITHOUT the GVL -- must NOT call any Ruby API functions. */
static void *
display_dual_without_gvl(void *arg)
{
    display_dual_args_t *args = (display_dual_args_t *)arg;
    const epd_model_config_t *cfg = args->dev->config;
    const epd_driver_t *drv = args->dev->driver;

    /* Install cancel flag so epd_read_busy can check for interruption */
    epd_cancel_flag = &args->dev->cancel;

    /* Pre-display hook */
    if (drv && drv->pre_display) {
        drv->pre_display(cfg);
    }

    /* Send black channel via primary display command */
    epd_send_command(cfg->display_cmd);
    epd_send_data_bulk(args->black_buf, args->black_len);

    /* Send red/yellow channel via secondary display command */
    if (cfg->display_cmd_2 != 0x00) {
        epd_send_command(cfg->display_cmd_2);
        epd_send_data_bulk(args->red_buf, args->red_len);
    }

    args->result = EPD_OK;

    /* Post-display hook */
    if (drv && drv->post_display) {
        drv->post_display(cfg);
    }

    /* Clear cancel flag */
    epd_cancel_flag = NULL;

    return NULL;
}

/* Unblocking function for dual display */
static void
display_dual_ubf(void *arg)
{
    display_dual_args_t *args = (display_dual_args_t *)arg;
    args->dev->cancel = 1;
}

/* ---- _epd_display_dual(black_fb, red_fb) ---- */
static VALUE
device_epd_display_dual(VALUE self, VALUE rb_black_fb, VALUE rb_red_fb)
{
    device_t *dev = device_require_open(self);
    framebuffer_t *black_fb, *red_fb;
    display_dual_args_t args;

    TypedData_Get_Struct(rb_black_fb, framebuffer_t, &framebuffer_type, black_fb);
    TypedData_Get_Struct(rb_red_fb,   framebuffer_t, &framebuffer_type, red_fb);

    /* Prepare args for non-GVL execution */
    args.dev       = dev;
    args.black_buf = black_fb->buffer;
    args.black_len = black_fb->buffer_size;
    args.red_buf   = red_fb->buffer;
    args.red_len   = red_fb->buffer_size;
    args.result    = EPD_OK;

    /* Reset cancel flag before starting */
    dev->cancel = 0;

    /* Release GVL so other Ruby threads can run during dual display */
    rb_thread_call_without_gvl(display_dual_without_gvl, &args,
                               display_dual_ubf, &args);

    /* Back under GVL -- safe to raise exceptions */
    if (args.result == EPD_ERR_TIMEOUT) {
        rb_raise(rb_eBusyTimeoutError, "busy timeout during dual display");
    }
    if (args.result != EPD_OK) {
        rb_raise(rb_eDeviceError, "EPD dual display failed (rc=%d)", args.result);
    }

    return Qnil;
}

/* ---- _epd_sleep ---- */
static VALUE
device_epd_sleep(VALUE self)
{
    device_t *dev = device_require_open(self);
    epd_generic_sleep(dev->config);
    return Qnil;
}

/* ---- _epd_clear ---- */
static VALUE
device_epd_clear(VALUE self)
{
    device_t *dev = device_require_open(self);
    display_args_t args;
    size_t buf_size;
    uint8_t *buf;
    uint8_t fill;

    /* Calculate buffer size the same way framebuffer does */
    uint16_t width_byte;
    switch (dev->config->pixel_format) {
    case PIXEL_FORMAT_MONO:   width_byte = (uint16_t)((dev->config->width + 7) / 8); break;
    case PIXEL_FORMAT_GRAY4:  width_byte = (uint16_t)((dev->config->width + 3) / 4); break;
    case PIXEL_FORMAT_COLOR4:
    case PIXEL_FORMAT_COLOR7: width_byte = (uint16_t)((dev->config->width + 1) / 2); break;
    default:                  width_byte = (uint16_t)((dev->config->width + 7) / 8); break;
    }
    buf_size = (size_t)width_byte * dev->config->height;

    /* MONO: white = 0xFF; others: white = 0x00 or format-appropriate */
    switch (dev->config->pixel_format) {
    case PIXEL_FORMAT_MONO:   fill = 0xFF; break;
    case PIXEL_FORMAT_GRAY4:  fill = 0xFF; break; /* all-white: 0b11_11_11_11 */
    case PIXEL_FORMAT_COLOR4: fill = 0x11; break; /* white=1 in each nibble */
    case PIXEL_FORMAT_COLOR7: fill = 0x11; break; /* white=1 in each nibble */
    default:                  fill = 0xFF; break;
    }

    buf = (uint8_t *)xmalloc(buf_size);
    memset(buf, fill, buf_size);

    /* Prepare args for non-GVL execution */
    args.dev     = dev;
    args.buf     = buf;
    args.buf_len = buf_size;
    args.result  = EPD_OK;
    dev->cancel  = 0;

    /* Release GVL so other Ruby threads can run during clear */
    rb_thread_call_without_gvl(display_without_gvl, &args,
                               display_ubf, &args);

    xfree(buf);

    /* Back under GVL -- safe to raise exceptions */
    if (args.result == EPD_ERR_TIMEOUT) {
        rb_raise(rb_eBusyTimeoutError, "busy timeout during clear");
    }
    if (args.result != EPD_OK) {
        rb_raise(rb_eDeviceError, "EPD clear failed (rc=%d)", args.result);
    }

    return Qnil;
}

/* ---- Init_device ---- */
void
Init_device(void)
{
    rb_cDevice = rb_define_class_under(rb_mChromaWave, "Device", rb_cObject);
    rb_define_alloc_func(rb_cDevice, device_alloc);
    rb_define_method(rb_cDevice, "initialize",  device_initialize,  1);
    rb_define_method(rb_cDevice, "close",        device_close,       0);
    rb_define_method(rb_cDevice, "open?",        device_open_p,      0);
    rb_define_method(rb_cDevice, "model_name",   device_model_name,  0);
    rb_define_private_method(rb_cDevice, "_epd_init",         device_epd_init,         1);
    rb_define_private_method(rb_cDevice, "_epd_display",      device_epd_display,      1);
    rb_define_private_method(rb_cDevice, "_epd_display_dual", device_epd_display_dual, 2);
    rb_define_private_method(rb_cDevice, "_epd_sleep",        device_epd_sleep,        0);
    rb_define_private_method(rb_cDevice, "_epd_clear",        device_epd_clear,        0);
}
