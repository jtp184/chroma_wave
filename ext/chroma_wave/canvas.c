#include "chroma_wave.h"
#include "ruby/encoding.h"

VALUE rb_cCanvas;

/* ---- _canvas_clear(buf, r, g, b, a) ---- */
static VALUE
canvas_clear(VALUE self, VALUE rb_buf, VALUE rb_r, VALUE rb_g, VALUE rb_b, VALUE rb_a)
{
    (void)self;

    rb_str_modify(rb_buf);

    uint8_t *buf = (uint8_t *)RSTRING_PTR(rb_buf);
    long len     = RSTRING_LEN(rb_buf);

    uint8_t r = (uint8_t)(NUM2INT(rb_r) & 0xFF);
    uint8_t g = (uint8_t)(NUM2INT(rb_g) & 0xFF);
    uint8_t b = (uint8_t)(NUM2INT(rb_b) & 0xFF);
    uint8_t a = (uint8_t)(NUM2INT(rb_a) & 0xFF);

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

    rb_str_modify(rb_dst);

    uint8_t       *dst = (uint8_t *)RSTRING_PTR(rb_dst);
    const uint8_t *src = (const uint8_t *)RSTRING_PTR(rb_src);
    long dst_len = RSTRING_LEN(rb_dst);
    long src_len = RSTRING_LEN(rb_src);

    int x  = NUM2INT(rb_x);
    int y  = NUM2INT(rb_y);
    int w  = NUM2INT(rb_w);
    int h  = NUM2INT(rb_h);
    int dw = NUM2INT(rb_dw);
    int dh = (int)(dst_len / (dw * 4));

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

/* ---- Init_canvas() ---- */
void
Init_canvas(void)
{
    rb_cCanvas = rb_define_class_under(rb_mChromaWave, "Canvas", rb_cObject);

    rb_define_private_method(rb_cCanvas, "_canvas_clear",      canvas_clear,      5);
    rb_define_private_method(rb_cCanvas, "_canvas_blit_alpha",  canvas_blit_alpha,  8);
    rb_define_private_method(rb_cCanvas, "_canvas_load_rgba",   canvas_load_rgba,   7);
}
