# mount-com — MOUNT.COM image-library utility (CP/M)

In-machine companion to the interposer web UI: mount `.IMD`/`.HFE`
images from the Pico-hosted library to drive A, B, or "Drive C" without
touching a browser.

Tracks: #27; speaks the interposer mailbox (`docs/mailbox-protocol.md`, #155);
ships on the updated boot disk (#28).

## Definition

- CP/M 2.2 utility, assembly or compact C, tiny TPA footprint.
- Talks to the Pico through the mailbox port pair — `0E7h`/`0EBh`,
  `docs/mailbox-protocol.md` §2.
- Commands (UX TBD): list library, mount image → drive, unmount,
  status. One-shot command-line style, consistent with `FATCOPY`.
- Graceful behavior on a machine with no interposer present (probe
  mailbox, clean error).

## Deliverables

- `MOUNT.COM` + source
- Usage doc (ships on boot disk)
