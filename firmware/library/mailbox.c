/* The mailbox engine -- see mailbox.h for the contract and the two notes (#283).
 *
 * Everything here is a state machine over single bytes, because that is what the
 * protocol is: the Z80 is the only thing that initiates, so there are no
 * interrupts, no DMA and no FIFOs to size.
 */
#include "mailbox.h"

#include <string.h>

/* ------------------------------------------------------------------ the reply */

static void reply_code(mailbox *mb, uint8_t code)
{
    /* A reply is never empty: `0` means "not ready" on the wire, so even NOP
     * answers with the one-byte result code (section 3, rule 3). */
    mb->reply.len      = 1u;
    mb->reply.data[0]  = code;
    mb->reply_pos      = 0u;   /* the length has not gone out yet */
    mb->have_reply     = 1;
}

static void reply_byte(mailbox *mb, uint8_t b)
{
    if (mb->reply.len < MB_REPLY_MAX)
        mb->reply.data[mb->reply.len++] = b;
}

static void reply_record(mailbox *mb, const lib_record *rec)
{
    uint8_t  wire[LIB_RECORD_LEN];
    unsigned i;

    lib_record_encode(rec, wire);
    for (i = 0; i < LIB_RECORD_LEN; i++)
        reply_byte(mb, wire[i]);
}

static unsigned operand_u16(const uint8_t *p)
{
    return (unsigned)p[0] | ((unsigned)p[1] << 8);   /* little-endian */
}

/* -------------------------------------------------------------- the opcode set */

static unsigned opcode_operands(mailbox *mb, uint8_t opcode)
{
    switch (opcode) {
    case MB_OP_NOP:     return 0u;
    case MB_OP_ECHO:    return 1u;
    case MB_OP_ID:      return 0u;
    case MB_OP_COUNT:   return 0u;
    case MB_OP_GET:     return 2u;   /* index, u16 little-endian */
    case MB_OP_MOUNT:   return 3u;   /* index u16, then the drive */
    case MB_OP_UNMOUNT: return 1u;   /* the drive */
    case MB_OP_DSTATUS: return 1u;   /* the drive */
    default:            break;
    }
    /* The second client's classes -- the clock (#18), the ROM service (#284). */
    if (mb->extension != NULL && mb->extension->operands != NULL)
        return mb->extension->operands(mb->extension->ctx, opcode);
    return MB_UNKNOWN;
}

static void execute(mailbox *mb)
{
    lib_record rec;
    unsigned   index;
    unsigned   drive;
    int        rc;

    switch (mb->opcode) {
    case MB_OP_NOP:
        /* The reset: abandon a partial request and answer OK, so there is always
         * a way back to a known state. */
        reply_code(mb, LIB_OK);
        return;

    case MB_OP_ECHO:
        /* The presence probe (section 3): an absent interposer leaves the port
         * answering the floating bus, so the host sends a byte twice with two
         * patterns and requires both back. */
        reply_code(mb, LIB_OK);
        reply_byte(mb, mb->operand[0]);
        return;

    case MB_OP_ID:
        reply_code(mb, LIB_OK);
        reply_byte(mb, MB_PROTOCOL_VERSION);
        reply_byte(mb, MB_DEVICE_ID);
        return;

    case MB_OP_COUNT: {
        unsigned n = lib_count(mb->library);
        reply_code(mb, LIB_OK);
        reply_byte(mb, (uint8_t)(n & 0xFFu));
        reply_byte(mb, (uint8_t)((n >> 8) & 0xFFu));
        return;
    }

    case MB_OP_GET:
        index = operand_u16(mb->operand);
        rc = lib_get(mb->library, index, &rec);
        reply_code(mb, (uint8_t)rc);
        if (rc == LIB_OK)
            reply_record(mb, &rec);     /* always 24 bytes, so the reply is 25 */
        return;

    case MB_OP_MOUNT:
        index = operand_u16(mb->operand);
        drive = mb->operand[2];
        rc = lib_mount(mb->library, index, drive);
        reply_code(mb, (uint8_t)rc);
        if (rc == LIB_OK)
            reply_byte(mb, (uint8_t)lib_drive_state(mb->library, drive));
        return;

    case MB_OP_UNMOUNT:
        drive = mb->operand[0];
        rc = lib_unmount(mb->library, drive);
        reply_code(mb, (uint8_t)rc);
        if (rc == LIB_OK)
            reply_byte(mb, (uint8_t)lib_drive_state(mb->library, drive));
        return;

    case MB_OP_DSTATUS: {
        unsigned entry = 0;
        unsigned state;
        uint8_t  flags = 0;

        drive = mb->operand[0];
        state = (unsigned)lib_drive_state(mb->library, drive);
        if (state == LIB_ERR_DRIVE) {           /* out of range is the only error */
            reply_code(mb, LIB_ERR_DRIVE);
            return;
        }
        /* An empty drive is a *valid answer*, not an error: this is the status
         * query, and "nothing mounted" is the status.  (UNMOUNT is where `08h`
         * belongs -- asking to eject nothing is the mistake.) */
        if (lib_drive_entry(mb->library, drive, &entry) == LIB_OK) {
            if (lib_get(mb->library, entry, &rec) == LIB_OK)
                flags = rec.flags;
        } else {
            entry = LIB_DRIVE_NONE;
        }
        reply_code(mb, LIB_OK);
        reply_byte(mb, (uint8_t)state);
        reply_byte(mb, (uint8_t)(entry & 0xFFu));
        reply_byte(mb, (uint8_t)((entry >> 8) & 0xFFu));
        reply_byte(mb, flags);
        return;
    }

    default:
        break;
    }

    /* Not ours -- the extension's, if it wants it. */
    if (mb->extension != NULL && mb->extension->run != NULL &&
        mb->extension->run(mb->extension->ctx, mb->opcode, mb->operand,
                           &mb->reply)) {
        if (mb->reply.len == 0u)
            /* An extension that claims an opcode and produces no reply would
             * wedge the host on a register that reads 0 for ever, so it gets the
             * one answer the protocol guarantees is never empty. */
            mb->reply.len = 1u;
        mb->reply_pos  = 0u;
        mb->have_reply = 1;
        return;
    }

    reply_code(mb, LIB_ERR_OPCODE);
}

/* ------------------------------------------------------------------ the engine */

void mb_init(mailbox *mb, lib *library, const mb_extension *extension)
{
    memset(mb, 0, sizeof *mb);
    mb->library   = library;
    mb->extension = extension;
    mb->want      = 0u;             /* an opcode is next */
}

void mb_write(mailbox *mb, uint8_t byte)
{
    if (mb->have_reply) {
        /* Section 3, rule 4: a write while a reply is pending abandons it and
         * starts a new transaction.  That is the recovery path -- a wedged host
         * cannot wedge the firmware. */
        mb->have_reply = 0;
        mb->reply_pos  = 0u;
        mb->reply.len  = 0u;
        mb->noperand   = 0u;
        mb->want       = 0u;
    }

    if (mb->want == 0u) {
        /* an opcode */
        mb->opcode   = byte;
        mb->noperand = 0u;
        mb->want     = opcode_operands(mb, byte);

        if (mb->want == MB_UNKNOWN || mb->want > (unsigned)sizeof mb->operand) {
            /* Unknown, or a class that wants more operands than this engine
             * buffers -- either way, `01h` and the operand count resets. */
            mb->want = 0u;
            reply_code(mb, LIB_ERR_OPCODE);
            return;
        }
        if (mb->want == 0u) {
            execute(mb);
            mb->want = 0u;
        }
        return;
    }

    mb->operand[mb->noperand++] = byte;
    if (mb->noperand == mb->want) {
        mb->want = 0u;
        execute(mb);
    }
}

int mb_read(mailbox *mb, uint8_t *out)
{
    if (out == NULL || !mb->have_reply)
        return 0;

    if (mb->reply_pos == 0u) {
        /* The length goes out first, and it is never 0 (reply_code guarantees it). */
        mb->reply_pos = 1u;
        *out = mb->reply.len;
        return 1;
    }

    if (mb->reply_pos <= mb->reply.len) {
        *out = mb->reply.data[mb->reply_pos - 1u];
        mb->reply_pos++;
        if (mb->reply_pos > mb->reply.len) {
            mb->have_reply = 0;      /* consumed: the register reads 0 again */
            mb->reply_pos  = 0u;
        }
        return 1;
    }

    return 0;
}
