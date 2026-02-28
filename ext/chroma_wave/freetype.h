#ifndef CHROMA_WAVE_FREETYPE_H
#define CHROMA_WAVE_FREETYPE_H

#include "chroma_wave.h"

#ifndef NO_FREETYPE

#include <ft2build.h>
#include FT_FREETYPE_H

/* Wrapped struct for a loaded FreeType face */
typedef struct {
    FT_Face face;
    int     pixel_size;
} cw_font_face_t;

/* TypedData descriptor (extern for use in Init and method functions) */
extern const rb_data_type_t font_face_type;

#endif /* NO_FREETYPE */

/* Ruby class VALUE for ChromaWave::Font */
extern VALUE rb_cFont;

/* Initialize FreeType bindings (called from Init_chroma_wave) */
void Init_freetype(void);

#endif /* CHROMA_WAVE_FREETYPE_H */
