/* The mailbox engine -- the interposer's command channel (#283, #192).
 *
 * One engine, two doors.  `docs/mailbox-protocol.md` defines the channel a CP/M
 * program reaches at I/O `0E7h`/`0EBh` (#155, for `MOUNT.COM`); the ROM's own
 * client reaches the *same* protocol through the bank-2 register pair
 * `2800h`/`2801h` (`docs/rom-pico-protocol.md` section 2, #247 step 8).  The
 * doors differ only in their register layout, so this module is door-agnostic: a
 * firmware module that implements one client implements both.
 *
 * The transaction (section 3), which is what the state machine below is:
 *
 *   1. the host writes the opcode, then its operands, one write per byte;
 *   2. the host polls the reply register: 0 = not ready, else N = the length;
 *   3. the next N reads are the reply bytes, `reply[0]` a result code;
 *   4. a write while a reply is pending abandons it and starts a new transaction.
 *
 * Rule 4 is the recovery path, and it is why the engine cannot be wedged: a host
 * that loses track writes `NOP` (or anything) and is back in a known state.  An
 * opcode the firmware does not know is answered `01h` and resets the operand
 * count, which is the other half of the same guarantee.
 *
 * Two notes worth having in writing, because both look like bugs otherwise:
 *
 * - **Result code `02h`, "wrong operand count", is unreachable here.**  The engine
 *   is operand-count-driven: it consumes exactly as many operands as the opcode
 *   takes and executes, so a count can never be wrong.  The code is in the table
 *   because the protocol defines it, not because this implementation can raise
 *   it.  (A host that sends too few simply never completes a transaction; one that
 *   sends too many gets the extra bytes treated as the next request's opcode.)
 * - **On an error the reply is the result code alone.**  Section 4 gives each
 *   command a payload, and the payload is what a *successful* answer carries;
 *   there is no defined payload for a failure, so none is invented.
 */
#ifndef O1_MAILBOX_H
#define O1_MAILBOX_H

#include <stddef.h>
#include <stdint.h>

#include "library.h"

/* ------------------------------------------------------------------- the doors
 *
 * Firmware constants, one line each, exactly as the two protocol documents call
 * them: if a measurement on hardware says otherwise, these move and the clients
 * move with them and nothing else does.
 *
 * The userland pair is `= 3 (mod 4)` on purpose -- every port on this machine
 * aliases one of `00h`-`03h` (the bank latch), so a leaked write from a port that
 * is 3 mod 4 is `Clear BIT 9`, which is idempotent.  The ROM pair is a bank-2
 * register, decoded precisely by `A8-A15`, so the busy console path (which writes
 * `OUT (02h)`/`(03h)` about 150 times a second) is untouched.
 */
#define MB_DOOR_USER_WRITE 0x00E7u
#define MB_DOOR_USER_READ  0x00EBu
#define MB_DOOR_ROM_WRITE  0x2800u
#define MB_DOOR_ROM_READ   0x2801u

/* ----------------------------------------------------------------- the opcodes
 *
 * Partitioned by device class so that a second client is a new class rather than
 * a protocol revision (section 4).
 */
#define MB_OP_NOP      0x00u
#define MB_OP_ECHO     0x01u
#define MB_OP_ID       0x02u

#define MB_OP_COUNT    0x10u   /* image library (#20, #27) */
#define MB_OP_GET      0x11u
#define MB_OP_MOUNT    0x12u
#define MB_OP_UNMOUNT  0x13u
#define MB_OP_DSTATUS  0x14u

/* 20h-2Fh is the clock (#18) and 40h-4Fh the ROM service (#284).  Neither is
 * here: both arrive through `mb_extension` when they exist, so this module does
 * not grow a clock it cannot source or a payload it does not own. */

#define MB_PROTOCOL_VERSION 0x01u
#define MB_DEVICE_ID        0x01u   /* the interposer */

/* A reply is bounded at 255 by the protocol; 32 is what this command set needs
 * (the largest is GET: a result code plus a 24-byte record) and it keeps the
 * engine's footprint honest. */
#define MB_REPLY_MAX 32u

/* "I do not own this opcode" -- the operand-count query's answer. */
#define MB_UNKNOWN 0xFFu

typedef struct {
    uint8_t len;
    uint8_t data[MB_REPLY_MAX];
} mb_reply;

/* --------------------------------------------------------------- the extension
 *
 * The second client's classes plug in here.  `operands()` answers MB_UNKNOWN for
 * an opcode it does not own, so the engine answers `01h` for it exactly as it
 * would for any unknown opcode; `run()` fills the reply and returns 1 if it
 * handled the opcode.  Both may be NULL, and then the engine owns every opcode it
 * knows and refuses the rest.
 */
typedef struct {
    unsigned (*operands)(void *ctx, uint8_t opcode);
    int      (*run)(void *ctx, uint8_t opcode, const uint8_t *operand, mb_reply *out);
    void     *ctx;
} mb_extension;

/* ---------------------------------------------------------------- the engine */

typedef struct {
    lib                 *library;
    const mb_extension  *extension;   /* may be NULL */

    /* the request being assembled */
    uint8_t   opcode;
    uint8_t   operand[8];
    unsigned  noperand;
    unsigned  want;                   /* operands still to come; 0 = opcode next */

    /* the reply being handed out */
    mb_reply  reply;
    unsigned  reply_pos;              /* 0 = the length has not gone out yet */
    int       have_reply;
} mailbox;

void mb_init(mailbox *mb, lib *library, const mb_extension *extension);

/* One byte written to either door's request register. */
void mb_write(mailbox *mb, uint8_t byte);

/* One byte read from either door's reply register.  Returns 1 if a byte was
 * produced, 0 if the reply register reads 0 (not ready) -- so a caller that
 * wants the protocol's semantics writes 0 and ignores the byte. */
int mb_read(mailbox *mb, uint8_t *out);

#endif /* O1_MAILBOX_H */
