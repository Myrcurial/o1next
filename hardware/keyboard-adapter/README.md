# keyboard-adapter — the O1NEXT USB Keyboard Adapter (USB-HID → P4)

**Board:** `keyboard-adapter` — the **O1NEXT USB Keyboard Adapter** — the
project's **second deliverable**. See the register in
[`../README.md`](../README.md).

**Its shape, in the maintainer's words (2026-10-19):** a purpose-built adapter
with a **USB-A** port for an external USB keyboard, a **P4** connector mapping
the 8×8 native matrix, a **USB-C** port for programming or powering the adapter,
and a power lead that comes from one of (a) a small passive adapter on the MODEM
9-pin port, (b) a front-panel power port on the `O1NEXT WiFi COMM PAC`, or (c) a
front-panel power port on the `O1NEXT Drive C Repro`. The PCB mounts the 12 V→5 V
buck for the 5 V signalling and the 3.3 V the RP-series part needs — **RP2040 or
the B part is a project-wide decision taken elsewhere** (#47), and the reference
design below currently says RP2040.

**A USB port on the Osborne 1 you can jam a normal USB HID keyboard into
and have it work.** Standalone, always-on upgrade: no interposer, no
WiFi, no BIOS changes. Also the matrix-injection firmware base for the
interposer's web-KVM personality (#45).

Tracks: #47 (split out of #45). Target: PCBway build.

## Reference design

- **MCU:** RP2040 running a USB HID host stack (TinyUSB host mode) →
  8×8 matrix state. Chosen over RP2354B deliberately: no radio needed,
  lowest cost, standard chip for retro USB-HID-host adapters.
- **I/O:** watch 8 host row-drive lines (inputs), drive 8 column lines
  open-collector (matching the stock 74LS05 stage) — 16 GPIO.
- **Level shifting:** O1 keyboard lines are 5 V TTL; RP2040 is 3.3 V.
  Rows need 5 V-tolerant input handling; columns driven via open-drain
  buffer (74LVC07-class) so the adapter never fights the host.
- **Power (variant A — internal):** from **P4 pin 19 = +12V** (wired
  through jumper J6 + R21 22Ω; bridge J6 — a documented, reversible
  mod). On-board 12V→5V (or 12V→3.3V) buck; the 22Ω drop is negligible
  at RP2040 currents (~25–60 mA). Do **not** draw logic power from the
  column pull-ups.
- **Power (variant B — no-open-case):** powered from outside the
  machine so it works for users who don't want to open their Osborne 1
  at all. The adapter's USB-A port pairs with a **powered USB hub** (or
  a power-tee / 5 V feed on the adapter's upstream side): the RP2040
  draws its 5 V from the hub's external supply rather than from P4.
  J6 stays factory-open; the machine is untouched. The design should
  expose a power-source jumper (P4-12V vs external 5 V) so one PCB
  serves both variants. Note: in variant B the column lines are driven
  against a machine the adapter doesn't share power with — ensure
  common ground comes through P4 pins 1/20 and the open-drain column
  drivers tolerate the unpowered-machine / powered-adapter (and vice
  versa) states.
- **Power (variant C — from the MODEM port, no case opened):** the simplest
  no-open-case route, and the one to prefer. **P1 (MODEM, DE-9 pin 7) carries the
  same +12 V through the same R21, and it is reachable without opening anything**
  — so a **9-pin passthrough from this adapter to the modem port** takes power
  from there. That removes the J6 bridge from variant A entirely, on the same
  documented-and-reversible principle the WiFi modem module already uses: it
  powers itself off that pin (`../wifi-comm-pac/README.md`). One PCB should
  serve all three variants via the power-source jumper — variant C is variant A's
  rail, sourced from a different connector.

## Host interface — P4 keyboard connector (O1A)

Later O1A "blue/grey" machines: coiled cable, 24-hole plug, only the
inner 20 pins mate. Documented pinout (O1 Technical Manual via
pinouts.ru, 4/4 corroborating reports; corrected by #48):

- 1 = GND; 2–9 = rows A4, A0, A3, A6, A2, A5, A1, A7
- 10–17 = columns D0–D7; 18 = NC; **19 = +12V (via J6+R21)**; 20 = GND

## Spec validation required BEFORE layout

- [ ] Confirm pinout against `research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`
      and continuity-check a real O1A (rows vs columns, GND, pin 19
      +12V with J6 bridged; J6/R21 present on target board revisions).
- [ ] Confirm rows are driven low one-hot via open-collector inverters,
      columns pulled up to +5V via a 3.3K resistor pack.
- [ ] Scan timing: measure stock scan rate to size the RP2040 polling
      loop / PIO snoop.

## References

- `research/osborne1/keyboard/` (pinout source + provenance)
- `docs/research-gaps.md`, issue #45 (KVM personality reuse)
