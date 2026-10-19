# keyboard — the O1NEXT Complete's own keyboard

**Part of `o1next-complete`**, the machine — not a board that plugs into anything.
Register: [`../../README.md`](../../README.md).

A **custom USB keyboard PCB**: a **QMK-compatible** design in the **Osborne 1
layout**, so the machine keeps the O1's keyboard layout, keycaps and "keyboard
seals the unit" geometry, with **Cherry MX** switches underneath. It talks USB to
the `next-integrated` board's **USB-A #2** port (the fixed-function keyboard port).

The **matrix encoding is shared work**: the machine's keyboard is a Cherry-MX
implementation of the same 8×8 matrix `keyboard-adapter` drives, so the USB
keyboard interface (#47) and this board share their scan code — see the keyboard
block in [`../../next-integrated/README.md`](../../next-integrated/README.md) and
`site/hardware/o1next-complete.md`.

## Not the same thing as `keyboard-adapter`

Two different jobs, two different boards:

| | |
|---|---|
| [`../../keyboard-adapter/`](../../keyboard-adapter/) | an **adapter**: takes a *foreign* USB keyboard and drives a real Osborne 1's 8×8 matrix through the **P4** connector. For someone keeping the machine they have. |
| **this board** | **the machine's own keyboard**, built into the O1NEXT Complete. Nothing to adapt: it *is* the keyboard. |

## Status

**No schematic yet.** The machine's mechanical and keyboard work is tracked by
**#52** (with the rest of the enclosure) and the matrix work by **#47**, and the
schematic lands here as `keyboard.kicad_pro` — at which point it gets a `Board`
entry in `tools/check_schematics.py` named `o1next-complete-keyboard` and a row in
the register's parts table.
