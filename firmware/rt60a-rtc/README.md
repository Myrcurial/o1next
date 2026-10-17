# rt60a-rtc — the RT-60A **time service** (RP2354B)

**Decision (2026-10-11, #7): implement the RT-60A's documented ABI, not its
hardware.** This is the firmware-side record of that decision; the research side
is `docs/rt60a-analysis.md`, and the reasoning is in #7.

Tracks: #18 (this personality), #7 (the contract), #37 (the reconstruction).

## Why the ABI and not the hardware

The manual fully specifies the *hardware* — MSM5832/58321, lithium cell, crystal
and trimcap, card-edge onto the IEEE-488 port — but it does **not** document the
handshake that wakes the clock's outputs. It says only that "a special low
voltage CMOS circuit recognizes a unique handshake sequence". And the software
that speaks that handshake, `CLOCK.COM`, is on a TD0 whose dump is damaged
(27 bad sectors, `research/rtc/`).

Two things follow:

1. **The handshake is unlearnable** except by disassembling software we cannot
   read, and
2. **It buys nothing anyway** — the only thing that reads the clock is
   `CLOCK.COM` itself, and what software actually consumes is not the clock but
   the **memory ABI** that `CLOCK.COM` publishes.

That ABI *is* documented. It is what we implement.

## The contract we implement

From `docs/rt60a-analysis.md` — a pointer word at **`0x0040`**, then:

| Offset | Field |
|---|---|
| −15 | FLAGS (phantom display, At Trap, software off) |
| −14 | TIMEFLAG (12/24 h, AM/PM, seconds suppressed) |
| −13 | DATE, 7 bytes, `YYMMDD` + day-of-week |
| −6 | TIME, 6 bytes, raw BCD unpacked |
| 0 | DAY, MONTH, YEAR, HOURS, MINUTES, SECONDS (binary) |
| 6 | MEMBUFF — 60→1 decrementer; sticks at 1 when reads fail |
| 7 | TIMEASCII, NUL-terminated |
| 19 | DATEASCII, NUL-terminated |

Plus the **60 Hz interrupt hook at `0xEFF8`**, the **At Trap** interception of
`@T`/`@D` in printer output, and the BDOS file-stamping patches. The `0xFF`/`0xBB`
sentinel in the pointer word means "clock software is not running" and must be
preserved as a meaning, not overwritten.

## Two halves, not one

**The interposer cannot do this alone.** Without a resident publisher nothing
reads `0x0040`, and the At Trap and file-stamping behaviour is a BIOS/BDOS patch
— it is code, not data. So the work splits:

1. **The interposer is the clock.** Accurate time from the RP2354B RTC (or core
   timer), settable from the web UI, optionally NTP-synced when WiFi is up;
   battery-backed behaviour in flash so time survives reboots. Exposed through
   the personality mailbox — **no IEEE handshake, no MSM5832**.
2. **A resident publisher owns the ABI** — a `CLOCK.COM` replacement that
   maintains the `0x0040` block on the 60 Hz cadence and installs the hooks.
   That is Osborne-side software: `software/rt60a-clock/`.

## OZROM may inform the shape

**OZROM 1E ships a time-of-day clock** — `TIME`, `ALARM`, `TIMER` — on a machine
with no RTC hardware at all (#81). It is a second, independent implementation of
exactly this idea, and its manual documents it. Read it before fixing our ABI, so
we do not invent a third shape.

## Could we build a physical replica RT-60A instead?

**No** — and now for a firmer reason than the missing schematic. The handshake is
undocumented, so a replica could not be driven by the original software; only by
ours. If we are writing the software anyway, the virtual personality is strictly
cheaper. The manual's architecture (MSM5832/58321, pass-through card edge,
high-impedance outputs, source-handshake prerequisite, two shortable reset pins)
remains a clean-room redesign target if a unit or a working disk ever surfaces.

## Deliverables

- The ABI contract, promoted from `docs/rt60a-analysis.md` from an *analysis* to
  a *spec* (#7).
- The mailbox time service in this personality, plus a web-UI time-set endpoint.
- The resident publisher in `software/rt60a-clock/`.
- Validation against the reconstructed ABI; and, if a unit ever appears, a note
  on whether the handshake can be recovered.
