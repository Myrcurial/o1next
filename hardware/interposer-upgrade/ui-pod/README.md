# ui-pod — the UI pod of `interposer-upgrade`

**Part 2 of 4 of `interposer-upgrade`** — and a **snap-off section of the
interposer PCB** (routed and separated by mouse bites, so it is assembled in the
same single SMT pass as the rest of the panel), not a board of its own. The unit's
README is [`../README.md`](../README.md) and the register is
[`../../README.md`](../../README.md).

**Not a board of its own** — it is reached over a ribbon cable and is mostly
connectors, a display and LEDs. The maintainer's board description places the pod
inside the interposer, so it is a part of the Upgrade, not a separate product.

A COMM-PAC-style faceplate covering one floppy storage pocket, providing local
physical UI for the interposer without opening the case.

Tracks: #14.

## Contents

- SD card / USB stick socket (disk-image library media)
- **Second USB-A port: keyboard input via the interposer** — a USB HID
  keyboard plugged in here is injected into the O1's keyboard matrix by
  the interposer (reusing the `../../keyboard-adapter/` RP2040 matrix
  firmware, #45/#47). The **original keyboard stays plugged in and fully
  functional**; the USB keyboard is an optional second input that just
  works, both live simultaneously.
- **HDMI video out** (SCREEN-PAC personality, #24) — decided; VGA not pursued
- Small OLED status display
- Rotary encoder or 5-way d-pad (FlashFloppy-style menu UI)
- Hayes/USR-style LED bank: CTS/RTS/TX/RX/RING etc. (modem personality)
- Ribbon cable back to the interposer board (`../`)

## Constraints

- Must route through the existing front-panel ventilation / IEEE-488
  openings — no case cutting on the host machine.
- All electronics on the interposer side of the ribbon where possible;
  the pod is mostly connectors + display + LEDs to keep the cable
  simple and the front end 5 V/3.3 V logic only.

## Open questions

- OLED controller choice (I²C vs SPI over the ribbon).
- Exact pocket geometry vs. COMM-PAC faceplate dimensions (measure
  against host machine photos, `research/pictures/`).
