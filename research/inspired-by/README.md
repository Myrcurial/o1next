# inspired-by/ — adjacent projects and why this one is different

Other people's Osborne 1 reinventions that inspired or informed this
project — and the contrast that defines it. **Our approach keeps the
original machine intact**: original Z80, original ROMs, original
software, reversible interposer-based upgrades. These projects took
other paths, and they're worth studying for what they solved well.

## Osborne 1 reborn as a retro cyberdeck (MAME)

- [reddit.com/r/cyberDeck — Osborne 1 reborn as retro cyberdeck](https://www.reddit.com/r/cyberDeck/comments/me5fk9/osborne_1_reborn_as_retro_cyberdeck/)
- Osborne case + form factor, but **completely emulated**: modern
  internals running MAME. Nice reference for display mounting and
  fitting modern panels into the O1 shell; philosophically the opposite
  of o1nextgen (their O1 is a simulation; ours stays silicon-real).

## "Brain transplant" — Raspberry Pi inside the Osborne case

- [hackaday.com — Suitcase computer reborn with Raspberry Pi inside](https://hackaday.com/2018/05/17/suitcase-computer-reborn-with-raspberry-pi-inside/)
- [instructables.com — Raspberry Pi Osborne 1 rebuild](https://www.instructables.com/Raspberry-Pi-Osborne-1-Rebuild/)
- Guts the machine, keeps the case + **original keyboard**, runs a CP/M
  emulator (rather than MAME) on a Pi. Notably includes the **Arduino
  code converting the O1 keyboard matrix to USB — the inverse of our
  `firmware/keyboard-matrix/`** (#47: USB → matrix). Useful reference
  for the O1 matrix map and scan timing, and for keyboard-cable
  handling.

## What we take from each

| Project | Borrowed lesson |
|---|---|
| Cyberdeck (MAME) | Display/panel fitment in the O1 shell; appetite for the form factor |
| Pi brain transplant | O1 keyboard matrix → modern-host code (invertible to our use); CP/M emulator UX expectations |
| Richard Loxley's Gotek mod | See `hardware/floppy-adapter/` — switchable "three drives, two active" concept (we do it at the connector, on a PCB) |

If more adjacent projects turn up (other O1 mods, interposer-class
projects), add them here with a one-line "what we take from it".

## Osmosis Computer — direct prior art for the interposer (#73)

Osmosis's 1983 **80-column board** is the closest thing in the archive to what
this project is building, because of how it attaches: the Z80 is pulled from its
socket, plugged into the board's 40-way header, and the board is plugged into the
socket the Z80 came from. **A board that takes the CPU's socket and drives the
bus** is precisely the interposer shape (#11/#12).

What we take from it:

| Osmosis | Borrowed lesson |
|---|---|
| Z80 socket piggyback | The mechanical and electrical approach for the interposer — the same trick, 40 years earlier, with a 40-pin header instead of a PCB edge |
| Supplied monitor ROM | A personality can ship its own ROM rather than only observing the stock one |
| `ESC 8` / `ESC 5` width switching | A control interface users can reach from BASIC — a reminder that a personality's *interface* matters as much as its function |
| Its dBASE patch | Same three bytes as Nuevo's — the application-patch problem is inherent to 80 columns, not to any one board |

Full comparison, with quotations from both vendors' material:
`docs/o1-upgrade-boards.md`.
