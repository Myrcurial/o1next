# floppy-emulator — floppy interposer + image library (RP2354B)

Gotek/FlashFloppy analogue built into the interposer: interrupt the
Shugart bus between motherboard and drives; mount `.IMD`/`.HFE` images
to either drive bay, or to "Drive C" as a persistent RAM disk. The
hardest firmware component — Greaseweazle/FlashFloppy-class timing.

Tracks: #20; the DD/G2 format position is settled in
`docs/dd-upgrade-formats.md` (#95); physical integration with
`hardware/floppy-adapter/`.

## Definition

- MFM flux read/write emulation on PIO, pinned to core1; WiFi gated
  during flux windows (radio-jitter note, `firmware/README.md`).
- Image library in flash/SD, managed over WiFi (web UI) or from CP/M
  via `MOUNT.COM` (`software/mount-com/`).
- **Must not *assume* Osborne geometry** — replay what the image says (an
  `.HFE` carries the track layout) rather than hard-coding one format's
  parameters. Synthesising a blank foreign diskette is out of scope:
  foreign media is converted on the modern side before it is mounted
  (#95, `docs/dd-upgrade-formats.md`).
- Coexistence rules with the physical Gotek/drive adapter
  (`hardware/floppy-adapter/`) — which device owns the bus in each
  configuration must be documented and enforced.

## Deliverables

- PIO flux engine + Shugart bus drive logic
- `.IMD` / `.HFE` image handling
- Mailbox port protocol spec for `MOUNT.COM` — specified in
  `docs/mailbox-protocol.md` (#155); this personality implements its
  image-library commands
- Web-UI mount/library endpoints
