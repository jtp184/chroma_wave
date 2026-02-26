#include "framebuffer.h"
#include "ruby/encoding.h"

/* ---- Symbol cache ---- */
static ID id_mono, id_gray4, id_color4, id_color7;

/* ---- Helper: pixel_format_t from Ruby Symbol ---- */
static pixel_format_t
sym_to_pixel_format(VALUE sym)
{
    ID id = SYM2ID(sym);

    if (id == id_mono)   return PIXEL_FORMAT_MONO;
    if (id == id_gray4)  return PIXEL_FORMAT_GRAY4;
    if (id == id_color4) return PIXEL_FORMAT_COLOR4;
    if (id == id_color7) return PIXEL_FORMAT_COLOR7;

    rb_raise(rb_eArgError,
             "unknown pixel format: %"PRIsVALUE" (expected :mono, :gray4, :color4, or :color7)",
             sym);
    return 0; /* unreachable */
}

/* ---- Helper: pixel_format_t to Ruby Symbol ---- */
static VALUE
pixel_format_to_sym(pixel_format_t fmt)
{
    switch (fmt) {
    case PIXEL_FORMAT_MONO:   return ID2SYM(id_mono);
    case PIXEL_FORMAT_GRAY4:  return ID2SYM(id_gray4);
    case PIXEL_FORMAT_COLOR4: return ID2SYM(id_color4);
    case PIXEL_FORMAT_COLOR7: return ID2SYM(id_color7);
    }
    return Qnil; /* unreachable */
}

/* ---- Helper: calculate bytes per row ---- */
static uint16_t
calc_width_byte(uint16_t width, pixel_format_t fmt)
{
    switch (fmt) {
    case PIXEL_FORMAT_MONO:   return (uint16_t)((width + 7) / 8);
    case PIXEL_FORMAT_GRAY4:  return (uint16_t)((width + 3) / 4);
    case PIXEL_FORMAT_COLOR4: /* fall through */
    case PIXEL_FORMAT_COLOR7: return (uint16_t)((width + 1) / 2);
    }
    return 0; /* unreachable */
}

/* ---- TypedData callbacks ---- */
static void
fb_dfree(void *ptr)
{
    framebuffer_t *fb = (framebuffer_t *)ptr;
    if (fb->buffer) {
        xfree(fb->buffer);
        fb->buffer = NULL;
    }
    xfree(fb);
}

static size_t
fb_dsize(const void *ptr)
{
    const framebuffer_t *fb = (const framebuffer_t *)ptr;
    return sizeof(framebuffer_t) + fb->buffer_size;
}

static const rb_data_type_t framebuffer_type = {
    .wrap_struct_name = "ChromaWave::Framebuffer",
    .function = {
        .dmark  = NULL,
        .dfree  = fb_dfree,
        .dsize  = fb_dsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* ---- Allocation ---- */
static VALUE
fb_alloc(VALUE klass)
{
    framebuffer_t *fb;
    VALUE obj = TypedData_Make_Struct(klass, framebuffer_t, &framebuffer_type, fb);
    fb->buffer      = NULL;
    fb->width       = 0;
    fb->height      = 0;
    fb->pixel_format = PIXEL_FORMAT_MONO;
    fb->width_byte  = 0;
    fb->buffer_size = 0;
    return obj;
}

/* ---- Initialize ---- */
static VALUE
fb_initialize(VALUE self, VALUE rb_width, VALUE rb_height, VALUE rb_format)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    int w = NUM2INT(rb_width);
    int h = NUM2INT(rb_height);

    if (w <= 0 || w > UINT16_MAX)
        rb_raise(rb_eArgError, "width must be between 1 and %d", UINT16_MAX);
    if (h <= 0 || h > UINT16_MAX)
        rb_raise(rb_eArgError, "height must be between 1 and %d", UINT16_MAX);

    fb->width       = (uint16_t)w;
    fb->height      = (uint16_t)h;
    fb->pixel_format = sym_to_pixel_format(rb_format);
    fb->width_byte  = calc_width_byte(fb->width, fb->pixel_format);
    fb->buffer_size = (size_t)fb->width_byte * fb->height;

    fb->buffer = (uint8_t *)xmalloc(fb->buffer_size);

    /* MONO defaults to white (all bits set), others to 0x00 */
    if (fb->pixel_format == PIXEL_FORMAT_MONO)
        memset(fb->buffer, 0xFF, fb->buffer_size);
    else
        memset(fb->buffer, 0x00, fb->buffer_size);

    return self;
}

/* ---- Accessors ---- */
static VALUE
fb_width(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);
    return INT2NUM(fb->width);
}

static VALUE
fb_height(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);
    return INT2NUM(fb->height);
}

static VALUE
fb_buffer_size(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);
    return SIZET2NUM(fb->buffer_size);
}

static VALUE
fb_pixel_format(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);
    return pixel_format_to_sym(fb->pixel_format);
}

/* ---- set_pixel(x, y, color) ---- */
static VALUE
fb_set_pixel(VALUE self, VALUE rb_x, VALUE rb_y, VALUE rb_color)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);

    /* Silent clip on out-of-bounds */
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height)
        return self;

    uint8_t color = (uint8_t)(NUM2INT(rb_color) & 0xFF);
    size_t addr;
    uint8_t rdata;

    switch (fb->pixel_format) {
    case PIXEL_FORMAT_MONO:
        addr = (size_t)(x / 8) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        if (color == 0) /* BLACK: clear bit */
            fb->buffer[addr] = rdata & ~(0x80 >> (x % 8));
        else /* WHITE: set bit */
            fb->buffer[addr] = rdata | (0x80 >> (x % 8));
        break;

    case PIXEL_FORMAT_GRAY4:
        addr = (size_t)(x / 4) + (size_t)y * fb->width_byte;
        color = color & 0x03; /* 2-bit color */
        rdata = fb->buffer[addr];
        rdata = rdata & ~(0xC0 >> ((x % 4) * 2));
        fb->buffer[addr] = rdata | ((color << 6) >> ((x % 4) * 2));
        break;

    case PIXEL_FORMAT_COLOR4:
    case PIXEL_FORMAT_COLOR7:
        addr = (size_t)(x / 2) + (size_t)y * fb->width_byte;
        color = color & 0x0F; /* 4-bit color */
        rdata = fb->buffer[addr];
        rdata = rdata & ~(0xF0 >> ((x % 2) * 4));
        fb->buffer[addr] = rdata | ((color << 4) >> ((x % 2) * 4));
        break;
    }

    return self;
}

/* ---- get_pixel(x, y) ---- */
static VALUE
fb_get_pixel(VALUE self, VALUE rb_x, VALUE rb_y)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);

    /* nil for out-of-bounds */
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height)
        return Qnil;

    size_t addr;
    uint8_t rdata, color;

    switch (fb->pixel_format) {
    case PIXEL_FORMAT_MONO:
        addr = (size_t)(x / 8) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        color = (rdata >> (7 - (x % 8))) & 0x01;
        return INT2NUM(color);

    case PIXEL_FORMAT_GRAY4:
        addr = (size_t)(x / 4) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        color = (rdata >> (6 - (x % 4) * 2)) & 0x03;
        return INT2NUM(color);

    case PIXEL_FORMAT_COLOR4:
    case PIXEL_FORMAT_COLOR7:
        addr = (size_t)(x / 2) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        color = (rdata >> (4 - (x % 2) * 4)) & 0x0F;
        return INT2NUM(color);
    }

    return Qnil; /* unreachable */
}

/* ---- clear(color) ---- */
static VALUE
fb_clear(VALUE self, VALUE rb_color)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    uint8_t c = (uint8_t)(NUM2INT(rb_color) & 0xFF);
    uint8_t fill;

    switch (fb->pixel_format) {
    case PIXEL_FORMAT_MONO:
        fill = (c == 0) ? 0x00 : 0xFF;
        break;
    case PIXEL_FORMAT_GRAY4:
        c = c & 0x03;
        fill = (uint8_t)((c << 6) | (c << 4) | (c << 2) | c);
        break;
    case PIXEL_FORMAT_COLOR4:
    case PIXEL_FORMAT_COLOR7:
        c = c & 0x0F;
        fill = (uint8_t)((c << 4) | c);
        break;
    default:
        fill = 0x00;
        break;
    }

    memset(fb->buffer, fill, fb->buffer_size);
    return self;
}

/* ---- bytes ---- */
static VALUE
fb_bytes(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    VALUE str = rb_str_new((const char *)fb->buffer, (long)fb->buffer_size);
    rb_enc_associate(str, rb_ascii8bit_encoding());
    OBJ_FREEZE(str);
    return str;
}

/* ---- Module init ---- */
void
Init_framebuffer(void)
{
    /* Cache symbol IDs */
    id_mono   = rb_intern("mono");
    id_gray4  = rb_intern("gray4");
    id_color4 = rb_intern("color4");
    id_color7 = rb_intern("color7");

    rb_cFramebuffer = rb_define_class_under(rb_mChromaWave, "Framebuffer", rb_cObject);

    rb_define_alloc_func(rb_cFramebuffer, fb_alloc);
    rb_define_method(rb_cFramebuffer, "initialize", fb_initialize, 3);
    rb_define_method(rb_cFramebuffer, "width",        fb_width,        0);
    rb_define_method(rb_cFramebuffer, "height",       fb_height,       0);
    rb_define_method(rb_cFramebuffer, "buffer_size",  fb_buffer_size,  0);
    rb_define_method(rb_cFramebuffer, "pixel_format", fb_pixel_format, 0);
    rb_define_method(rb_cFramebuffer, "set_pixel",    fb_set_pixel,    3);
    rb_define_method(rb_cFramebuffer, "get_pixel",    fb_get_pixel,    2);
    rb_define_method(rb_cFramebuffer, "clear",        fb_clear,        1);
    rb_define_method(rb_cFramebuffer, "bytes",        fb_bytes,        0);
}
