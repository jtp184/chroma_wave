#include "freetype.h"
#include "ruby/encoding.h"

VALUE rb_cFont;

#ifndef NO_FREETYPE

/* ---- FT_Library singleton ---- */

static FT_Library ft_library = NULL;

/* Cleanup callback registered via rb_set_end_proc */
static void
ft_library_cleanup(VALUE _unused)
{
    (void)_unused;
    if (ft_library) {
        FT_Done_FreeType(ft_library);
        ft_library = NULL;
    }
}

/* Lazily initialize the global FT_Library on first use */
static void
ft_ensure_library(void)
{
    if (ft_library) return;

    FT_Error err = FT_Init_FreeType(&ft_library);
    if (err) {
        ft_library = NULL;
        rb_raise(rb_eChromaWaveError,
                 "FreeType initialization failed (FT error %d)", err);
    }

    rb_set_end_proc(ft_library_cleanup, Qnil);
}

/* ---- TypedData for cw_font_face_t ---- */

static void
font_face_free(void *ptr)
{
    cw_font_face_t *face_data = ptr;
    /* Only free the face if the library is still alive.
     * During Ruby shutdown, GC may finalize Font objects after
     * the end-proc has already destroyed the FT_Library. Calling
     * FT_Done_Face on a dead library segfaults. */
    if (face_data->face && ft_library) {
        FT_Done_Face(face_data->face);
        face_data->face = NULL;
    }
    xfree(face_data);
}

static size_t
font_face_memsize(const void *ptr)
{
    const cw_font_face_t *face_data = ptr;
    size_t size = sizeof(cw_font_face_t);

    /* Include the parsed font file size so Ruby's GC has better
     * pressure estimates. FT_Face holds 50KB-2MB of parsed data. */
    if (face_data->face && face_data->face->stream)
        size += face_data->face->stream->size;

    return size;
}

const rb_data_type_t font_face_type = {
    .wrap_struct_name = "ChromaWave::Font/FT_Face",
    .function = {
        .dmark  = NULL,
        .dfree  = font_face_free,
        .dsize  = font_face_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* Allocator for Font objects */
static VALUE
font_alloc(VALUE klass)
{
    cw_font_face_t *face_data;
    VALUE obj = TypedData_Make_Struct(klass, cw_font_face_t,
                                     &font_face_type, face_data);
    face_data->face       = NULL;
    face_data->pixel_size = 0;
    return obj;
}

/* ---- Helper to extract face_data with NULL check ---- */

static cw_font_face_t *
get_face_data(VALUE self)
{
    cw_font_face_t *face_data;
    TypedData_Get_Struct(self, cw_font_face_t, &font_face_type, face_data);

    if (!face_data->face) {
        rb_raise(rb_eChromaWaveError, "font face not loaded (call _ft_load_face first)");
    }
    return face_data;
}

/* Validate and convert a Ruby Integer to a non-negative codepoint.
 * NUM2ULONG silently accepts negatives, so we guard explicitly. */
static FT_ULong
codepoint_from_value(VALUE rb_codepoint)
{
    if (FIXNUM_P(rb_codepoint) && FIX2LONG(rb_codepoint) < 0) {
        rb_raise(rb_eArgError, "codepoint must be non-negative");
    }
    return NUM2ULONG(rb_codepoint);
}

/* ---- Private C methods on ChromaWave::Font ---- */

/*
 * _ft_load_face(path, size) → self
 *
 * Loads a TrueType font file and sets the pixel size.
 *
 * path: String — absolute path to a .ttf file
 * size: Integer — pixel size for rendering
 */
static VALUE
ft_load_face(VALUE self, VALUE rb_path, VALUE rb_size)
{
    ft_ensure_library();

    Check_Type(rb_path, T_STRING);
    const char *path = StringValueCStr(rb_path);
    int size = NUM2INT(rb_size);

    if (size <= 0) {
        rb_raise(rb_eArgError, "size must be positive, got %d", size);
    }

    cw_font_face_t *face_data;
    TypedData_Get_Struct(self, cw_font_face_t, &font_face_type, face_data);

    /* Free any previously loaded face */
    if (face_data->face) {
        FT_Done_Face(face_data->face);
        face_data->face = NULL;
    }

    FT_Error err = FT_New_Face(ft_library, path, 0, &face_data->face);
    if (err) {
        face_data->face = NULL;
        rb_raise(rb_eArgError,
                 "failed to load font '%s' (FT error %d)", path, err);
    }

    err = FT_Set_Pixel_Sizes(face_data->face, 0, (FT_UInt)size);
    if (err) {
        FT_Done_Face(face_data->face);
        face_data->face = NULL;
        rb_raise(rb_eArgError,
                 "failed to set pixel size %d (FT error %d)", size, err);
    }

    face_data->pixel_size = size;
    return self;
}

/*
 * _ft_render_glyph(codepoint) → Hash
 *
 * Renders a glyph and returns its bitmap and metrics.
 *
 * Returns Hash with keys:
 *   :bitmap    — ASCII-8BIT String (1 byte per pixel, grayscale alpha 0–255)
 *   :width     — Integer (bitmap width in pixels)
 *   :height    — Integer (bitmap height in pixels)
 *   :bearing_x — Integer (horizontal bearing)
 *   :bearing_y — Integer (vertical bearing, positive = above baseline)
 *   :advance_x — Integer (horizontal advance to next glyph)
 */
static VALUE
ft_render_glyph(VALUE self, VALUE rb_codepoint)
{
    cw_font_face_t *face_data = get_face_data(self);
    FT_ULong codepoint = codepoint_from_value(rb_codepoint);

    FT_UInt glyph_index = FT_Get_Char_Index(face_data->face, codepoint);

    FT_Error err = FT_Load_Glyph(face_data->face, glyph_index, FT_LOAD_DEFAULT);
    if (err) {
        rb_raise(rb_eChromaWaveError,
                 "failed to load glyph for codepoint %lu (FT error %d)",
                 codepoint, err);
    }

    err = FT_Render_Glyph(face_data->face->glyph, FT_RENDER_MODE_NORMAL);
    if (err) {
        rb_raise(rb_eChromaWaveError,
                 "failed to render glyph for codepoint %lu (FT error %d)",
                 codepoint, err);
    }

    FT_GlyphSlot slot = face_data->face->glyph;
    FT_Bitmap *bmp = &slot->bitmap;

    unsigned int w = bmp->width;
    unsigned int h = bmp->rows;
    size_t buf_size = (size_t)w * h;

    /* Create bitmap string with pitch-aware row copy */
    VALUE rb_bitmap = rb_str_new(NULL, (long)buf_size);
    rb_enc_associate(rb_bitmap, rb_ascii8bit_encoding());
    uint8_t *dst = (uint8_t *)RSTRING_PTR(rb_bitmap);

    if (buf_size > 0) {
        int pitch = bmp->pitch;
        const uint8_t *src = bmp->buffer;
        for (unsigned int row = 0; row < h; row++) {
            memcpy(dst + (size_t)row * w, src + (size_t)row * pitch, w);
        }
    }

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("bitmap")),    rb_bitmap);
    rb_hash_aset(result, ID2SYM(rb_intern("width")),     UINT2NUM(w));
    rb_hash_aset(result, ID2SYM(rb_intern("height")),    UINT2NUM(h));
    rb_hash_aset(result, ID2SYM(rb_intern("bearing_x")), INT2NUM(slot->bitmap_left));
    rb_hash_aset(result, ID2SYM(rb_intern("bearing_y")), INT2NUM(slot->bitmap_top));
    rb_hash_aset(result, ID2SYM(rb_intern("advance_x")), INT2NUM(slot->advance.x >> 6));

    return result;
}

/*
 * _ft_glyph_metrics(codepoint) → Hash
 *
 * Returns glyph metrics without rendering.
 *
 * Returns Hash with keys:
 *   :advance_x — Integer (horizontal advance)
 *   :bearing_x — Integer (horizontal bearing)
 *   :bearing_y — Integer (vertical bearing)
 *   :width     — Integer (glyph width)
 *   :height    — Integer (glyph height)
 */
static VALUE
ft_glyph_metrics(VALUE self, VALUE rb_codepoint)
{
    cw_font_face_t *face_data = get_face_data(self);
    FT_ULong codepoint = codepoint_from_value(rb_codepoint);

    FT_UInt glyph_index = FT_Get_Char_Index(face_data->face, codepoint);

    FT_Error err = FT_Load_Glyph(face_data->face, glyph_index, FT_LOAD_DEFAULT);
    if (err) {
        rb_raise(rb_eChromaWaveError,
                 "failed to load glyph metrics for codepoint %lu (FT error %d)",
                 codepoint, err);
    }

    FT_Glyph_Metrics *m = &face_data->face->glyph->metrics;

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("advance_x")), INT2NUM(m->horiAdvance >> 6));
    rb_hash_aset(result, ID2SYM(rb_intern("bearing_x")), INT2NUM(m->horiBearingX >> 6));
    rb_hash_aset(result, ID2SYM(rb_intern("bearing_y")), INT2NUM(m->horiBearingY >> 6));
    rb_hash_aset(result, ID2SYM(rb_intern("width")),     INT2NUM(m->width >> 6));
    rb_hash_aset(result, ID2SYM(rb_intern("height")),    INT2NUM(m->height >> 6));

    return result;
}

/*
 * _ft_line_height → Integer
 *
 * Returns the line height (ascender - descender) in pixels.
 */
static VALUE
ft_line_height(VALUE self)
{
    cw_font_face_t *face_data = get_face_data(self);
    FT_Size_Metrics *sm = &face_data->face->size->metrics;

    return INT2NUM((sm->ascender - sm->descender) >> 6);
}

/*
 * _ft_ascent → Integer
 *
 * Returns the ascent (distance from baseline to top) in pixels.
 */
static VALUE
ft_ascent(VALUE self)
{
    cw_font_face_t *face_data = get_face_data(self);
    return INT2NUM(face_data->face->size->metrics.ascender >> 6);
}

/*
 * _ft_descent → Integer
 *
 * Returns the descent (distance from baseline to bottom) in pixels.
 * Returns a positive value (the absolute distance below baseline).
 */
static VALUE
ft_descent(VALUE self)
{
    cw_font_face_t *face_data = get_face_data(self);
    /* descender is negative in FreeType, negate to return positive */
    return INT2NUM(-(face_data->face->size->metrics.descender >> 6));
}

#endif /* NO_FREETYPE */

/* ---- Init_freetype() ---- */

void
Init_freetype(void)
{
    rb_cFont = rb_define_class_under(rb_mChromaWave, "Font", rb_cObject);

#ifndef NO_FREETYPE
    rb_define_alloc_func(rb_cFont, font_alloc);

    rb_define_private_method(rb_cFont, "_ft_load_face",     ft_load_face,     2);
    rb_define_private_method(rb_cFont, "_ft_render_glyph",  ft_render_glyph,  1);
    rb_define_private_method(rb_cFont, "_ft_glyph_metrics", ft_glyph_metrics, 1);
    rb_define_private_method(rb_cFont, "_ft_line_height",   ft_line_height,   0);
    rb_define_private_method(rb_cFont, "_ft_ascent",        ft_ascent,        0);
    rb_define_private_method(rb_cFont, "_ft_descent",       ft_descent,       0);
#endif
}
