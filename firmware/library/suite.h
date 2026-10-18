/* The checks that must hold for *any* media set (#285).
 *
 * #285's acceptance is that a host-backed media implementation "passes the same
 * suite as the fixture one, so the library cannot tell them apart".  The way to
 * mean that is to have one suite and run it twice: `test_library.c` runs it over a
 * directory tree, `test_fatfs.c` runs it over three real FAT volumes, and neither
 * gets to relax an assertion because its medium is different.
 *
 * **The fixture is part of the contract.**  Both suites build the same eight
 * entries with the same names, sizes and kinds -- a duplicate name to prove the
 * merge, an invalid Drive C blob to prove `VALID`, an invalid copy with a valid one
 * below it to prove the fallback, a long name to prove LFN, and a `printer/` PDF
 * and a `.txt` that must not appear at all.  Change one fixture and you change
 * both, or this stops meaning anything.
 *
 * What is *not* here: the protocol's own edge cases (the abandon rule, the operand
 * that looks like an opcode, the entry cap) are media-independent by construction
 * -- they never reach a medium -- so they live in `test_library.c` once.
 */
#ifndef O1_SUITE_H
#define O1_SUITE_H

#include "media.h"

/* Run the shared suite over `order` (in precedence order).  Returns the number of
 * failed checks, printing each one.  `label` names the media set in the output
 * ("directory", "fatfs"). */
int suite_media(const media *const *order, unsigned nmedia, const char *label);

#endif /* O1_SUITE_H */
