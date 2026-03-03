#ifndef VENDOR_DEBUG_H
#define VENDOR_DEBUG_H

/*
 * Override the Waveshare vendor Debug() macro to route through Ruby's
 * warning system (rb_warn) instead of printf/stderr.
 *
 * This header is force-included via -include in extconf.rb before any
 * other headers. It defines the vendor's include guard (__DEBUG_H) to
 * prevent the original Debug.h from taking effect.
 *
 * Unlike the original Debug.h (which is a no-op unless -DDEBUG is
 * set at compile time), this replacement always emits through
 * rb_warn(). Ruby's warning level controls visibility at runtime:
 *   -W0 / $VERBOSE=nil  silences these messages
 *   -W1 / $VERBOSE=false (default) shows them
 *   Warning.warn can intercept them programmatically
 *
 * Vendor format strings use \r\n line endings for raw printf output.
 * cw_vendor_debug() strips trailing \r\n before routing to rb_warn(),
 * which appends its own newline.
 */

/* Block vendor Debug.h from being processed */
#define __DEBUG_H

#include <ruby.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

/* Format a vendor debug message, strip trailing \r\n, and emit
 * through Ruby's warning system.
 *
 * Uses vsnprintf for formatting (standard C printf semantics) then
 * passes the result to rb_warn via %s — avoiding any rb_sprintf
 * format quirks (e.g. PRIsVALUE hijacking %i). */
static inline void
cw_vendor_debug(const char *fmt, ...)
{
    char buf[256];
    va_list ap;
    int len;

    va_start(ap, fmt);
    len = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (len < 0) return;
    if ((size_t)len >= sizeof(buf)) len = (int)(sizeof(buf) - 1);

    /* Strip trailing \r and \n from vendor format strings */
    while (len > 0 && (buf[len - 1] == '\r' || buf[len - 1] == '\n'))
        buf[--len] = '\0';

    rb_warn("ChromaWave [vendor]: %s", buf);
}

/* Redirect vendor debug output to Ruby's warning system */
#define Debug(fmt, ...) cw_vendor_debug(fmt, ##__VA_ARGS__)

#endif /* VENDOR_DEBUG_H */
