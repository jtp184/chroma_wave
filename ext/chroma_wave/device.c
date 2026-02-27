#include "device.h"
#include "driver_registry.h"
#include "framebuffer.h"
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
epd_read_busy(busy_polarity_t polarity, uint32_t timeout_ms)
{
    uint32_t i;
    uint8_t  pin_val;

    for (i = 0; i < timeout_ms; i++) {
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
    int rc;

    TypedData_Get_Struct(rb_fb, framebuffer_t, &framebuffer_type, fb);

    if (dev->driver && dev->driver->pre_display) {
        dev->driver->pre_display(dev->config);
    }

    if (dev->driver && dev->driver->custom_display) {
        rc = dev->driver->custom_display(dev->config, fb->buffer, fb->buffer_size);
    } else {
        rc = epd_generic_display(dev->config, fb->buffer, fb->buffer_size);
    }

    if (rc == EPD_ERR_TIMEOUT) {
        rb_raise(rb_eBusyTimeoutError, "busy timeout during display");
    }
    if (rc != EPD_OK) {
        rb_raise(rb_eDeviceError, "EPD display failed (rc=%d)", rc);
    }

    if (dev->driver && dev->driver->post_display) {
        dev->driver->post_display(dev->config);
    }

    return Qnil;
}

/* ---- _epd_display_dual(black_fb, red_fb) ---- */
static VALUE
device_epd_display_dual(VALUE self, VALUE rb_black_fb, VALUE rb_red_fb)
{
    device_t *dev = device_require_open(self);
    framebuffer_t *black_fb, *red_fb;

    TypedData_Get_Struct(rb_black_fb, framebuffer_t, &framebuffer_type, black_fb);
    TypedData_Get_Struct(rb_red_fb,   framebuffer_t, &framebuffer_type, red_fb);

    /* Send black channel via primary display command */
    epd_send_command(dev->config->display_cmd);
    epd_send_data_bulk(black_fb->buffer, black_fb->buffer_size);

    /* Send red/yellow channel via secondary display command */
    if (dev->config->display_cmd_2 != 0x00) {
        epd_send_command(dev->config->display_cmd_2);
        epd_send_data_bulk(red_fb->buffer, red_fb->buffer_size);
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
    size_t buf_size;
    uint8_t *buf;
    uint8_t fill;
    int rc;

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

    if (dev->driver && dev->driver->pre_display) {
        dev->driver->pre_display(dev->config);
    }

    if (dev->driver && dev->driver->custom_display) {
        rc = dev->driver->custom_display(dev->config, buf, buf_size);
    } else {
        rc = epd_generic_display(dev->config, buf, buf_size);
    }

    xfree(buf);

    if (rc == EPD_ERR_TIMEOUT) {
        rb_raise(rb_eBusyTimeoutError, "busy timeout during clear");
    }
    if (rc != EPD_OK) {
        rb_raise(rb_eDeviceError, "EPD clear failed (rc=%d)", rc);
    }

    if (dev->driver && dev->driver->post_display) {
        dev->driver->post_display(dev->config);
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
