# bus-analyzer — passive Z80 bus capture (RP2354B)

Cycle-accurate capture of address/data/control traffic from the
interposer, streamed over USB (and WiFi when idle bandwidth allows).
Hardware equivalent of emulator machine-state introspection.

Tracks: #17 (Phase 2 #16). Hardware: `hardware/interposer-upgrade/`.

## Definition

- PIO state machines sample the 4 MHz bus synchronously off the CPU
  clock; capture address, data, /MREQ, /IORQ, /RD, /WR, /M1, /RFSH.
- /RFSH refresh cycles filtered from the trace (optionally counted).
- Ring buffer in SRAM (520 KB), streamed to host via USB CDC;
  host-side decode lives in `tools/trace-analyzer/`.
- Timing-critical sections pinned to core1/PIO with WiFi IRQs fenced
  (see `firmware/README.md` radio-jitter note).

## Shared engine

This component includes the **memory-map snoop/poke engine** that every
other interposer personality builds on: watch bank-switched I/O
addresses (`docs/o1-memory-io-map.md`), and in active mode drive the
data bus through the AHCT transceivers during the correct bus window.
Keep it a separate module (`snoop/`) inside this folder so other
personalities link it without the capture pipeline.

## The trace format is already written down

`#o1next-trace` — the envelope, the version, the time unit and the rules — is defined in
[`../bench-bridge/README.md`](../bench-bridge/README.md) (#342), and it is deliberately
**one definition shared by every producer rather than one per producer**:

```
#o1next-trace <version> <source> <unit>
<time> <kind> <payload…>
```

**The envelope is shared; the payload is per-source.** This analyzer emits Z80 bus
cycles; the bench rig emits byte runs in two directions; `tools/trace-analyzer/` should
carry one reader for the envelope and one decoder per source, rather than a second
format that has to be kept in step with the first by hand.

## Deliverables

- PIO programs + capture firmware (Pico SDK, C)
- Trigger/filter configuration (address ranges, port bases, R/W)
- USB streaming protocol spec (shared with `tools/trace-analyzer/`) — **the envelope
  already exists**; what is left is this source's `kind`s and payload fields
