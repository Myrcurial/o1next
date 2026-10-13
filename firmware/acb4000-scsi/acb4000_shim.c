/* The host-adapter shim -- layer 2 of the personality (#179).
 *
 * A port block, expressed as data.  This file is the *only* place a Z80 address
 * appears; the target above has never heard of a port and the store below has
 * never heard of a host.
 *
 * The `md10` profile is measured.  Everything in it is read out of the driver
 * rather than guessed:
 *
 *   - the four registers and their roles      docs/acb4000-host-adapter.md 1
 *   - base+2 reading 04h = one controller     docs/acb4000-host-adapter.md 1
 *   - the four status bits the driver polls   docs/acb4000-host-adapter.md 1
 *   - the status byte surviving two reads,    docs/osborne1ng-machine.md 4
 *     the select byte arriving at any time,
 *     the CDB index resetting per command
 *   - controller 01 = SCSI ID 0               docs/osborne1ng-machine.md 4
 *
 * The `reference` profile is the OEM manual's Appendix A model, transcribed and
 * *not* exercised against real software: it is here so that a machine which
 * followed the reference design is a table entry rather than a second driver.
 */
#include "acb4000.h"

#include <string.h>

const acb4000_profile acb4000_profile_md10 = {
    /* name */        "md10",
    /* base */        0x30u,   /* PORTCHNG.COM patches this; 30h is the shipped default */
    /* data_reg */    0,
    /* status_reg */  2,
    /* sel_reg */     2,       /* the overlay writes 10h to base+2 to assert the handshake */
    /* sel_value */   0x10u,
    /* select_mask */ 0x01u,   /* "controller 01", i.e. SCSI ID 0 */
    /* bit_sel */     0x01u,
    /* bit_req */     0x02u,
    /* bit_online */  0x04u,
    /* bit_phase */   0x20u,
    /* bit_end */     0x40u
};

const acb4000_profile acb4000_profile_reference = {
    /* name */        "reference",
    /* base */        0x00u,   /* the manual calls it BASE */
    /* data_reg */    0,
    /* status_reg */  2,
    /* sel_reg */     1,       /* BASE+1 control: SEL 40h */
    /* sel_value */   0x40u,
    /* select_mask */ 0x01u,   /* controller ID 01 */
    /* bit_sel */     0x01u,   /* the card's answer to SEL */
    /* bit_req */     0x80u,   /* REQ */
    /* bit_online */  0x08u,   /* BUSY -- the reference model has no separate on-line bit */
    /* bit_phase */   0x10u,   /* C/D: 1 = command/status/message, 0 = data */
    /* bit_end */     0x20u    /* MSG */
};

void acb4000_shim_init(acb4000_shim *s, const acb4000_profile *p, acb4000_target *t)
{
    memset(s, 0, sizeof *s);
    s->profile = p;
    s->target = t;
    acb4000_shim_reset(s);
}

void acb4000_shim_reset(acb4000_shim *s)
{
    const acb4000_profile *p = s->profile;

    memset(s->reg, 0, sizeof s->reg);
    memset(s->cdb, 0, sizeof s->cdb);
    s->xfer = ACB4000_XFER_IDLE;
    s->cdb_index = s->cdb_length = 0;
    s->select = 0;
    s->last_read = 0;
    s->status_reads = 0;

    /* "One controller on-line" is a property of the card, not of a register the
     * host writes: the presence probe writes 04h to base+2 and reads the on-line
     * bit back out of the status byte (docs/acb4000-host-adapter.md 1). */
    s->online = (s->target != NULL) ? 1 : 0;
    s->reg[p->status_reg] = s->online ? p->bit_online : 0x00u;
}

static uint8_t shim_status(const acb4000_shim *s)
{
    const acb4000_profile *p = s->profile;
    uint8_t st = s->reg[p->status_reg];

    /* base+2 is a read/write register and its controller field only reads back
     * when a controller is really there -- which is what makes the presence
     * probe a probe and not an echo (docs/osborne1ng-machine.md). */
    if (!s->online)
        st &= (uint8_t)~p->bit_online;

    switch (s->xfer) {
    case ACB4000_XFER_IDLE:
        break;
    case ACB4000_XFER_SELECTED:
        st |= p->bit_sel;
        break;
    case ACB4000_XFER_COMMAND:
        st |= p->bit_req | p->bit_phase;
        break;
    case ACB4000_XFER_DATA:
        /* The driver's data-out loop writes a byte for every REQ it sees
         * (overlay 0x808d), and a data-in loop takes a byte until the phase
         * changes -- so REQ is up in both directions and END is up only while
         * the target still has bytes to give. */
        st |= p->bit_req;
        if (s->target != NULL &&
            acb4000_target_phase(s->target) == ACB4000_PHASE_DATA_IN)
            st |= p->bit_end;
        break;
    case ACB4000_XFER_STATUS:
        st |= p->bit_phase | p->bit_end;
        break;
    }
    return st;
}

static void shim_begin_status(acb4000_shim *s)
{
    s->xfer = ACB4000_XFER_STATUS;
    s->status_reads = 0;
}

uint8_t acb4000_shim_read(acb4000_shim *s, int offset)
{
    const acb4000_profile *p = s->profile;
    offset &= 0x03;

    if (offset == p->data_reg) {
        if (s->xfer == ACB4000_XFER_DATA) {
            /* A read only means anything in a data-in phase; during a data-out
             * phase the host is writing, so hand back what was last read. */
            if (s->target != NULL &&
                acb4000_target_phase(s->target) == ACB4000_PHASE_DATA_IN) {
                uint32_t n = acb4000_target_read(s->target, &s->last_read, 1u);
                if (n == 0) {
                    /* The phase had already run out and the driver's loop took
                     * one byte too many: that byte is the status
                     * (docs/osborne1ng-machine.md). */
                    s->last_read = acb4000_target_status(s->target);
                    shim_begin_status(s);
                } else if (acb4000_target_phase(s->target) == ACB4000_PHASE_NONE) {
                    /* ... and this was the last byte of the phase, so the next
                     * poll of the status register must already show the status
                     * phase -- otherwise a data-in loop that polls before it
                     * reads would spin for ever on a REQ with no END. */
                    shim_begin_status(s);
                }
            }
            return s->last_read;
        }
        if (s->xfer == ACB4000_XFER_STATUS) {
            /* ... and the status byte stays up for two reads: the routine reads
             * it into B and then reads the register again to acknowledge. */
            s->last_read = acb4000_target_status(s->target);
            if (s->status_reads < 2)
                s->status_reads++;
            else
                s->xfer = ACB4000_XFER_IDLE;
            return s->last_read;
        }
        s->last_read = 0x00u;
        return s->last_read;
    }

    if (offset == p->status_reg)
        return shim_status(s);

    return 0xFFu;
}


void acb4000_shim_write(acb4000_shim *s, int offset, uint8_t data)
{
    const acb4000_profile *p = s->profile;
    offset &= 0x03;

    if (offset == p->data_reg) {
        switch (s->xfer) {
        case ACB4000_XFER_IDLE:
        case ACB4000_XFER_STATUS:
            /* The select byte can arrive whenever the card is not mid-command --
             * including while the previous command's status is still up, which is
             * what the overlay's ID scan does. */
            s->select = data;
            break;

        case ACB4000_XFER_COMMAND:
            if (s->cdb_index == 0)
                s->cdb_length = acb4000_cdb_length(data);
            if (s->cdb_index < (int)sizeof s->cdb)
                s->cdb[s->cdb_index] = data;
            s->cdb_index++;
            if (s->cdb_index >= s->cdb_length) {
                acb4000_target_command(s->target, s->cdb, s->cdb_length);
                if (acb4000_target_phase(s->target) == ACB4000_PHASE_NONE)
                    shim_begin_status(s);
                else
                    s->xfer = ACB4000_XFER_DATA;
            }
            break;

        case ACB4000_XFER_DATA:
            acb4000_target_write(s->target, &data, 1u);
            if (acb4000_target_phase(s->target) == ACB4000_PHASE_NONE)
                shim_begin_status(s);
            break;

        default:
            break;
        }
        return;
    }

    s->reg[offset] = data;

    if (offset == p->sel_reg) {
        if (data == p->sel_value) {
            /* The host asserted the handshake.  Only a controller whose ID the
             * host selected raises the select bit -- that is what the overlay's
             * ID scan (sla c from 01h) is looking for. */
            if ((s->select & p->select_mask) != 0)
                s->xfer = ACB4000_XFER_SELECTED;
        } else if (data == 0x00u && s->xfer == ACB4000_XFER_SELECTED) {
            /* Released: the command phase starts, and it starts *fresh*.  The
             * driver re-selects and re-enters the routine for every command, so
             * an index left over from the previous one must not be carried in
             * (docs/osborne1ng-machine.md). */
            s->cdb_index = 0;
            s->cdb_length = 0;
            s->xfer = ACB4000_XFER_COMMAND;
        }
    }
}

