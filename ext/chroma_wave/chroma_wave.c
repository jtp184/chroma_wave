#include "chroma_wave.h"

VALUE rb_mChromaWave;

RUBY_FUNC_EXPORTED void
Init_chroma_wave(void)
{
  rb_mChromaWave = rb_define_module("ChromaWave");
}
