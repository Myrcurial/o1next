#!/usr/bin/env python3
"""Generate the wifi-comm-pac Rev A schematic for issues #324 / #325.

This sheet is **wired**, not label-connected: every net is drawn as orthogonal
wire segments between the pins it joins, and the supply rails use power symbols
(the ordinary way a schematic shows GND/3V3/5V).  One net label is still placed
per signal net, so the net *names* survive -- and because the labels are singular
per net, `tools/check_schematics.py` fails if a wire is missing or mis-routed,
rather than being fooled by a label doing the connecting.

Geometry: KiCad stores symbol pins with Y up and the sheet with Y down, so a
placed symbol's pin lands at (x + px, y - py).  check_schematics.py asserts the
resulting nets.

Routing: a tiny Manhattan router.  For each net the pins are joined in a star
from the first pin, trying L routes, then Z routes with a growing offset, and
rejecting any candidate that crosses a symbol body, overlaps another net's wire
collinearly, or lands an endpoint on one.  Perpendicular crossings are allowed
(and are unambiguous in KiCad: no junction, no connection).

NOTE ON PIN NUMBERS: for the multi-pin ICs the numbers are *logical*, not the
vendor footprint's.  They exist so the netlist checker can name a pin; the real
assignment is made at footprint annotation, as the floppy adapter's relay does.
The connectors and the two AW9523B parts use their real numbering.

Regenerate: python3 gen_wifi_comm_pac_sch.py   (writes wifi-comm-pac.kicad_sch)
"""
import datetime
import re
import uuid


def uid():
    return str(uuid.uuid4())


def snap(v):
    """KiCad wants wire and label ends on the 1.27 mm grid."""
    return round(round(v / 1.27) * 1.27, 3)


TODAY = str(datetime.date.today())

# power nets are drawn with power symbols, one per pin; everything else is wired
POWER_NETS = {'GND', '+3V3', '+5V', '+12V', '+12V_SW', '+5V_P1', '+5V_USB'}


class Symbol:
    """Minimal KiCad symbol builder (rectangle body, L/R pins)."""

    def __init__(self, name, ref_letter, w, h):
        self.name = name
        self.ref_letter = ref_letter
        self.w, self.h = w, h
        self.pins = []          # (number, name, side, offset_from_bottom)
        self.lib_id = 'local:' + name
        self.footprint = ''     # set from FOOTPRINTS below, keyed by SYMS key

    def add(self, num, pname, side, off):
        self.pins.append((num, pname, side, off))
        return self

    def _find(self, num):
        for n, p, side, off in self.pins:
            if n == num:
                return p, side, off
        raise KeyError(num)

    def pin_sym(self, num):
        """symbol-local connection point (KiCad symbol space: Y up)."""
        p, side, off = self._find(num)
        hw, hh = self.w / 2, self.h / 2
        if side == 'L':
            return (-hw - 2.54, -hh + off)
        if side == 'R':
            return (hw + 2.54, -hh + off)
        raise ValueError(side)

    def lib_sexpr(self):
        s = f'  (symbol "{self.lib_id}" (pin_names (offset 0.508)) (in_bom yes) (on_board yes)\n'
        s += (f'    (property "Reference" "{self.ref_letter}" (at 0 {-self.h/2 - 2.54} 0)'
              ' (effects (font (size 1.27 1.27))))\n')
        s += (f'    (property "Value" "{self.name}" (at 0 {-self.h/2 - 5.08} 0)'
              ' (effects (font (size 1.27 1.27))))\n')
        s += (f'    (property "Footprint" "{self.footprint}" (at 0 0 0)'
              ' (effects (font (size 1.27 1.27)) (hide yes)))\n')
        s += '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        hw, hh = self.w / 2, self.h / 2
        s += f'    (symbol "{self.name}_0_1"\n'
        s += (f'      (rectangle (start {-hw} {hh}) (end {hw} {-hh})'
              ' (stroke (width 0.254) (type default)) (fill (type background))))\n')
        s += f'    (symbol "{self.name}_1_1"\n'
        for n, p, side, off in self.pins:
            ax, ay = self.pin_sym(n)
            rot = 0 if side == 'L' else 180
            s += (f'      (pin passive line (at {ax} {ay} {rot}) (length 2.54)'
                  f' (name "{p}" (effects (font (size 1.27 1.27))))'
                  f' (number "{n}" (effects (font (size 1.27 1.27)))))\n')
        s += '    )\n  )'
        return s


class PowerSym:
    """A one-pin power symbol; its Value is the net name, as KiCad expects."""

    def __init__(self, net):
        self.net = net
        self.name = 'PWR_' + re.sub(r'\W', '_', net)
        self.lib_id = 'local:' + self.name

    def lib_sexpr(self):
        down = self.net == 'GND'
        bar = -1.27 if down else 1.27
        s = (f'  (symbol "{self.lib_id}" (power) (pin_names (offset 0))'
             ' (in_bom yes) (on_board yes)\n')
        s += ('    (property "Reference" "#PWR" (at 0 -6.35 0)'
              ' (effects (font (size 1.27 1.27)) (hide yes)))\n')
        s += (f'    (property "Value" "{self.net}" (at 0 3.81 0)'
              ' (effects (font (size 1.27 1.27))))\n')
        s += '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        s += '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        s += f'    (symbol "{self.name}_0_1"\n'
        s += ('      (polyline (pts (xy 0 0) (xy 0 ' + f'{bar}' + '))'
              ' (stroke (width 0.254) (type default)) (fill (type none)))\n')
        s += (f'      (polyline (pts (xy -1.27 {bar}) (xy 1.27 {bar}))'
              ' (stroke (width 0.254) (type default)) (fill (type none))))\n')
        s += f'    (symbol "{self.name}_1_1"\n'
        s += (f'      (pin power_in line (at 0 0 90) (length 0)'
              f' (name "{self.net}" (effects (font (size 1.27 1.27))))'
              ' (number "1" (effects (font (size 1.27 1.27)))))\n')
        s += '    )\n  )'
        return s


class FlagSym:
    """PWR_FLAG: tells ERC that a rail is driven, so power_in pins are satisfied."""

    name = 'PWR_FLAG'
    lib_id = 'local:PWR_FLAG'

    def lib_sexpr(self):
        s = '  (symbol "local:PWR_FLAG" (power) (pin_names (offset 0)) (in_bom yes) (on_board yes)\n'
        s += '    (property "Reference" "#FLG" (at 0 -3.81 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        s += '    (property "Value" "PWR_FLAG" (at 0 5.08 0) (effects (font (size 1.27 1.27))))\n'
        s += '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        s += '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        s += '    (symbol "PWR_FLAG_0_1"\n'
        s += '      (polyline (pts (xy 0 0) (xy 0 1.27) (xy -1.27 2.54) (xy 0 3.81) (xy 1.27 2.54) (xy 0 1.27)) (stroke (width 0.254) (type default)) (fill (type none))))\n'
        s += '    (symbol "PWR_FLAG_1_1"\n'
        s += '      (pin power_out line (at 0 0 90) (length 0) (name "pwr" (effects (font (size 1.27 1.27)))) (number "1" (effects (font (size 1.27 1.27)))))\n'
        s += '    )\n  )'
        return s


def ic(name, ref, left, right, w=25.4, pitch=2.54):
    """Rectangle IC with pins down the left and right edges."""
    n = max(len(left), len(right))
    h = pitch * (n - 1) + 12.7
    s = Symbol(name, ref, w, h)
    for i, (num, pname) in enumerate(left):
        s.add(num, pname, 'L', h - 5.08 - pitch * i)
    for i, (num, pname) in enumerate(right):
        s.add(num, pname, 'R', h - 5.08 - pitch * i)
    return s


def two_pin(name, ref, w=10.16):
    """Horizontal two-terminal part: pin 1 left, pin 2 right."""
    s = Symbol(name, ref, w, 5.08)
    s.add(1, '1', 'L', 2.54)
    s.add(2, '2', 'R', 2.54)
    return s


# --------------------------------------------------------------- symbols
# Pin sides follow the signal flow left -> right: the machine (J1) on the left,
# then the level stage, then the ESP32, then the expanders and the panel.
SYMS = {
    'J1': ic('CONN_2X05_MODEM', 'J', [], [
        (2, 'TXD'), (8, 'MCB'), (5, 'CTS'), (9, 'RI'), (6, 'RXD'),
        (4, 'MSB'), (7, '+12.6V'), (1, 'GND'), (3, 'NC'), (10, 'SPARE'),
    ], w=22.86, pitch=5.08),
    'U1': ic('74LVC4T245_TXD', 'U',
             [(8, 'B1'), (9, 'B2'), (12, '/OE'), (13, 'VCCB'), (2, 'GND')],
             [(3, 'A1'), (4, 'A2'), (7, 'DIR'), (1, 'VCCA')]),
    'U2': ic('74LVC4T245_HS', 'U',
             [(8, 'B1'), (9, 'B2'), (12, '/OE'), (13, 'VCCB'), (2, 'GND')],
             [(3, 'A1'), (4, 'A2'), (7, 'DIR'), (1, 'VCCA')]),
    'U3': ic('74LVC1G07_MSB', 'U',
             [(4, 'Y')],
             [(2, 'A'), (5, 'VCC'), (3, 'GND'), (1, 'NC')], w=17.78),
    'U4': ic('MAX3232_RXD', 'U',
             [(14, 'T1OUT'), (15, 'GND')],
             [(11, 'T1IN'), (16, 'VCC'), (1, 'C1+'), (3, 'C1-'),
              (4, 'C2+'), (5, 'C2-'), (2, 'V+'), (6, 'V-'),
              (7, 'T2OUT'), (8, 'R2IN'), (9, 'R2OUT'), (10, 'T2IN'),
              (12, 'R1OUT'), (13, 'R1IN')]),
    'U5': ic('ESP32-S2-MINI-2U', 'U',
             [(5, 'IO15'), (6, 'IO16'), (7, 'IO33'), (8, 'IO34'),
              (9, 'IO35'), (10, 'IO36'), (11, 'IO37'), (12, 'IO38'),
              (13, 'IO21'), (14, 'IO19'), (15, 'IO20'), (3, 'EN'), (4, 'IO0')],
             [(1, '3V3'), (16, 'IO43'), (17, 'IO44'), (18, 'GND'), (2, 'GND')],
             w=35.56),
    'U6': ic('AW9523B_PANEL', 'U',
             [(1, 'VDD'), (2, 'GND'), (3, 'SDA'), (4, 'SCL'), (5, 'AD0'),
              (6, 'AD1'), (7, 'INTN'), (8, 'RESETN')],
             [(17, 'P0_0'), (18, 'P0_1'), (19, 'P0_2'), (20, 'P0_3'),
              (21, 'P0_4'), (22, 'P0_5'), (23, 'P0_6'), (24, 'P0_7'),
              (9, 'P1_0'), (10, 'P1_1'), (11, 'P1_2'), (12, 'P1_3'),
              (13, 'P1_4'), (14, 'P1_5'), (15, 'P1_6'), (16, 'P1_7')],
             w=33.02),
    'U7': ic('AW9523B_IFACE', 'U',
             [(9, 'P1_0'), (10, 'P1_1'), (11, 'P1_2'), (12, 'P1_3'),
              (13, 'P1_4'), (14, 'P1_5'), (15, 'P1_6'), (16, 'P1_7'),
              (17, 'P0_0'), (18, 'P0_1'), (19, 'P0_2'), (20, 'P0_3'),
              (21, 'P0_4'), (22, 'P0_5'), (23, 'P0_6'), (24, 'P0_7')],
             [(1, 'VDD'), (2, 'GND'), (3, 'SDA'), (4, 'SCL'), (5, 'AD0'),
              (6, 'AD1'), (7, 'INTN'), (8, 'RESETN')], w=33.02),
    'U8': ic('MAX98357A', 'U',
             [(3, 'BCLK'), (4, 'LRCLK'), (5, 'DIN'), (6, 'SD_MODE')],
             [(1, 'VDD'), (2, 'GND'), (7, 'GAIN'), (8, 'OUT+'), (9, 'OUT-')]),
    'U9': ic('TPS54331', 'U',
             [(1, 'BOOT'), (2, 'VIN'), (3, 'EN'), (4, 'SS'), (5, 'VSENSE')],
             [(8, 'PH'), (6, 'COMP'), (7, 'GND')]),
    'U10': ic('AP2112K-3.3', 'U',
              [(1, 'VIN'), (3, 'EN'), (2, 'GND')],
              [(4, 'VOUT'), (5, 'NC')], w=17.78),
    'J3': ic('USB_C_SINK', 'J',
             [(1, 'VBUS'), (2, 'CC1'), (3, 'CC2'), (4, 'D+'), (5, 'D-')],
             [(6, 'GND'), (7, 'SHIELD')], w=20.32),
    'SW1': two_pin('SW_LATCH', 'SW', 12.7),
    'J2': two_pin('CONN_SPK', 'J', 10.16),
    'R': two_pin('R', 'R', 7.62),
    'C': two_pin('C', 'C', 7.62),
    'L': two_pin('L', 'L', 7.62),
    'D': two_pin('D', 'D', 7.62),
    'LED': two_pin('LED', 'D', 7.62),
    'LEDR': two_pin('LED', 'D', 7.62),
    'F': two_pin('FUSE', 'F', 7.62),
}
# --------------------------------------------------------------- net maps
LED_SRC = [                       # constant-current source, P0
    ('LED_RADIO', 17), ('LED_CONN', 18), ('LED_HS', 19), ('LED_AA', 20),
    ('LED_CD', 21), ('LED_OH', 22), ('LED_RD', 23), ('LED_SD', 24),
]
LED_SINK = [('LED_TR', 9), ('LED_MR', 10), ('LED_RI', 11)]   # open-drain P1

NET_J1 = {1: 'GND', 2: 'P1_TXD', 4: 'P1_MSB', 5: 'P1_CTS',
          6: 'P1_RXD', 7: '+12V', 8: 'P1_MCB', 9: 'P1_RI', 3: 'NC', 10: 'NC'}
NET_U1 = {1: '+3V3', 2: 'GND', 3: 'O1_TXD_3V3', 4: 'O1_MCB_3V3', 5: 'NC',
          6: 'NC', 7: 'GND', 8: 'P1_TXD', 9: 'P1_MCB', 10: 'NC', 11: 'NC',
          12: 'GND', 13: '+5V'}
NET_U2 = {1: '+3V3', 2: 'GND', 3: 'IF_CTS', 4: 'IF_RI', 5: 'NC', 6: 'NC',
          7: '+3V3', 8: 'P1_CTS', 9: 'P1_RI', 10: 'NC', 11: 'NC', 12: 'GND',
          13: '+5V'}
NET_U3 = {1: 'NC', 2: 'IF_MSB', 3: 'GND', 4: 'P1_MSB', 5: '+3V3'}
NET_U4 = {1: 'C1P', 2: 'VP', 3: 'C1N', 4: 'C2P', 5: 'C2N', 6: 'VN', 7: 'NC',
          8: 'GND', 9: 'NC', 10: 'GND', 11: 'UART1_TX', 12: 'NC', 13: 'GND',
          14: 'P1_RXD', 15: 'GND', 16: '+3V3'}
NET_U5 = {1: '+3V3', 2: 'GND', 3: 'ESP_EN', 4: 'NC', 5: 'UART1_TX',
          6: 'O1_TXD_3V3', 7: 'I2C_SDA', 8: 'I2C_SCL', 9: 'I2S_BCLK',
          10: 'I2S_LRCLK', 11: 'I2S_DIN', 12: 'INT_PANEL', 13: 'INT_IF',
          14: 'USB_DM_ESP', 15: 'USB_DP_ESP', 16: 'NC', 17: 'NC', 18: 'GND'}
NET_U6 = {1: '+3V3', 2: 'GND', 3: 'I2C_SDA', 4: 'I2C_SCL', 5: 'GND', 6: 'GND',
          7: 'INT_PANEL', 8: 'EXP_RSTN', 12: 'NC', 13: 'NC', 14: 'NC',
          15: 'NC', 16: 'NC'}
for _net, _pin in LED_SRC:
    NET_U6[_pin] = _net
for _net, _pin in LED_SINK:
    NET_U6[_pin] = _net + '_K'
NET_U7 = {1: '+3V3', 2: 'GND', 3: 'I2C_SDA', 4: 'I2C_SCL', 5: '+3V3', 6: 'GND',
          7: 'INT_IF', 8: 'EXP_RSTN', 9: 'IF_CTS', 10: 'IF_RI', 11: 'IF_MSB',
          12: 'O1_MCB_3V3'}
for _p in list(range(13, 17)) + list(range(17, 25)):
    NET_U7[_p] = 'NC'
NET_U8 = {1: '+5V', 2: 'GND', 3: 'I2S_BCLK', 4: 'I2S_LRCLK', 5: 'I2S_DIN',
          6: '+3V3', 7: 'GND', 8: 'SPK_P', 9: 'SPK_N'}
NET_U9 = {1: 'BOOT_N', 2: '+12V_SW', 3: '+12V_SW', 4: 'SS_N', 5: 'FB_N',
          6: 'COMP_N', 7: 'GND', 8: 'PH_N'}
NET_U10 = {1: '+5V', 2: 'GND', 3: '+5V', 4: '+3V3', 5: 'NC'}
NET_J3 = {1: 'VBUS_IN', 2: 'USB_CC1', 3: 'USB_CC2', 4: 'USB_DP_CON',
          5: 'USB_DM_CON', 6: 'GND', 7: 'GND'}
NET_SW1 = {1: '+12V', 2: '+12V_SW'}
NET_J2 = {1: 'SPK_P', 2: 'SPK_N'}

# --------------------------------------------------------------- placement
PLACE = [
    # the machine connector and the level stage
    ('J1', 'J1', 'Conn_02x05 IDC (P1 MODEM)', 60, 150, NET_J1),
    ('U1', 'U1', '74LVC4T245 (TXD/MCB)', 150, 105, NET_U1),
    ('U3', 'U3', '74LVC1G07 (MSB)', 150, 160, NET_U3),
    ('U4', 'U4', 'MAX3232 (RXD)', 150, 225, NET_U4),
    ('U2', 'U2', '74LVC4T245 (CTS/RI)', 150, 320, NET_U2),
    # interface expander, below the stage
    ('U7', 'U7', 'AW9523B interface 0x59', 265, 330, NET_U7),
    # the modem
    ('U5', 'U5', 'ESP32-S2-MINI-2U', 370, 150, NET_U5),
    # panel expander
    ('U6', 'U6', 'AW9523B panel 0x58', 480, 130, NET_U6),
    # audio
    ('U8', 'U8', 'MAX98357A', 620, 400, NET_U8),
    ('J2', 'J2', 'Speaker', 710, 400, NET_J2),
    # power
    ('SW1', 'SW1', 'Slide switch, latching', 450, 45, NET_SW1),
    ('U9', 'U9', 'TPS54331 buck 12.6->5', 520, 55, NET_U9),
    ('U10', 'U10', 'AP2112K-3.3 LDO', 650, 95, NET_U10),
    ('J3', 'J3', 'USB-C sink', 100, 500, NET_J3),
]

# two-terminal parts: (symbol type, ref, value, x, y, net1, net2)
TWO = [
    # buck and its parts
    ('C', 'C1', '220u', 405, 45, '+12V_SW', 'GND'),
    ('C', 'C2', '100n', 455, 92, 'BOOT_N', 'PH_N'),
    ('C', 'C3', '10n', 490, 100, 'SS_N', 'GND'),
    ('L', 'L1', '10uH', 585, 40, 'PH_N', '+5V_P1'),
    ('D', 'D12', 'SS34 catch', 585, 70, 'GND', 'PH_N'),
    ('R', 'R12', '10k', 600, 145, '+5V_P1', 'FB_N'),
    ('R', 'R13', '1k91', 635, 145, 'FB_N', 'GND'),
    ('C', 'C4', '1n', 600, 175, 'COMP_N', 'GND'),
    ('R', 'R14', '10k', 635, 175, 'COMP_N', 'GND'),
    ('C', 'C5', '22u', 620, 40, '+5V_P1', 'GND'),
    ('C', 'C7', '10u', 690, 95, '+3V3', 'GND'),
    # diode-OR and USB
    ('D', 'D13', 'SS14 OR', 350, 470, '+5V_P1', '+5V'),
    ('D', 'D14', 'SS14 OR', 395, 470, '+5V_USB', '+5V'),
    ('C', 'C6', '22u', 440, 470, '+5V', 'GND'),
    ('F', 'F1', 'polyfuse 1A', 165, 500, 'VBUS_IN', '+5V_USB'),
    ('R', 'R15', '5k1', 225, 500, 'USB_CC1', 'GND'),
    ('R', 'R16', '5k1', 225, 528, 'USB_CC2', 'GND'),
    ('R', 'R17', '22R', 292, 500, 'USB_DP_ESP', 'USB_DP_CON'),
    ('R', 'R18', '22R', 292, 528, 'USB_DM_ESP', 'USB_DM_CON'),
    # MAX3232 charge pump
    ('C', 'C8', '100n', 235, 210, 'C1P', 'C1N'),
    ('C', 'C9', '100n', 235, 232, 'C2P', 'C2N'),
    ('C', 'C10', '100n', 235, 254, 'VP', 'GND'),
    ('C', 'C11', '100n', 235, 276, 'VN', 'GND'),
    ('C', 'C12', '100n', 235, 298, '+3V3', 'GND'),
    # ESP32 support
    ('R', 'R19', '10k', 330, 210, 'ESP_EN', '+3V3'),
    ('C', 'C13', '1u', 330, 236, 'ESP_EN', 'GND'),
    ('R', 'R20', '4k7', 330, 262, 'I2C_SDA', '+3V3'),
    ('R', 'R21', '4k7', 330, 288, 'I2C_SCL', '+3V3'),
    # expander support
    ('R', 'R22', '10k', 430, 300, 'INT_PANEL', '+3V3'),
    ('R', 'R23', '10k', 466, 300, 'INT_IF', '+3V3'),
    ('R', 'R24', '10k', 502, 300, 'EXP_RSTN', '+3V3'),
    ('C', 'C14', '100n', 538, 300, 'EXP_RSTN', 'GND'),
    ('R', 'R25', '10k', 470, 380, 'IF_CTS', '+3V3'),
    ('R', 'R26', '10k', 506, 380, 'IF_RI', '+3V3'),
    ('R', 'R27', '10k', 542, 380, 'IF_MSB', '+3V3'),
]

# lamps: source side (pin -> R -> LED -> GND) and sink side (3V3 -> LED -> R -> pin)
for _i, (_net, _pin) in enumerate(LED_SRC):
    _y = 90 + _i * 16
    TWO.append(('R', f'R{_i + 1}', '470R', 545, _y, _net, _net + '_A'))
    TWO.append(('LED', f'D{_i + 1}', '3528', 560.24, _y, _net + '_A', 'GND'))
for _i, (_net, _pin) in enumerate(LED_SINK):
    _y = 230 + _i * 16
    TWO.append(('LEDR', f'D{_i + 9}', '3528', 560.24, _y, '+3V3', _net + '_A'))
    TWO.append(('R', f'R{_i + 9}', '470R', 545, _y, _net + '_K', _net + '_A'))

NOTES = [
    'wifi-comm-pac Rev A - O1NEXT WiFi COMM PAC (issues #324, #325, part of #56)',
    'J1 is a 2x5 IDC: pin n = DE-9 pin n for 1..9; pin 10 is spare.',
    'Pin 7 is +12.6 V DC direct from the machine (2.02 A rail), NOT via R21.',
    'U1/U2 translate the 5 V TTL side; U3 is the open-drain MSB sink.',
    'U4 MAX3232 runs on 3V3 so its drivers swing +/-5.5 V into the bipolar RXD.',
    'U6 = panel expander 0x58 (P0 push-pull CC, P1 open-drain). U7 = handshake 0x59.',
    'Both expanders are fitted: neither is full, so the pin budget is closed.',
    'Power is diode-OR: 12.6 V -> 5 V path, and USB-C 5 V for bench work.',
]
# --------------------------------------------------------------- footprints
# **A schematic with no footprints cannot become a board.**  Every symbol's
# Footprint field was empty in the first revision of this file, on the theory
# that the assignment happens later, at annotation.  That theory does not survive
# contact: `Update PCB from Schematic` transfers *nothing* when the field is
# empty, so the board could not be started at all without hand-assigning 71
# footprints in KiCad -- which is exactly the hand transcription this generator
# exists to avoid.
#
# **Every name below was checked against KiCad's own libraries before it was
# written here** -- confirmed to exist as
# `<kicad>/footprints/<lib>.pretty/<name>.kicad_mod`.  A footprint that does not
# exist is worse than an empty one, because it *looks* assigned.
#
# Keyed by SYMS key, so one line covers every instance of a template part: `R`
# is 27 resistors and `C` is 14 capacitors.
FOOTPRINTS = {
    'J1':  'Connector_PinHeader_2.54mm:PinHeader_2x05_P2.54mm_Vertical',
    'U1':  'Package_SO:TSSOP-16_4.4x5mm_P0.65mm',
    'U2':  'Package_SO:TSSOP-16_4.4x5mm_P0.65mm',
    'U3':  'Package_TO_SOT_SMD:SOT-23-6',
    'U4':  'Package_SO:SOIC-16_3.9x9.9mm_P1.27mm',
    'U6':  'Package_DFN_QFN:QFN-24-1EP_4x4mm_P0.5mm_EP2.6x2.6mm',
    'U7':  'Package_DFN_QFN:QFN-24-1EP_4x4mm_P0.5mm_EP2.6x2.6mm',
    # U8 is a TQFN-16, 3 x 3 mm, 0.5 mm pitch.  The exposed pad is **1.1 x 1.1 mm**,
    # taken from the SnapEDA model for the MAX98357AETE_T rather than guessed --
    # which is what settles the 1.6/1.7/1.75 question, and means KiCad's own
    # library carries it after all.
    'U8':  'Package_DFN_QFN:VQFN-16-1EP_3x3mm_P0.5mm_EP1.1x1.1mm',
    'U9':  'Package_SO:SOIC-8_3.9x4.9mm_P1.27mm',
    'U10': 'Package_TO_SOT_SMD:SOT-23-5',
    # U5: the module.  Espressif's KiCad library has MINI-1/-1U and SOLO-2U and no
    # -2U, so this one is ours -- see footprints/o1next.pretty/README.md, which is
    # where it should be published from.  SnapEDA's model, checked against the
    # datasheet: 0.85 mm pad pitch, rows at +/-7.0 mm, 0.8 x 0.4 mm pads.
    'U5':  'o1next:ESP32-S2-MINI-2U',
    'R':   'Resistor_SMD:R_0603_1608Metric',
    'C':   'Capacitor_SMD:C_0603_1608Metric',
    'L':   'Inductor_SMD:L_1210_3225Metric',
    'D':   'Diode_SMD:D_SMA',
    'F':   'Fuse:Fuse_1206_3216Metric',
    # J2 is a **piezo buzzer**, not a speaker: Multicomp Pro MCKPT-G1340-3917,
    # 12 Vp-p, 4 kHz, 80 dB, 9.5 nF.  Pin pitch 5.08 mm, measured by seating it in
    # a breadboard.  Its own footprint, in the library above.
    'J2':  'o1next:Piezo_Buzzer_Multicomp_MCKPT-G1340-3917',
    # SW1 is SparkFun COM-10860, the Surface Mount Right Angle Switch -- SPST,
    # 6.7 x 2.6 mm.  SparkFun's library is CC BY 4.0, so the footprint is copied
    # into ours *with attribution* rather than referenced: the board then needs no
    # external library, and CI has nothing extra to install.
    'SW1': 'o1next:Slide_SPST_SMD_6.7x2.6mm',
    # The LED is SunLED XZM2CRK168WA: 1.8 x 0.6 mm right-angle, two 0.8 mm square
    # pads 1.8 mm apart on centre.  Drawn, because KiCad's nearest 1.6 x 0.6 mm
    # right-angle is a different part.
    'LED':  'o1next:LED_SunLED_XZM2CRK168WA',
    'LEDR': 'o1next:LED_SunLED_XZM2CRK168WA',
}

# **Open, and deliberately not guessed.**  Each needs a part decision that
# changes the board, and a plausible-but-wrong footprint is a board that does not
# fit -- which is worse than a blank one, because a blank one is visibly undone.
# The generator prints this list on every run so it cannot be forgotten.
FOOTPRINT_OPEN = {
    'J3':  'USB-C receptacle, Same Sky UJ32-C-H-G-DSMT-1-P24-TR.  The footprint is '
           'ready -- o1next:USB_C_SameSky_UJ32-C-H-G-DSMT-1-P24-TR, all 24 contacts '
           'plus six shield pads -- but **it cannot be assigned until the SYMBOL is '
           'rebuilt**: the symbol has 7 pins against the 24 the part has, so assigning it '
           'now would leave 17 pads with no net.  The rebuild is A1-A12 and B1-B12 '
           'with the real signal names, the ten unused contacts carried and marked '
           'no-connect, and it changes the netlist, which check_schematics.py '
           'asserts.  That is why it is its own job and not a footnote here.',
}

for _k, _s in SYMS.items():
    _s.footprint = FOOTPRINTS.get(_k, '')

ref_fp = {}          # ref -> footprint, for symbol_instances


# --------------------------------------------------------------- emitter
out = [
    '(kicad_sch (version 20230121) (generator "eeschema") (generator_version "7.0")',
    f'  (uuid "{uid()}")',
    '  (paper "A1")',
    '  (title_block (title "o1next wifi-comm-pac - O1NEXT WiFi COMM PAC")'
    f' (date "{TODAY}") (rev "A")',
    '    (comment 1 "Issues #324, #325 (part of #56). P1 MODEM 2x5 IDC; 5V TTL level'
    ' stage; AW9523B panel + handshake; MAX98357A audio; 12.6V/USB diode-OR power."))',
    '  (lib_symbols',
]
for _k in ['J1', 'U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'U7', 'U8', 'U9', 'U10',
           'J2', 'J3', 'SW1', 'R', 'C', 'L', 'D', 'LED', 'LEDR', 'F']:
    out.append(SYMS[_k].lib_sexpr())
for _n in sorted(POWER_NETS):
    out.append(PowerSym(_n).lib_sexpr())
out.append(FlagSym().lib_sexpr())
out.append('  )')

insts = []          # placed symbol sexprs
sinst = []          # (ref, value) for symbol_instances
rects = []          # symbol bodies, for the router
pinpts = {}         # net -> [(ref, pin, x, y, side)]
ncs = []            # no-connect points
segs = []           # (net, (x1,y1), (x2,y2))
labels = []         # (net, x, y)
pwr_no = [0]
flag_no = [0]


def emit_symbol(key, ref, value, x, y, netmap):
    s = SYMS[key]
    x, y = snap(x), snap(y)
    sinst.append((ref, value))
    ref_fp[ref] = s.footprint
    rects.append((x - s.w / 2 - 0.6, y - s.h / 2 - 0.6,
                  x + s.w / 2 + 0.6, y + s.h / 2 + 0.6))
    body = [
        f'  (symbol (lib_id "{s.lib_id}") (at {x} {y} 0) (unit 1)'
        f' (exclude_from_sim no) (in_bom yes) (on_board yes) (uuid "{uid()}")',
        f'    (property "Reference" "{ref}" (at {x} {y - s.h / 2 - 2.54} 0)'
        ' (effects (font (size 1.27 1.27))))',
        f'    (property "Value" "{value}" (at {x} {y - s.h / 2 - 5.08} 0)'
        ' (effects (font (size 1.27 1.27))))',
        f'    (property "Footprint" "{s.footprint}" (at 0 0 0)'
        ' (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
    ]
    for n, pname, side, off in s.pins:
        body.append(f'    (pin "{n}" (uuid "{uid()}"))')
        sx, sy = s.pin_sym(n)
        X, Y = snap(x + sx), snap(y - sy)     # symbol Y-up -> sheet Y-down
        net = netmap.get(n)
        if not net or net == 'NC':
            ncs.append((X, Y))
        else:
            pinpts.setdefault(net, []).append((ref, str(n), X, Y, side))
    body.append('  )')
    insts.append('\n'.join(body))


def emit_power(net, x, y):
    pwr_no[0] += 1
    ref = f'#PWR{pwr_no[0]:02d}'
    sinst.append((ref, net))
    insts.append('\n'.join([
        f'  (symbol (lib_id "{PowerSym(net).lib_id}") (at {x} {y} 0) (unit 1)'
        f' (exclude_from_sim no) (in_bom yes) (on_board yes) (uuid "{uid()}")',
        f'    (property "Reference" "{ref}" (at {x} {y - 6.35} 0)'
        ' (effects (font (size 1.27 1.27)) (hide yes)))',
        f'    (property "Value" "{net}" (at {x} {y + 3.81} 0)'
        ' (effects (font (size 1.27 1.27))))',
        '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (pin "1" (uuid "' + uid() + '"))',
        '  )',
    ]))


# --------------------------------------------------------------- router
# A* on a 1.27 mm grid.  Symbols are blocked; another net's wire blocks travel
# *along* it (collinear overlap would short) but not across it (a crossing is
# unambiguous in KiCad: no junction, no connection).  Cells that hold another
# net's wire end are blocked outright, because an endpoint touching a wire is a
# junction.
import heapq

GRID = 1.27
XMAX = int(841 / GRID)
YMAX = int(594 / GRID)


def cell(p):
    return (int(round(p[0] / GRID)), int(round(p[1] / GRID)))


def pt(c):
    return (round(c[0] * GRID, 2), round(c[1] * GRID, 2))


blocked = None


def build_blocked():
    """Symbol bodies, as grid cells -- computed once, after placement."""
    global blocked
    if blocked is not None:
        return
    blocked = set()
    for (rx1, ry1, rx2, ry2) in rects:
        for cx in range(int(rx1 / GRID), int(rx2 / GRID) + 1):
            for cy in range(int(ry1 / GRID), int(ry2 / GRID) + 1):
                blocked.add((cx, cy))

h_own = {}      # cell -> net, for horizontal wire cells
v_own = {}      # cell -> net, for vertical wire cells
endp = {}       # cell -> net, for wire ends
pin_own = {}
fallbacks = []


def mark(net, a, b):
    ca, cb = cell(a), cell(b)
    if ca[1] == cb[1]:
        key = h_own
    else:
        key = v_own
    lo, hi = (ca, cb) if ca <= cb else (cb, ca)
    if lo[0] == hi[0]:
        for cy in range(lo[1], hi[1] + 1):
            key[(lo[0], cy)] = net
    else:
        for cx in range(lo[0], hi[0] + 1):
            key[(cx, lo[1])] = net
    endp[ca] = net
    endp[cb] = net


def build_pins():
    """A wire must never pass through another component's pin."""
    if pin_own:
        return
    for n, pts in pinpts.items():
        for (_r, _p, x, y, _s) in pts:
            pin_own[cell((x, y))] = n


def astar(net, s, g, limit=3000000):
    """A* over (cell, heading).  Other nets' wires are expensive, not impossible:
    travel along them would short, so it costs 200; ending on one would make a
    junction, so it costs 400.  Symbol bodies stay impassable.
    """
    DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))

    def penalty(c, d):
        p = 0
        if d < 2:            # horizontal move
            if c in h_own and h_own[c] != net:
                p += 200
        else:
            if c in v_own and v_own[c] != net:
                p += 200
        if c in endp and endp[c] != net:
            p += 400
        return p

    start = (s, 4)       # heading 4 = no heading yet
    dist = {start: 0}
    prev = {}
    pq = [(abs(s[0] - g[0]) + abs(s[1] - g[1]), 0, s, 4)]
    seen = set()
    while pq:
        _f, cost, c, d = heapq.heappop(pq)
        if (c, d) in seen:
            continue
        seen.add((c, d))
        if c == g:
            state = (c, d)
            path = [c]
            while state[0] != s or state[1] != 4:
                state = prev[state]
                path.append(state[0])
            path.reverse()
            return path
        if len(seen) > limit:
            return None
        for nd, (dx, dy) in enumerate(DIRS):
            n = (c[0] + dx, c[1] + dy)
            if not (0 <= n[0] <= XMAX and 0 <= n[1] <= YMAX):
                continue
            if n in blocked:
                continue
            if n in endp and endp[n] != net:
                continue
            if n in pin_own and pin_own[n] != net:
                continue
            if nd < 2 and n in h_own and h_own[n] != net:
                continue
            if nd >= 2 and n in v_own and v_own[n] != net:
                continue
            step = 1 + (0 if d == 4 or nd == d else 2)
            nc = cost + step
            key = (n, nd)
            if nc < dist.get(key, 1 << 30):
                dist[key] = nc
                prev[key] = (c, d)
                heapq.heappush(pq, (nc + abs(n[0] - g[0]) + abs(n[1] - g[1]), nc, n, nd))
    return None


def simplify(path):
    if len(path) < 3:
        return path
    keep = [path[0]]
    for i in range(1, len(path) - 1):
        a, b, c = path[i - 1], path[i], path[i + 1]
        if (b[0] - a[0]) * (c[1] - b[1]) != (b[1] - a[1]) * (c[0] - b[0]):
            keep.append(b)
    keep.append(path[-1])
    return keep


def route(net, a, b):
    build_blocked()
    build_pins()
    s, g = cell(a), cell(b)
    path = astar(net, s, g)
    if path is None:
        if net == 'ZZZ':
            for label_, c in (('start', cell(a)), ('goal', cell(b))):
                print(label_, c, 'blk', c in blocked, 'endp', endp.get(c),
                      'h', h_own.get(c), 'v', v_own.get(c))
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (c[0]+dx, c[1]+dy)
                    print('   nb', n, 'blk', n in blocked, 'endp', endp.get(n),
                          'h', h_own.get(n), 'v', v_own.get(n))
        fallbacks.append((net, a, b))
        path = [s, (g[0], s[1]), g]
    else:
        path = simplify(path)
    pts = [a] + [pt(c) for c in path[1:-1]] + [b]
    for i in range(len(pts) - 1):
        if pts[i] != pts[i + 1]:
            mark(net, pts[i], pts[i + 1])
            segs.append((net, pts[i], pts[i + 1]))


for _key, _ref, _val, _x, _y, _net in PLACE:
    emit_symbol(_key, _ref, _val, _x, _y, _net)
for _key, _ref, _val, _x, _y, _n1, _n2 in TWO:
    emit_symbol(_key, _ref, _val, _x, _y, {1: _n1, 2: _n2})

# power nets: one power symbol per pin, joined by a short stub
for net in sorted(POWER_NETS):
    first = None
    for (_ref, _pin, X, Y, side) in pinpts.get(net, []):
        dx = 5.08 if side == 'R' else -5.08
        fx = snap(X + dx)
        emit_power(net, fx, Y)
        segs.append((net, (X, Y), (fx, Y)))
        if first is None:
            first = (fx, Y)
    if first is not None:
        flag_no[0] += 1
        ref = f'#FLG{flag_no[0]:02d}'
        sinst.append((ref, 'PWR_FLAG'))
        insts.append('\n'.join([
            f'  (symbol (lib_id "local:PWR_FLAG") (at {first[0]} {first[1]} 180) (unit 1)'
            f' (exclude_from_sim no) (in_bom yes) (on_board yes) (uuid "{uid()}")',
            f'    (property "Reference" "{ref}" (at {first[0]} {first[1] + 5.08} 0)'
            ' (effects (font (size 1.27 1.27)) (hide yes)))',
            f'    (property "Value" "PWR_FLAG" (at {first[0]} {first[1] - 5.08} 0)'
            ' (effects (font (size 1.27 1.27))))',
            '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
            '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
            '    (pin "1" (uuid "' + uid() + '"))',
            '  )',
        ]))

# signal nets: a wired star from the first pin, and one label for the name
def _span(n):
    pts = pinpts[n]
    xs = [p[2] for p in pts]
    ys = [p[3] for p in pts]
    return (max(xs) - min(xs)) + (max(ys) - min(ys))


for net in sorted(pinpts, key=_span, reverse=True):
    if net in POWER_NETS:
        continue
    pts = pinpts[net]
    a = (pts[0][2], pts[0][3])
    for (_ref, _pin, X, Y, _side) in pts[1:]:
        route(net, a, (X, Y))
    labels.append((net, a[0], a[1]))

for (net, a, b) in segs:
    insts.append(f'  (wire (pts (xy {a[0]} {a[1]}) (xy {b[0]} {b[1]}))'
                 f' (stroke (width 0) (type default)) (uuid "{uid()}"))')
for (net, x, y) in labels:
    insts.append(f'  (label "{net}" (at {x} {y} 0)'
                 f' (effects (font (size 1.27 1.27)) (justify left bottom))'
                 f' (uuid "{uid()}"))')
for (x, y) in ncs:
    insts.append(f'  (no_connect (at {x} {y}) (uuid "{uid()}"))')
for i, note in enumerate(NOTES):
    insts.append(f'  (text "{note}" (at 30 {535 + i * 6} 0)'
                 f' (effects (font (size 1.6 1.6)) (justify left)) (uuid "{uid()}"))')

out.extend(insts)
out.append('  (sheet_instances (path "/" (page "1")))')
si = '  (symbol_instances'
for ref, val in sinst:
    si += (f' (path "/" (reference "{ref}") (unit 1) (value "{val}")'
           f' (footprint "{ref_fp.get(ref, "")}"))')
si += ')'
out.append(si)
out.append(')')

with open('wifi-comm-pac.kicad_sch', 'w') as f:
    f.write('\n'.join(out) + '\n')
if fallbacks:
    print('WARNING', len(fallbacks), 'unroutable nets:', fallbacks)

comp = [ref for ref, _ in sinst if not ref.startswith('#')]
missing = [ref for ref in comp if not ref_fp.get(ref)]
print('footprints: %d of %d component symbols have one; %d do not'
      % (len(comp) - len(missing), len(comp), len(missing)))
if missing:
    print()
    print('OPEN -- no footprint, and each is a part decision rather than a lookup:')
    for _k in sorted(FOOTPRINT_OPEN):
        print('  %-5s %s' % (_k, FOOTPRINT_OPEN[_k]))
    print()
    print('  A schematic with empty footprints transfers NOTHING to the PCB.')
    print('  Fill FOOTPRINTS above; every name there is checked against the library.')

print('wrote wifi-comm-pac.kicad_sch:',
      len(segs), 'wire segments,', len(labels), 'labels,',
      len(ncs), 'no-connects,', len(sinst), 'symbols,',
      len(rects), 'bodies')
