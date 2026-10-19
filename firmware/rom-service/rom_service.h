/* The ROM service -- the ROM's own class of the mailbox protocol (#284, #192).
 *
 * The second client of the same firmware.  `docs/mailbox-protocol.md` defines the
 * channel a CP/M program reaches at I/O `0E7h`/`0EBh` (#155, for `MOUNT.COM`);
 * ROM 2.0's monitor runs before any CP/M exists, in bank 2, and reaches the *same*
 * protocol through the bank-2 register pair `2800h`/`2801h`
 * (`docs/rom-pico-protocol.md` section 2, #247 step 8).  The two doors differ only
 * in their register layout, so this class is written once and answers on both.
 *
 * What the class is for now is the *protocol*, not the picture
 * ------------------------------------------------------------
 * `PRESENT` had four content ids and three of them are gone: `1` and `2` served
 * the boot frame's two halves and `3` the screen's own code, and **#278 retired
 * all three** when the RP2354B became the display -- it reads the animation out of
 * its own flash and the Z80's whole role is the trigger.  So `PRESENT(0)`, the
 * payload, is the one id left, and `1`, `2` and `3` answer `09h`, "no such
 * content" (section 4.2), exactly as the emulator's `softrom_device` already does.
 *
 * The payload is a port, not an asset
 * -----------------------------------
 * The payload -- CBIOS + MD-10 BIOS image + the hand-over stub, 3599 bytes -- is
 * what window page 1 holds, and this module does not own it: it is handed in, as a
 * pointer and a length, the same way `media.h` hands the library a medium.  On the
 * board that pointer is into the RP2354B's own **XIP flash**, where a pointer *is*
 * the read; on the host the suite hands in the bytes `tools/research/rom2image.py`
 * assembled from the repo's own archive, so the test proves the module serves *the*
 * payload rather than a fixture that happens to fit.
 *
 * A module that is handed no payload answers `06h` (media error -- section 4.2's
 * "a flash read that failed") rather than pretending to present one.
 *
 * What this module is not
 * -----------------------
 * It is not the window.  Page 0 is the monitor and page 1 the payload, and *which*
 * page the window serves is the softROM's business (`softrom_device`), not this
 * class's; `PRESENT` says which content the door wants, and `rs_present()` hands
 * the bytes to whoever fills the page.
 */
#ifndef O1_ROM_SERVICE_H
#define O1_ROM_SERVICE_H

#include <stdint.h>

#include "mailbox.h"

/* ------------------------------------------------------------- the command set
 *
 * `docs/rom-pico-protocol.md` section 4, verbatim: the class is `40h-4Fh`, and two
 * of its sixteen slots are used.  The space is partitioned by device class so that
 * this client adds a class rather than a protocol revision (mailbox-protocol.md
 * section 4).
 */
#define RS_OP_PRESENT 0x40u   /* content id u8; the reply is the result code alone */
#define RS_OP_INFO    0x41u   /* no operands; version u8, flags u8 */

/* The content ids (section 4).  One is left; the other three retired with the
 * ROM-side frame path (#278) and answer `09h`. */
#define RS_CONTENT_PAYLOAD 0u   /* CBIOS + MD-10 BIOS image + the hand-over stub */

/* `INFO`'s reply payload.  The flags byte is `00h` and stays in the reply because
 * the reply's *shape* is the protocol's: there is no asset slot left to report. */
#define RS_INFO_VERSION 0x01u
#define RS_INFO_FLAGS   0x00u

/* ------------------------------------------------------------------- the doors
 *
 * The engine owns these numbers -- "one engine, two doors" (mailbox.h) -- so the
 * ROM service *names* them rather than defining a second copy that could drift: a
 * measurement on hardware moves one line in mailbox.h and both clients with it.
 * The suite pins all four to the protocol's numbers, so a drift fails here.
 *
 * The userland pair is `= 3 (mod 4)` on purpose (every port on this machine aliases
 * one of `00h`-`03h`, the bank latch); the ROM pair is a bank-2 register decoded
 * precisely by `A8-A15`, which is why the busy console path does not touch it --
 * and why the door is `2800h` and not `2300h`, which is the floppy's track register
 * as well as the keyboard's row 0 (section 2, measured).
 */
#define RS_DOOR_USER_WRITE MB_DOOR_USER_WRITE   /* 00E7h */
#define RS_DOOR_USER_READ  MB_DOOR_USER_READ    /* 00EBh */
#define RS_DOOR_ROM_WRITE  MB_DOOR_ROM_WRITE    /* 2800h */
#define RS_DOOR_ROM_READ   MB_DOOR_ROM_READ     /* 2801h */

/* ----------------------------------------------------------------- the payload
 *
 * `bytes` is the payload's first byte -- on the board, an address in XIP flash --
 * and `len` is its length.  A NULL `bytes` or a zero `len` is "no payload", which
 * `PRESENT(0)` answers `06h` to.
 */
typedef struct {
    const uint8_t *bytes;
    uint32_t       len;
} rom_payload;

typedef struct {
    rom_payload  payload;
    mb_extension ext;      /* the vtable the engine calls; `ctx` is this struct */
} rom_service;

/* `payload` may be NULL, and then the module has nothing to present.  The payload
 * is not copied -- keep it alive. */
void rs_init(rom_service *rs, const rom_payload *payload);

/* The vtable to hand `mb_init()`.  Valid until the next `rs_init()` on the same
 * struct, and it must outlive the mailbox: `mb_init` does not copy it. */
const mb_extension *rs_extension(rom_service *rs);

/* `PRESENT`: the content id -> the payload's length and bytes.
 *
 * Returns `LIB_OK` and, if the out-parameters are non-NULL, the payload's bytes and
 * length; `LIB_ERR_CONTENT` (`09h`) for an id that retired with the frame path; or
 * `LIB_ERR_MEDIA` (`06h`) when there is no payload to present.
 *
 * **The out-parameters are written only on `LIB_OK`**, which is what makes the
 * "leaves page 1 alone" rule (section 4.2) one line instead of a caller's promise:
 * a client that keeps whatever it had passes NULL and reads nothing. */
int rs_present(const rom_service *rs, uint8_t id, const uint8_t **bytes, uint32_t *len);

#endif /* O1_ROM_SERVICE_H */
