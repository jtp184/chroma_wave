#include "chroma_wave.h"

/* ---- Cached symbol IDs for pixel format conversion ---- */
static ID id_mono, id_gray4, id_color4, id_color7;

/* Convert a Ruby Symbol (:mono, :gray4, :color4, :color7) to pixel_format_t.
 * Raises ArgumentError for unrecognized symbols. */
pixel_format_t
cw_sym_to_pixel_format(VALUE sym)
{
    ID id = SYM2ID(sym);

    if (id == id_mono)   return PIXEL_FORMAT_MONO;
    if (id == id_gray4)  return PIXEL_FORMAT_GRAY4;
    if (id == id_color4) return PIXEL_FORMAT_COLOR4;
    if (id == id_color7) return PIXEL_FORMAT_COLOR7;

    rb_raise(rb_eArgError,
             "unknown pixel format: %"PRIsVALUE
             " (expected :mono, :gray4, :color4, or :color7)",
             sym);
    return 0; /* unreachable */
}

/* Convert pixel_format_t to a Ruby Symbol. */
VALUE
cw_pixel_format_to_sym(pixel_format_t fmt)
{
    switch (fmt) {
    case PIXEL_FORMAT_MONO:   return ID2SYM(id_mono);
    case PIXEL_FORMAT_GRAY4:  return ID2SYM(id_gray4);
    case PIXEL_FORMAT_COLOR4: return ID2SYM(id_color4);
    case PIXEL_FORMAT_COLOR7: return ID2SYM(id_color7);
    }
    return Qnil; /* unreachable */
}

/* Module and class VALUE definitions */
VALUE rb_mChromaWave;
VALUE rb_mChromaWaveNative;
VALUE rb_cFramebuffer;
VALUE rb_eChromaWaveError;
VALUE rb_eDeviceError;
VALUE rb_eInitError;
VALUE rb_eBusyTimeoutError;
VALUE rb_eSPIError;
VALUE rb_eDependencyError;
VALUE rb_eFormatMismatchError;
VALUE rb_eModelNotFoundError;

RUBY_FUNC_EXPORTED void
Init_chroma_wave(void)
{
    /* Cache symbol IDs for pixel format conversion */
    id_mono   = rb_intern("mono");
    id_gray4  = rb_intern("gray4");
    id_color4 = rb_intern("color4");
    id_color7 = rb_intern("color7");

    /* Top-level module */
    rb_mChromaWave = rb_define_module("ChromaWave");

    /* Native sub-module for C-level helpers */
    rb_mChromaWaveNative = rb_define_module_under(rb_mChromaWave, "Native");

    /* Error hierarchy */
    rb_eChromaWaveError     = rb_define_class_under(rb_mChromaWave, "Error",               rb_eStandardError);
    rb_eDeviceError         = rb_define_class_under(rb_mChromaWave, "DeviceError",          rb_eChromaWaveError);
    rb_eInitError           = rb_define_class_under(rb_mChromaWave, "InitError",            rb_eDeviceError);
    rb_eBusyTimeoutError    = rb_define_class_under(rb_mChromaWave, "BusyTimeoutError",     rb_eDeviceError);
    rb_eSPIError            = rb_define_class_under(rb_mChromaWave, "SPIError",             rb_eDeviceError);
    rb_eDependencyError     = rb_define_class_under(rb_mChromaWave, "DependencyError",      rb_eChromaWaveError);
    rb_eFormatMismatchError = rb_define_class_under(rb_mChromaWave, "FormatMismatchError",  rb_eArgError);
    rb_eModelNotFoundError  = rb_define_class_under(rb_mChromaWave, "ModelNotFoundError",   rb_eArgError);

    /* Mode constants on Native */
    rb_define_const(rb_mChromaWaveNative, "MODE_FULL",      INT2NUM(0));
    rb_define_const(rb_mChromaWaveNative, "MODE_FAST",      INT2NUM(1));
    rb_define_const(rb_mChromaWaveNative, "MODE_PARTIAL",   INT2NUM(2));
    rb_define_const(rb_mChromaWaveNative, "MODE_GRAYSCALE", INT2NUM(3));

    /* Initialize sub-modules */
    Init_framebuffer();
    Init_driver_registry();
    Init_canvas();
    Init_device();
    Init_freetype();
}
