#include "framebuffer.h"
#include "ruby/encoding.h"
#include <ruby/thread.h>

/* Cached symbol ID for pinning framebuffer references in raw_buffer strings */
static ID id_fb_source;

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

const rb_data_type_t framebuffer_type = {
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

    if (w <= 0 || w > EPD_MAX_DIMENSION)
        rb_raise(rb_eArgError, "width must be between 1 and %d", EPD_MAX_DIMENSION);
    if (h <= 0 || h > EPD_MAX_DIMENSION)
        rb_raise(rb_eArgError, "height must be between 1 and %d", EPD_MAX_DIMENSION);

    fb->width       = (uint16_t)w;
    fb->height      = (uint16_t)h;
    fb->pixel_format = cw_sym_to_pixel_format(rb_format);
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

/* ---- initialize_copy (deep-copy for dup/clone) ---- */
static VALUE
fb_initialize_copy(VALUE copy, VALUE orig)
{
    framebuffer_t *fb_copy, *fb_orig;

    if (copy == orig) return copy;

    TypedData_Get_Struct(copy, framebuffer_t, &framebuffer_type, fb_copy);
    TypedData_Get_Struct(orig, framebuffer_t, &framebuffer_type, fb_orig);

    /* Free any existing buffer in the copy */
    if (fb_copy->buffer) {
        xfree(fb_copy->buffer);
        fb_copy->buffer = NULL;
    }

    /* Copy metadata */
    fb_copy->width        = fb_orig->width;
    fb_copy->height       = fb_orig->height;
    fb_copy->pixel_format = fb_orig->pixel_format;
    fb_copy->width_byte   = fb_orig->width_byte;
    fb_copy->buffer_size  = fb_orig->buffer_size;

    /* Deep-copy buffer data */
    if (fb_orig->buffer && fb_orig->buffer_size > 0) {
        fb_copy->buffer = (uint8_t *)xmalloc(fb_orig->buffer_size);
        memcpy(fb_copy->buffer, fb_orig->buffer, fb_orig->buffer_size);
    }

    return copy;
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
    return cw_pixel_format_to_sym(fb->pixel_format);
}

/* ---- Raw pixel helpers (no VALUE overhead, no bounds check) ---- */

/* Reads a raw color index from the framebuffer at (x, y).
 * Caller must ensure x/y are within bounds and buffer is initialized. */
static inline uint8_t
fb_get_pixel_raw(const framebuffer_t *fb, int x, int y)
{
    size_t addr;
    uint8_t rdata;

    switch (fb->pixel_format) {
    case PIXEL_FORMAT_MONO:
        addr = (size_t)(x / 8) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        return (rdata >> (7 - (x % 8))) & 0x01;

    case PIXEL_FORMAT_GRAY4:
        addr = (size_t)(x / 4) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        return (rdata >> (6 - (x % 4) * 2)) & 0x03;

    case PIXEL_FORMAT_COLOR4:
    case PIXEL_FORMAT_COLOR7:
        addr = (size_t)(x / 2) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        return (rdata >> (4 - (x % 2) * 4)) & 0x0F;
    }
    return 0; /* unreachable */
}

/* Writes a raw color index into the framebuffer at (x, y).
 * Caller must ensure x/y are within bounds and buffer is initialized. */
static inline void
fb_set_pixel_raw(framebuffer_t *fb, int x, int y, uint8_t color)
{
    size_t addr;
    uint8_t rdata;

    switch (fb->pixel_format) {
    case PIXEL_FORMAT_MONO:
        addr = (size_t)(x / 8) + (size_t)y * fb->width_byte;
        rdata = fb->buffer[addr];
        if (color == 0)
            fb->buffer[addr] = rdata & ~(0x80 >> (x % 8));
        else
            fb->buffer[addr] = rdata | (0x80 >> (x % 8));
        break;

    case PIXEL_FORMAT_GRAY4:
        addr = (size_t)(x / 4) + (size_t)y * fb->width_byte;
        color = color & 0x03;
        rdata = fb->buffer[addr];
        rdata = rdata & ~(0xC0 >> ((x % 4) * 2));
        fb->buffer[addr] = rdata | ((color << 6) >> ((x % 4) * 2));
        break;

    case PIXEL_FORMAT_COLOR4:
    case PIXEL_FORMAT_COLOR7:
        addr = (size_t)(x / 2) + (size_t)y * fb->width_byte;
        color = color & 0x0F;
        rdata = fb->buffer[addr];
        rdata = rdata & ~(0xF0 >> ((x % 2) * 4));
        fb->buffer[addr] = rdata | ((color << 4) >> ((x % 2) * 4));
        break;
    }
}

/* ---- set_pixel(x, y, color) ---- */
static VALUE
fb_set_pixel(VALUE self, VALUE rb_x, VALUE rb_y, VALUE rb_color)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    if (!fb->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);

    /* Silent clip on out-of-bounds */
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height)
        return self;

    uint8_t color = (uint8_t)(NUM2INT(rb_color) & 0xFF);
    fb_set_pixel_raw(fb, x, y, color);
    return self;
}

/* ---- get_pixel(x, y) ---- */
static VALUE
fb_get_pixel(VALUE self, VALUE rb_x, VALUE rb_y)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    if (!fb->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);

    /* nil for out-of-bounds */
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height)
        return Qnil;

    return INT2NUM(fb_get_pixel_raw(fb, x, y));
}

/* ---- clear(color) ---- */
static VALUE
fb_clear(VALUE self, VALUE rb_color)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    if (!fb->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

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

/* ---- rotate(degrees) ---- */

/* Arguments for the GVL-released rotation worker. */
typedef struct {
    const framebuffer_t *src;
    framebuffer_t *dst;
    uint16_t dst_w;
    uint16_t dst_h;
    int degrees;
} rotate_args_t;

/* Pure-C rotation loop — called without the GVL. */
static void *
fb_rotate_worker(void *arg)
{
    rotate_args_t *ra = (rotate_args_t *)arg;
    const framebuffer_t *src = ra->src;
    framebuffer_t *dst = ra->dst;
    uint16_t dst_w = ra->dst_w;
    uint16_t dst_h = ra->dst_h;
    int degrees = ra->degrees;

    int sx, sy, dx = 0, dy = 0;
    for (sy = 0; sy < src->height; sy++) {
        for (sx = 0; sx < src->width; sx++) {
            uint8_t color = fb_get_pixel_raw(src, sx, sy);

            switch (degrees) {
            case 90:
                dx = dst_w - 1 - sy;
                dy = sx;
                break;
            case 180:
                dx = dst_w - 1 - sx;
                dy = dst_h - 1 - sy;
                break;
            case 270:
                dx = sy;
                dy = dst_h - 1 - sx;
                break;
            default: break;
            }

            fb_set_pixel_raw(dst, dx, dy, color);
        }
    }

    return NULL;
}

/*
 * call-seq:
 *   rotate(degrees) -> Framebuffer
 *
 * Returns a new Framebuffer whose pixels are rotated clockwise by
 * +degrees+ (must be 0, 90, 180, or 270).
 *
 * A 0° rotation returns a +dup+. For 90° and 270° the destination
 * dimensions are swapped (width ↔ height). The pixel format is
 * preserved.
 *
 * The pixel-copy loop runs without the GVL so other Ruby threads
 * can proceed concurrently.
 *
 * @param degrees [Integer] rotation angle (0, 90, 180, or 270)
 * @return [Framebuffer] a new, rotated framebuffer
 * @raise [ArgumentError] if +degrees+ is not a valid rotation
 */
static VALUE
fb_rotate(VALUE self, VALUE rb_degrees)
{
    framebuffer_t *src;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, src);

    if (!src->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    int degrees = NUM2INT(rb_degrees);
    if (degrees != 0 && degrees != 90 && degrees != 180 && degrees != 270)
        rb_raise(rb_eArgError, "rotation must be 0, 90, 180, or 270 (got %d)", degrees);

    /* 0°: return a dup */
    if (degrees == 0)
        return rb_obj_dup(self);

    /* Compute destination dimensions */
    uint16_t dst_w, dst_h;
    if (degrees == 90 || degrees == 270) {
        dst_w = src->height;
        dst_h = src->width;
    } else { /* 180 */
        dst_w = src->width;
        dst_h = src->height;
    }

    /* Create new Framebuffer via rb_class_new_instance so
     * PixelFormatBridge fires and @pixel_format_obj is set up. */
    VALUE argv[3];
    argv[0] = INT2NUM(dst_w);
    argv[1] = INT2NUM(dst_h);
    argv[2] = cw_pixel_format_to_sym(src->pixel_format);
    VALUE dst_obj = rb_class_new_instance(3, argv, rb_obj_class(self));

    framebuffer_t *dst;
    TypedData_Get_Struct(dst_obj, framebuffer_t, &framebuffer_type, dst);

    /* Run the pixel loop without the GVL so other Ruby threads can proceed. */
    rotate_args_t ra = {
        .src = src,
        .dst = dst,
        .dst_w = dst_w,
        .dst_h = dst_h,
        .degrees = degrees,
    };
    rb_thread_call_without_gvl(fb_rotate_worker, &ra, RUBY_UBF_IO, NULL);

    return dst_obj;
}

/* ---- extract(x, y, width, height) ---- */

/* Arguments for the GVL-released extraction worker. */
typedef struct {
    const framebuffer_t *src;
    framebuffer_t *dst;
    int src_x;
    int src_y;
} extract_args_t;

/* Pure-C extraction loop — called without the GVL. */
static void *
fb_extract_worker(void *arg)
{
    extract_args_t *ea = (extract_args_t *)arg;
    const framebuffer_t *src = ea->src;
    framebuffer_t *dst = ea->dst;
    int src_x = ea->src_x;
    int src_y = ea->src_y;

    int dx, dy;
    for (dy = 0; dy < dst->height; dy++) {
        for (dx = 0; dx < dst->width; dx++) {
            uint8_t color = fb_get_pixel_raw(src, src_x + dx, src_y + dy);
            fb_set_pixel_raw(dst, dx, dy, color);
        }
    }

    return NULL;
}

/*
 * call-seq:
 *   extract(x, y, width, height) -> Framebuffer
 *
 * Returns a new Framebuffer containing the sub-region starting at
 * (+x+, +y+) with the given +width+ and +height+. The pixel format
 * is preserved.
 *
 * Raises ArgumentError if the region exceeds the framebuffer bounds
 * or if dimensions are not positive.
 *
 * The pixel-copy loop runs without the GVL so other Ruby threads
 * can proceed concurrently.
 *
 * @param x [Integer] left edge of the extraction region
 * @param y [Integer] top edge of the extraction region
 * @param width [Integer] region width in pixels
 * @param height [Integer] region height in pixels
 * @return [Framebuffer] a new framebuffer containing the sub-region
 * @raise [ArgumentError] if the region is invalid or out of bounds
 */
static VALUE
fb_extract(VALUE self, VALUE rb_x, VALUE rb_y, VALUE rb_w, VALUE rb_h)
{
    framebuffer_t *src;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, src);

    if (!src->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);
    int w = NUM2INT(rb_w);
    int h = NUM2INT(rb_h);

    if (w <= 0 || h <= 0)
        rb_raise(rb_eArgError,
                 "extract dimensions must be positive (got %dx%d)", w, h);
    if (x < 0 || y < 0 || x + w > src->width || y + h > src->height)
        rb_raise(rb_eArgError,
                 "extract region (%d,%d %dx%d) exceeds framebuffer "
                 "bounds (%dx%d)",
                 x, y, w, h, src->width, src->height);

    /* Create new Framebuffer via rb_class_new_instance so
     * PixelFormatBridge fires and @pixel_format_obj is set up. */
    VALUE argv[3];
    argv[0] = INT2NUM(w);
    argv[1] = INT2NUM(h);
    argv[2] = cw_pixel_format_to_sym(src->pixel_format);
    VALUE dst_obj = rb_class_new_instance(3, argv, rb_obj_class(self));

    framebuffer_t *dst;
    TypedData_Get_Struct(dst_obj, framebuffer_t, &framebuffer_type, dst);

    /* Run the pixel loop without the GVL so other Ruby threads can proceed. */
    extract_args_t ea = {
        .src = src,
        .dst = dst,
        .src_x = x,
        .src_y = y,
    };
    rb_thread_call_without_gvl(fb_extract_worker, &ea, RUBY_UBF_IO, NULL);

    return dst_obj;
}

/* ---- _fb_blit(source, x, y) ---- */

/* Arguments for the GVL-released blit worker. */
typedef struct {
    const framebuffer_t *src;
    framebuffer_t *dst;
    int dst_x;
    int dst_y;
} blit_args_t;

/* Pure-C blit loop — called without the GVL.
 * Copies all pixels from src into dst at the given offset,
 * clipping to dst bounds. Both framebuffers must share the
 * same pixel format. */
static void *
fb_blit_worker(void *arg)
{
    blit_args_t *ba = (blit_args_t *)arg;
    const framebuffer_t *src = ba->src;
    framebuffer_t *dst = ba->dst;
    int dst_x = ba->dst_x;
    int dst_y = ba->dst_y;

    /* Compute clipped source region */
    int sx_start = (dst_x < 0) ? -dst_x : 0;
    int sy_start = (dst_y < 0) ? -dst_y : 0;
    int sx_end = src->width;
    int sy_end = src->height;

    if (dst_x + sx_end > dst->width)
        sx_end = dst->width - dst_x;
    if (dst_y + sy_end > dst->height)
        sy_end = dst->height - dst_y;

    int sx, sy;
    for (sy = sy_start; sy < sy_end; sy++) {
        for (sx = sx_start; sx < sx_end; sx++) {
            uint8_t color = fb_get_pixel_raw(src, sx, sy);
            fb_set_pixel_raw(dst, dst_x + sx, dst_y + sy, color);
        }
    }

    return NULL;
}

/*
 * call-seq:
 *   _fb_blit(source, x, y) -> self
 *
 * Copies all pixels from +source+ into this framebuffer at offset
 * (+x+, +y+), clipping to bounds. Both framebuffers must share the
 * same pixel format.
 *
 * The pixel-copy loop runs without the GVL so other Ruby threads
 * can proceed concurrently.
 *
 * This is a private accelerator called by the Ruby +blit+ method
 * when the source is a Framebuffer with matching format.
 *
 * @param source [Framebuffer] the source framebuffer
 * @param x [Integer] destination x offset
 * @param y [Integer] destination y offset
 * @return [self]
 * @raise [ChromaWaveError] if either framebuffer is not initialized
 * @raise [ArgumentError] if pixel formats do not match
 */
static VALUE
fb_blit(VALUE self, VALUE rb_source, VALUE rb_x, VALUE rb_y)
{
    framebuffer_t *dst;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, dst);

    if (!dst->buffer)
        rb_raise(rb_eChromaWaveError, "destination framebuffer not initialized");

    if (!rb_typeddata_is_kind_of(rb_source, &framebuffer_type))
        rb_raise(rb_eTypeError, "source must be a Framebuffer");

    framebuffer_t *src;
    TypedData_Get_Struct(rb_source, framebuffer_t, &framebuffer_type, src);

    if (!src->buffer)
        rb_raise(rb_eChromaWaveError, "source framebuffer not initialized");

    if (src->pixel_format != dst->pixel_format)
        rb_raise(rb_eArgError, "pixel formats must match for blit");

    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);

    /* Early exit if completely out of bounds */
    if (x >= dst->width || y >= dst->height ||
        x + src->width <= 0 || y + src->height <= 0)
        return self;

    blit_args_t ba = {
        .src = src,
        .dst = dst,
        .dst_x = x,
        .dst_y = y,
    };
    rb_thread_call_without_gvl(fb_blit_worker, &ba, RUBY_UBF_IO, NULL);

    return self;
}

/* ---- bytes ---- */
static VALUE
fb_bytes(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    if (!fb->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    VALUE str = rb_str_new((const char *)fb->buffer, (long)fb->buffer_size);
    rb_enc_associate(str, rb_ascii8bit_encoding());
    OBJ_FREEZE(str);
    return str;
}

/* ---- raw_buffer (no-copy, read-only view) ---- */
static VALUE
fb_raw_buffer(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    if (!fb->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    /* Wrap the C buffer without copying.  The string is frozen so Ruby
     * code cannot mutate the underlying buffer directly.
     *
     * Pin the Framebuffer by storing a back-reference on the string.
     * This creates a GC edge (String → Framebuffer) that prevents the
     * Framebuffer from being collected while the string is still alive,
     * avoiding a use-after-free on the underlying buffer.
     *
     * Note: the buffer contents may change via set_pixel/clear on the
     * Framebuffer; callers should treat the string as a transient view. */
    VALUE str = rb_str_new_static((const char *)fb->buffer, (long)fb->buffer_size);
    rb_enc_associate(str, rb_ascii8bit_encoding());
    rb_ivar_set(str, id_fb_source, self);
    OBJ_FREEZE(str);
    return str;
}

/* ---- equality ---- */
static VALUE
fb_eq(VALUE self, VALUE other)
{
    framebuffer_t *fb_a, *fb_b;

    if (!rb_typeddata_is_kind_of(other, &framebuffer_type))
        return Qfalse;

    TypedData_Get_Struct(self,  framebuffer_t, &framebuffer_type, fb_a);
    TypedData_Get_Struct(other, framebuffer_t, &framebuffer_type, fb_b);

    if (!fb_a->buffer || !fb_b->buffer) {
        rb_raise(rb_eChromaWaveError, "framebuffer not initialized");
    }

    if (fb_a->width != fb_b->width ||
        fb_a->height != fb_b->height ||
        fb_a->pixel_format != fb_b->pixel_format)
        return Qfalse;

    if (memcmp(fb_a->buffer, fb_b->buffer, fb_a->buffer_size) != 0)
        return Qfalse;

    return Qtrue;
}

/* ---- inspect ---- */
static const char *
pixel_format_name(pixel_format_t fmt)
{
    switch (fmt) {
    case PIXEL_FORMAT_MONO:   return "mono";
    case PIXEL_FORMAT_GRAY4:  return "gray4";
    case PIXEL_FORMAT_COLOR4: return "color4";
    case PIXEL_FORMAT_COLOR7: return "color7";
    }
    return "unknown";
}

static VALUE
fb_inspect(VALUE self)
{
    framebuffer_t *fb;
    TypedData_Get_Struct(self, framebuffer_t, &framebuffer_type, fb);

    return rb_sprintf("#<ChromaWave::Framebuffer %dx%d %s (%"PRIuSIZE" bytes)>",
                      fb->width, fb->height,
                      pixel_format_name(fb->pixel_format),
                      fb->buffer_size);
}

/* ---- Module init ---- */
void
Init_framebuffer(void)
{
    id_fb_source = rb_intern("@__fb_source__");

    rb_cFramebuffer = rb_define_class_under(rb_mChromaWave, "Framebuffer", rb_cObject);

    rb_define_alloc_func(rb_cFramebuffer, fb_alloc);
    rb_define_method(rb_cFramebuffer, "initialize",      fb_initialize,      3);
    rb_define_method(rb_cFramebuffer, "initialize_copy", fb_initialize_copy, 1);
    rb_define_method(rb_cFramebuffer, "width",           fb_width,           0);
    rb_define_method(rb_cFramebuffer, "height",          fb_height,          0);
    rb_define_method(rb_cFramebuffer, "buffer_size",     fb_buffer_size,     0);
    rb_define_method(rb_cFramebuffer, "pixel_format",    fb_pixel_format,    0);
    rb_define_method(rb_cFramebuffer, "set_pixel",       fb_set_pixel,       3);
    rb_define_method(rb_cFramebuffer, "get_pixel",       fb_get_pixel,       2);
    rb_define_method(rb_cFramebuffer, "clear",           fb_clear,           1);
    rb_define_method(rb_cFramebuffer, "rotate",          fb_rotate,          1);
    rb_define_method(rb_cFramebuffer, "extract",         fb_extract,         4);
    rb_define_private_method(rb_cFramebuffer, "_fb_blit", fb_blit,           3);
    rb_define_method(rb_cFramebuffer, "bytes",           fb_bytes,           0);
    rb_define_method(rb_cFramebuffer, "raw_buffer",      fb_raw_buffer,      0);
    rb_define_method(rb_cFramebuffer, "==",              fb_eq,              1);
    rb_define_method(rb_cFramebuffer, "inspect",         fb_inspect,         0);
}
