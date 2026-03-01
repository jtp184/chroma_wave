#include "chroma_wave.h"
#include "ruby/encoding.h"

/* ---- Helper: validate 0..255 color channel ---- */
static inline uint8_t
cw_channel_value(VALUE rb_val, const char *name)
{
    int v = NUM2INT(rb_val);
    if (v < 0 || v > 255) {
        rb_raise(rb_eArgError, "%s must be 0..255, got %d", name, v);
    }
    return (uint8_t)v;
}

VALUE rb_cCanvas;

/* ---- _canvas_clear(buf, r, g, b, a) ---- */
static VALUE
canvas_clear(VALUE self, VALUE rb_buf, VALUE rb_r, VALUE rb_g, VALUE rb_b, VALUE rb_a)
{
    (void)self;

    Check_Type(rb_buf, T_STRING);
    rb_str_modify(rb_buf);

    uint8_t *buf = (uint8_t *)RSTRING_PTR(rb_buf);
    long len     = RSTRING_LEN(rb_buf);

    if (len % 4 != 0) {
        rb_raise(rb_eArgError, "buffer length must be a multiple of 4 (got %ld)", len);
    }

    uint8_t r = cw_channel_value(rb_r, "red");
    uint8_t g = cw_channel_value(rb_g, "green");
    uint8_t b = cw_channel_value(rb_b, "blue");
    uint8_t a = cw_channel_value(rb_a, "alpha");

    uint8_t stamp[4] = { r, g, b, a };

    for (long i = 0; i < len; i += 4) {
        memcpy(buf + i, stamp, 4);
    }

    return Qnil;
}

/* ---- _canvas_blit_alpha(dst, src, dx, dy, sw, sh, dw, dh) ----
 *
 * Alpha-composited blit from src onto dst.
 * Integer alpha blending: (s*a + d*(255-a) + 127) / 255
 */
static VALUE
canvas_blit_alpha(VALUE self,
                  VALUE rb_dst, VALUE rb_src,
                  VALUE rb_dx, VALUE rb_dy,
                  VALUE rb_sw, VALUE rb_sh,
                  VALUE rb_dw, VALUE rb_dh)
{
    (void)self;

    Check_Type(rb_dst, T_STRING);
    Check_Type(rb_src, T_STRING);
    rb_str_modify(rb_dst);

    uint8_t       *dst = (uint8_t *)RSTRING_PTR(rb_dst);
    const uint8_t *src = (const uint8_t *)RSTRING_PTR(rb_src);
    long dst_len = RSTRING_LEN(rb_dst);
    long src_len = RSTRING_LEN(rb_src);

    int dx = NUM2INT(rb_dx);
    int dy = NUM2INT(rb_dy);
    int sw = NUM2INT(rb_sw);
    int sh = NUM2INT(rb_sh);
    int dw = NUM2INT(rb_dw);
    int dh = NUM2INT(rb_dh);

    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 ||
        sw > EPD_MAX_DIMENSION || sh > EPD_MAX_DIMENSION ||
        dw > EPD_MAX_DIMENSION || dh > EPD_MAX_DIMENSION) {
        return Qnil;
    }

    for (int sy = 0; sy < sh; sy++) {
        int dest_y = dy + sy;
        if (dest_y < 0 || dest_y >= dh) continue;

        for (int sx = 0; sx < sw; sx++) {
            int dest_x = dx + sx;
            if (dest_x < 0 || dest_x >= dw) continue;

            long s_off = ((long)sy * sw + sx) * 4;
            long d_off = ((long)dest_y * dw + dest_x) * 4;

            if (s_off + 3 >= src_len || d_off + 3 >= dst_len) continue;

            uint8_t sa = src[s_off + 3];

            if (sa == 0) continue; /* fully transparent — skip */

            if (sa == 255) {
                /* fully opaque — direct copy */
                memcpy(dst + d_off, src + s_off, 4);
            } else {
                /* semi-transparent — alpha blend */
                uint8_t inv_a = 255 - sa;
                dst[d_off + 0] = (uint8_t)((src[s_off + 0] * sa + dst[d_off + 0] * inv_a + 127) / 255);
                dst[d_off + 1] = (uint8_t)((src[s_off + 1] * sa + dst[d_off + 1] * inv_a + 127) / 255);
                dst[d_off + 2] = (uint8_t)((src[s_off + 2] * sa + dst[d_off + 2] * inv_a + 127) / 255);
                dst[d_off + 3] = 255; /* result is always opaque */
            }
        }
    }

    return Qnil;
}

/* ---- _canvas_load_rgba(dst, src, x, y, w, h, dw) ----
 *
 * Bulk-load raw RGBA bytes into a rectangular region with clipping.
 */
static VALUE
canvas_load_rgba(VALUE self,
                 VALUE rb_dst, VALUE rb_src,
                 VALUE rb_x, VALUE rb_y,
                 VALUE rb_w, VALUE rb_h,
                 VALUE rb_dw)
{
    (void)self;

    Check_Type(rb_dst, T_STRING);
    Check_Type(rb_src, T_STRING);
    rb_str_modify(rb_dst);

    int dw = NUM2INT(rb_dw);
    if (dw <= 0) return Qnil;

    uint8_t       *dst = (uint8_t *)RSTRING_PTR(rb_dst);
    const uint8_t *src = (const uint8_t *)RSTRING_PTR(rb_src);
    long dst_len = RSTRING_LEN(rb_dst);
    long src_len = RSTRING_LEN(rb_src);

    int x  = NUM2INT(rb_x);
    int y  = NUM2INT(rb_y);
    int w  = NUM2INT(rb_w);
    int h  = NUM2INT(rb_h);

    if (w <= 0 || h <= 0) return Qnil;
    if (w > EPD_MAX_DIMENSION || h > EPD_MAX_DIMENSION) return Qnil;

    int dh = (int)(dst_len / 4 / dw);

    int src_row_bytes = w * 4;

    for (int sy = 0; sy < h; sy++) {
        int dest_y = y + sy;
        if (dest_y < 0 || dest_y >= dh) continue;

        int dx_start = (0 > -x) ? 0 : -x;
        int dx_end   = (w < (dw - x)) ? w : (dw - x);
        if (dx_start >= dx_end) continue;

        long s_off   = (long)sy * src_row_bytes + (long)dx_start * 4;
        long d_off   = ((long)dest_y * dw + x + dx_start) * 4;
        long copy_len = (long)(dx_end - dx_start) * 4;

        if (s_off + copy_len > src_len) continue;
        if (d_off + copy_len > dst_len) continue;

        memcpy(dst + d_off, src + s_off, (size_t)copy_len);
    }

    return Qnil;
}

/* ---- _canvas_blit_glyph(buf, bitmap, gx, gy, gw, gh, dw, dh, r, g, b) ----
 *
 * Alpha-composites a glyph bitmap onto a Canvas RGBA buffer.
 *
 * buf    – Canvas RGBA buffer String (modified in-place)
 * bitmap – glyph alpha bitmap String (1 byte per pixel, 0–255)
 * gx, gy – destination position on canvas
 * gw, gh – glyph dimensions in pixels
 * dw, dh – canvas dimensions in pixels
 * r,g,b  – foreground colour RGB (0–255 each)
 *
 * Per-pixel: skip alpha==0, direct write alpha==255, else integer blend:
 *   (fg * alpha + bg * (255 - alpha) + 127) / 255
 */
static VALUE
canvas_blit_glyph(VALUE self,
                  VALUE rb_buf, VALUE rb_bmp,
                  VALUE rb_gx, VALUE rb_gy,
                  VALUE rb_gw, VALUE rb_gh,
                  VALUE rb_dw, VALUE rb_dh,
                  VALUE rb_r, VALUE rb_g, VALUE rb_b)
{
    (void)self;

    Check_Type(rb_buf, T_STRING);
    Check_Type(rb_bmp, T_STRING);
    rb_str_modify(rb_buf);

    uint8_t       *dst = (uint8_t *)RSTRING_PTR(rb_buf);
    const uint8_t *bmp = (const uint8_t *)RSTRING_PTR(rb_bmp);
    long dst_len = RSTRING_LEN(rb_buf);
    long bmp_len = RSTRING_LEN(rb_bmp);

    int gx = NUM2INT(rb_gx);
    int gy = NUM2INT(rb_gy);
    int gw = NUM2INT(rb_gw);
    int gh = NUM2INT(rb_gh);
    int dw = NUM2INT(rb_dw);
    int dh = NUM2INT(rb_dh);

    uint8_t fr = cw_channel_value(rb_r, "red");
    uint8_t fg = cw_channel_value(rb_g, "green");
    uint8_t fb = cw_channel_value(rb_b, "blue");

    if (gw <= 0 || gh <= 0 || dw <= 0 || dh <= 0) return Qnil;

    for (int row = 0; row < gh; row++) {
        int dest_y = gy + row;
        if (dest_y < 0 || dest_y >= dh) continue;

        for (int col = 0; col < gw; col++) {
            int dest_x = gx + col;
            if (dest_x < 0 || dest_x >= dw) continue;

            long b_off = (long)row * gw + col;
            if (b_off >= bmp_len) continue;

            uint8_t alpha = bmp[b_off];
            if (alpha == 0) continue;

            long d_off = ((long)dest_y * dw + dest_x) * 4;
            if (d_off + 3 >= dst_len) continue;

            if (alpha == 255) {
                dst[d_off + 0] = fr;
                dst[d_off + 1] = fg;
                dst[d_off + 2] = fb;
                dst[d_off + 3] = 255;
            } else {
                uint8_t inv = 255 - alpha;
                dst[d_off + 0] = (uint8_t)((fr * alpha + dst[d_off + 0] * inv + 127) / 255);
                dst[d_off + 1] = (uint8_t)((fg * alpha + dst[d_off + 1] * inv + 127) / 255);
                dst[d_off + 2] = (uint8_t)((fb * alpha + dst[d_off + 2] * inv + 127) / 255);
                dst[d_off + 3] = 255;
            }
        }
    }

    return Qnil;
}

/* ---- Init_canvas() ---- */
void
Init_canvas(void)
{
    rb_cCanvas = rb_define_class_under(rb_mChromaWave, "Canvas", rb_cObject);

    rb_define_private_method(rb_cCanvas, "_canvas_clear",      canvas_clear,      5);
    rb_define_private_method(rb_cCanvas, "_canvas_blit_alpha",  canvas_blit_alpha,  8);
    rb_define_private_method(rb_cCanvas, "_canvas_load_rgba",   canvas_load_rgba,   7);
    rb_define_private_method(rb_cCanvas, "_canvas_blit_glyph",  canvas_blit_glyph,  11);
}
