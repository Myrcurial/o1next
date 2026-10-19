# zimodem-fork — WiFi modem firmware (ESP32)

Fork of [Zimodem](https://github.com/bozimmerman/Zimodem) targeting the
ESP32 build, extended with the O1-specific features. One codebase serves
both the severable modem module and (leaning) the interposer-onboard
ESP32 (`hardware/wifi-comm-pac/`, `hardware/interposer-upgrade/`).

Tracks: #21, #56. **The fork is not started yet** — stock ESP32 Zimodem
covers telnet in the interim (see `software/README.md` no-new-code
list); fork when the baud-buffer work begins.

## What the fork adds on top of upstream ESP32 Zimodem

1. **Double-sided baud-rate buffer** — decouple the O1-side ACIA rate
   from the far-end link rate: buffer both directions so a 650/2600
   (or 8 MHz turbo) machine talks cleanly to a link running at any
   modern rate. This is the fix that makes the 2× business turbo (#55)
   usable and quietly corrects the factory 600/2400 → 650/2600 quirk.
2. **SSH as a first-class transport** — upstream already has an
   ESP32-only SSH client (`INCLUDE_SSH`); we surface it properly: key
   management, host verification, session control via the web UI, so
   the O1 can `ssh` into a modern host (e.g. a Mac's Remote Login).

## Kept from upstream

Hayes AT command set + telnet (period comm software compatibility:
Kermit, XMODEM, etc.), ESP32 extras (SD shell, FTP, SLIP/PPP).

## O1-specific integration

- MODEM (P1) port is TTL with a **bipolar RXD input** — module hardware
  handles levels (`hardware/wifi-comm-pac/`); firmware just needs
  the right UART inversion/idle settings — validate on real hardware.
- Management endpoint bridged to the interposer web UI
  (`../web-ui/`) when onboard.

## Deliverables

- Fork repo + O1 patches (baud buffer, SSH management)
- Build/flash docs; period-software compatibility test notes
