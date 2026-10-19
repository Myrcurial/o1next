# keyboard-matrix — USB HID host → 8×8 matrix injection (RP2040)

One RP2040 firmware shared by three consumers:

1. **Standalone USB keyboard adapter** (`hardware/keyboard-adapter/`,
   #47) — the everyday always-on upgrade.
2. **Interposer KVM console** (`../kvm-console/`, #45) — browser
   keystrokes injected into the matrix.
3. **Front-panel second USB-A port** (`hardware/interposer-upgrade/ui-pod/`, #14) —
   optional second keyboard; original keyboard stays live.

## Definition

- TinyUSB host mode: enumerate HID boot-protocol keyboards, maintain
  an 8×8 matrix state matching the O1 scan map.
- Watch 8 host row-drive lines; drive 8 column lines open-drain
  (hardware: 74LVC07-class) exactly like a stock key press.
- Input source is runtime-selectable: local USB port, or events pushed
  from the interposer (KVM path).

## Mapping work

- O1 matrix/scan map from the Rev E schematic + validation on real
  hardware (same validation checklist as #47).
- Handle O1 quirks: RESET/SHIFT-lock style keys, repeat behavior.

## Deliverables

- RP2040 firmware (Pico SDK + TinyUSB host)
- Keymap table + matrix-injection timing notes
- Bench validation checklist (shared with #47's pre-layout list)
