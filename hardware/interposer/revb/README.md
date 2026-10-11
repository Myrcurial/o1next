# revb/ — Rev B personality engine: RP2350B pin map

Rev A (ES) and Rev B are **separate products, not revisions**: Rev A is
the mastering/debug instrument (shift-register fabric, CPU stopped);
Rev B is the live-cycle personality engine (respond inside a running
machine's bus window). This document is the Rev B pin allocation.

## The trick that makes 48 GPIO enough: window detect + /WAIT stretch

Live response does **not** require direct address pins:

- A **74AHCT688** magnitude comparator watches A8–15 (+ bank-2 status)
  against a **595-programmable match window** → combinational `ADDR_HIT`
  to PIO. Windows are firmware-relocatable, so every personality's port
  base is soft.
- On HIT, PIO asserts **/WAIT** before the end of T2 (688 is
  combinational; PIO response ~50 ns — comfortable), stretching the Z80
  cycle. Full address + data come from the 165 snapshot chain; the
  response is driven via the data 245; /WAIT releases. The CPU never
  knows it was slowed by microseconds.
- Result: the 16-line address bus consumes **zero** timing-critical
  GPIO; /WAIT stretching is the period-correct mechanism slow
  peripherals always used.

## RP2350B pin map (48 GPIO)

| Pins | Function | Notes |
|---|---|---|
| GP0–7 | **D0–7** data bus | via 74AHCT245 (bidir) |
| GP8–11 | **/MREQ, /IORQ, /RD, /WR** | direct, raw edges — cycle framing |
| GP12–19 | **HSTX → HDMI** | HSTX is fixed to GP12–19 on RP2350; a VGA resistor DAC would need the same range, so the two are mutually exclusive — **HDMI is the choice**, VGA not pursued (front-panel pod carries the connector) |
| GP20 | /M1 | direct (opcode-fetch vs cycle typing) |
| GP21 | CLK | direct — PIO timing reference |
| GP22 | **/WAIT drive** | fast OC buffer; the personality enabler |
| GP23 | **ADDR_HIT** | 74AHCT688 window-comparator output |
| GP24, GP25 | DATA_OE, DATA_DIR | 245 control |
| GP26–30 | SR_SCK, SR_MISO(165), SR_LOAD, SR_MOSI(595), SR_RCK | drive/capture fabric (inherited from Rev A) |
| GP31, GP32 | /OE_ADDR (595 /G), /OE_SYSCTL (244) | drive enables |
| GP33 | /BUSRQ drive | mastering (Rev A capability retained) |
| GP34, GP35 | /BUSAK in, /RESET in | handshake/status |
| GP36 | /RFSH in | snapshot strobe refinement |
| GP37 | spare / front-panel ribbon aux | candidate: PIO-USB for 2nd keyboard (with GP38?) |
| GP38, GP39 | **UART0 TX/RX → ESP32-C3** | modem + WiFi + LED bank offload |
| GP40–43 | SPI: SCK, MOSI, MISO, /CS_SD | SD card (SPI mode); 4-bit SDIO-via-PIO would cost 2 more — deferred |
| GP44 | /CS_FLASH | W25Q library flash (shares SPI bus) |
| GP45, GP46 | **I²C SDA, SCL** | front-panel OLED/encoder, expanders, "just in case" |
| GP47 | trigger / debug LED / ADDR_HIT2 | spare comparator window |

**ESP32-C3 side (offloaded from RP2350):** Hayes-style LED bank
(charlieplexed or I²C expander), modem UART link, web radio. EN/BOOT
driven from 595 bits (slow by nature).

**Fit check:** 47–48 allocated with the whole personality set covered;
the 595/165 fabric remains the pressure-relief valve for any slow line
that turns out to want a pin.

## Carry-over from Rev A

595/165 shift fabric, 244 sysctl tri-state, 245 data path, W25Q flash,
ESP32-C3 radio, /BUSRQ mastering — Rev B keeps the whole instrument
and adds the live-response path (688 + /WAIT + direct control/data).
