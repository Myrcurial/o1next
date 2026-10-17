# kvm-console — web-based KVM for the O1 (RP2354B + RP2040)

Browser-based KVM console: watch the Osborne's screen and type into it
from a web page. An interposer personality composed from two existing
components rather than new core work.

Tracks: #45 (split: standalone keyboard hardware is #47).

## Definition

- **Video:** screen snoop reusing `../screenpac-video/` (framebuffer +
  char-gen state → rendered page/canvas in the web UI).
- **Keyboard:** matrix injection reusing `../keyboard-matrix/` RP2040
  firmware — browser keystrokes → USB-HID-like events → 8×8 matrix
  pokes into the O1's keyboard scan.
- The physical keyboard remains live at all times; KVM input is an
  additional concurrent source, same rule as the front-panel second
  USB port (`hardware/front-panel-ui/`).

## Deliverables

- KVM composition firmware + web-UI console page
- Latency/refresh characterization notes
