/*
 * The interposer's own board: the bare RP2354B, not a module (#286).
 *
 * Every other board header in the Pico SDK describes a module.  The interposer
 * carries the bare B part on a custom PCB, so this file says what that part is
 * and nothing else -- there is no board LED, no default UART, I2C or SPI pin,
 * because hardware/interposer/revb/README.md allocates all 48 GPIO itself and a
 * "default pin" here would be a pin that is really something else.
 *
 * Two things are worth stating rather than leaving to the SDK's defaults:
 *
 *   - the flash is the B part's **2 MB in-package** flash, which is the
 *     firmware store (#192's media decision).  The A-part boards say 4 MB.
 *   - the GPIO count is the B part's 48.  The SDK's platform.h already defines
 *     the A/B selector as 0 (the B package) when no board header sets it, so
 *     this file deliberately does not set it: the default is the correct answer
 *     for this board, and setting it would be the one place in the tree that
 *     spells the A part's name (tools/check_part_numbers.py forbids that).
 *
 * SPDX-License-Identifier: MIT
 */

// -----------------------------------------------------
// NOTE: THIS HEADER IS ALSO INCLUDED BY ASSEMBLER SO
//       SHOULD ONLY CONSIST OF PREPROCESSOR DIRECTIVES
// -----------------------------------------------------

#ifndef _BOARDS_O1NEXT_INTERPOSER_H
#define _BOARDS_O1NEXT_INTERPOSER_H

pico_board_cmake_set(PICO_PLATFORM, rp2350)

// For board detection
#define O1NEXT_INTERPOSER

// --- GPIO ---
// 48 GPIO: the B package.  Left at the SDK default (0 = B part); see the header
// comment.  hardware/interposer/revb/README.md is the allocation.

// --- FLASH ---
// 2 MB in-package flash (RP2354B).  This is the firmware store, not a library
// medium (#192).
pico_board_cmake_set_default(PICO_FLASH_SIZE_BYTES, (2 * 1024 * 1024))
#ifndef PICO_FLASH_SIZE_BYTES
#define PICO_FLASH_SIZE_BYTES (2 * 1024 * 1024)
#endif

// --- LED ---
// There is no LED on the board, and this header does not invent one.  The Rev B
// pin map's spare pin is GP37; the smoke firmware's heartbeat is on GP26 for a
// reason that belongs to the emulator, not the board (#286).

#endif
