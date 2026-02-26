#include "chroma_wave.h"

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

    /* Initialize sub-modules */
    Init_framebuffer();
    Init_driver_registry();
}
