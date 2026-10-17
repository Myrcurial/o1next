# web-ui — browser interface (RP2354B, lwIP HTTP)

C64 Ultimate-style browser UI served by the RP2354B: the single place
to manage every interposer personality — no local mods required on the
machine, and a CP/M-side utility (`software/mount-com/`) covers
in-machine control for the image library.

Tracks: part of #16; consumed by #20, #19, #21/#56, #45.

## Definition

- lwIP HTTP server + static assets + small JSON API on the RP2354B.
- Pages/endpoints:
  - **Storage:** image library browse/upload, mount to drive A/B or
    Drive C (`../floppy-emulator/`, `../drive-c-gpib/`)
  - **Printer:** list/download rendered MX-80 PDFs (`../virtual-printer/`)
  - **Modem:** connection status, phonebook, SSH session/key management
    (bridged to the ESP32, `../zimodem-fork/`)
  - **Console:** KVM page (`../kvm-console/`)
  - **Clock/status:** RTC set, analyzer status, firmware info
- Bandwidth/jitter discipline: heavy transfers never during flux
  windows or capture sessions (radio-jitter rule).

## Deliverables

- HTTP server + API spec (`api.md`)
- Static front-end (vanilla JS; no build step heavier than a Makefile)
