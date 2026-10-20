# trace-analyzer — host-side bus trace capture/analysis (planned)

Host companion to `firmware/bus-analyzer/` (#17): capture the USB trace
stream, decode it into cycle logs, filter, annotate.

## Definition (to be built with the analyzer firmware)

- Capture CLI: USB CDC stream → raw/`.vcd`/decoded text formats.
- Decoder: Z80 bus cycles (opcode fetch, mem R/W, I/O R/W, INT ack),
  with address-range and port filters mirroring the firmware's
  triggers; /RFSH already filtered on-device (counts preserved).
- Annotation: symbol/address labels (BIOS entry points, peripheral
  port bases from `docs/o1-memory-io-map.md`) to make CoPower-88 and
  Drive C bring-up legible.
- Streaming protocol spec shared with the firmware (versioned).

## The envelope already exists — do not invent a second one

`#o1next-trace` is defined in
[`../../firmware/bench-bridge/README.md`](../../firmware/bench-bridge/README.md) (#342):
a header line naming the version, the source and the time unit, then
`<time> <kind> <payload…>` lines, one per record.

```
#o1next-trace 1 bus-analyzer ns
14976 R 2a01 4f 1
```

**The envelope is shared; the payload is per-source.** This tool wants **one reader for
the envelope and one decoder per source** — the bench rig's byte runs and the analyzer's
bus cycles are two decoders, not two formats. That is the whole reason the envelope was
written down before either producer existed: two formats would have to be kept in step by
hand, and one of them would not be.

## Uses

- CoPower-88 protocol bring-up + unknown-doorbell trapping (#26, #23)
- Drive C / OCC1 protocol validation (#6, #8)
- General "what is the machine doing" debugging during every
  personality's development
