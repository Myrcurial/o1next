#!/usr/bin/env python3
"""Generate the wifi-comm-pac Rev A schematic for issues #324 / #325.

Structural schematic for layout, in the same spirit as
../floppy-adapter/gen_floppy_adapter_sch.py and
../interposer-upgrade/reva/gen_reva_sch.py: symbols are placed and every pin is
tied to a net by a label, so the mapping can be edited without re-routing.

NOTE ON GEOMETRY: KiCad stores symbol pin coordinates with Y up and the sheet has
Y down, so a placed symbol's pin lands at (x + px, y - py).  The generators in
this repo use that convention; check_schematics.py asserts the resulting nets.

NOTE ON PIN NUMBERS: for the multi-pin ICs the numbers below are *logical*, not
the vendor footprint's.  They exist so the netlist checker can name a pin; the
real assignment is made at footprint annotation, exactly as the relay in the
floppy adapter does.  The connectors (J1, J2, J3) and the two AW9523B parts use
their real numbering, because those are the ones a layout depends on.

Regenerate: python3 gen_wifi_comm_pac_sch.py   (writes wifi-comm-pac.kicad_sch)
KiCad is not required to generate; open/re-save in KiCad 7+ to normalise.
"""
import datetime
import uuid


def uid():
    return str(uuid.uuid4())


TODAY = str(datetime.date.today())


class Symbol:
    """Minimal KiCad symbol builder (rectangle body, L/R pins)."""

    def __init__(self, name, ref_letter, w, h):
        self.name = name
        self.ref_letter = ref_letter
        self.w, self.h = w, h
        self.pins = []          # (number, name, side, offset_from_bottom)
        self.lib_id = 'local:' + name

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
        s += '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
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


def ic(name, ref, left, right, w=25.4):
    """Rectangle IC with pins down the left and right edges."""
    n = max(len(left), len(right))
    h = 2.54 * (n - 1) + 12.7
    s = Symbol(name, ref, w, h)
    for i, (num, pname) in enumerate(left):
        s.add(num, pname, 'L', h - 5.08 - 2.54 * i)
    for i, (num, pname) in enumerate(right):
        s.add(num, pname, 'R', h - 5.08 - 2.54 * i)
    return s


def two_pin(name, ref, w=10.16):
    """Horizontal two-terminal part: pin 1 left, pin 2 right."""
    s = Symbol(name, ref, w, 5.08)
    s.add(1, '1', 'L', 2.54)
    s.add(2, '2', 'R', 2.54)
    return s


# --------------------------------------------------------------- symbols
SYMS = {
    'J1': ic('CONN_2X05_MODEM', 'J',
             [(1, 'GND'), (2, 'TXD'), (4, 'MSB'), (5, 'CTS'), (6, 'RXD')],
             [(8, 'MCB'), (7, '+12.6V'), (9, 'RI'), (3, 'NC'), (10, 'SPARE')],
             w=22.86),
    'U1': ic('74LVC4T245_TXD', 'U',
             [(1, 'VCCA'), (2, 'GND'), (3, 'A1'), (4, 'A2'), (5, 'A3'),
              (6, 'A4'), (7, 'DIR')],
             [(8, 'B1'), (9, 'B2'), (10, 'B3'), (11, 'B4'), (12, '/OE'),
              (13, 'VCCB')]),
    'U2': ic('74LVC4T245_HS', 'U',
             [(1, 'VCCA'), (2, 'GND'), (3, 'A1'), (4, 'A2'), (5, 'A3'),
              (6, 'A4'), (7, 'DIR')],
             [(8, 'B1'), (9, 'B2'), (10, 'B3'), (11, 'B4'), (12, '/OE'),
              (13, 'VCCB')]),
    'U3': ic('74LVC1G07_MSB', 'U',
             [(2, 'A'), (3, 'GND'), (1, 'NC')],
             [(4, 'Y'), (5, 'VCC')], w=17.78),
    'U4': ic('MAX3232_RXD', 'U',
             [(1, 'C1+'), (2, 'V+'), (3, 'C1-'), (4, 'C2+'), (5, 'C2-'),
              (6, 'V-'), (7, 'T2OUT'), (8, 'R2IN')],
             [(9, 'R2OUT'), (10, 'T2IN'), (11, 'T1IN'), (12, 'R1OUT'),
              (13, 'R1IN'), (14, 'T1OUT'), (15, 'GND'), (16, 'VCC')]),
    'U5': ic('ESP32-S2-MINI-2U', 'U',
             [(1, '3V3'), (2, 'GND'), (3, 'EN'), (4, 'IO0'), (5, 'IO15'),
              (6, 'IO16'), (7, 'IO33'), (8, 'IO34'), (9, 'IO35')],
             [(10, 'IO36'), (11, 'IO37'), (12, 'IO38'), (13, 'IO21'),
              (14, 'IO19'), (15, 'IO20'), (16, 'IO43'), (17, 'IO44'),
              (18, 'GND')], w=35.56),
    'U6': ic('AW9523B_PANEL', 'U',
             [(1, 'VDD'), (2, 'GND'), (3, 'SDA'), (4, 'SCL'), (5, 'AD0'),
              (6, 'AD1'), (7, 'INTN'), (8, 'RESETN'),
              (9, 'P1_0'), (10, 'P1_1'), (11, 'P1_2'), (12, 'P1_3'),
              (13, 'P1_4'), (14, 'P1_5'), (15, 'P1_6'), (16, 'P1_7')],
             [(17, 'P0_0'), (18, 'P0_1'), (19, 'P0_2'), (20, 'P0_3'),
              (21, 'P0_4'), (22, 'P0_5'), (23, 'P0_6'), (24, 'P0_7')],
             w=33.02),
    'U7': ic('AW9523B_IFACE', 'U',
             [(1, 'VDD'), (2, 'GND'), (3, 'SDA'), (4, 'SCL'), (5, 'AD0'),
              (6, 'AD1'), (7, 'INTN'), (8, 'RESETN'),
              (9, 'P1_0'), (10, 'P1_1'), (11, 'P1_2'), (12, 'P1_3'),
              (13, 'P1_4'), (14, 'P1_5'), (15, 'P1_6'), (16, 'P1_7')],
             [(17, 'P0_0'), (18, 'P0_1'), (19, 'P0_2'), (20, 'P0_3'),
              (21, 'P0_4'), (22, 'P0_5'), (23, 'P0_6'), (24, 'P0_7')],
             w=33.02),
    'U8': ic('MAX98357A', 'U',
             [(1, 'VDD'), (2, 'GND'), (3, 'BCLK'), (4, 'LRCLK'), (5, 'DIN')],
             [(6, 'SD_MODE'), (7, 'GAIN'), (8, 'OUT+'), (9, 'OUT-')]),
    'U9': ic('TPS54331', 'U',
             [(1, 'BOOT'), (2, 'VIN'), (3, 'EN'), (4, 'SS'), (5, 'VSENSE')],
             [(6, 'COMP'), (7, 'GND'), (8, 'PH')]),
    'U10': ic('AP2112K-3.3', 'U',
              [(1, 'VIN'), (2, 'GND'), (3, 'EN')],
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
}
# --------------------------------------------------------------- panel nets
LED_SRC = [                       # constant-current source, P0
    ('LED_RADIO', 17), ('LED_CONN', 18), ('LED_HS', 19), ('LED_AA', 20),
    ('LED_CD', 21), ('LED_OH', 22), ('LED_RD', 23), ('LED_SD', 24),
]
LED_SINK = [('LED_TR', 9), ('LED_MR', 10), ('LED_RI', 11)]   # open-drain P1

# --------------------------------------------------------------- net maps
NET_J1 = {1: 'GND', 2: 'P1_TXD', 3: 'NC', 4: 'P1_MSB', 5: 'P1_CTS',
          6: 'P1_RXD', 7: '+12V', 8: 'P1_MCB', 9: 'P1_RI', 10: 'NC'}

# U1: 5 V -> 3.3 V.  DIR low = B to A, so TXD and MCB flow toward the ESP32.
NET_U1 = {1: '+3V3', 2: 'GND', 3: 'O1_TXD_3V3', 4: 'O1_MCB_3V3', 5: 'NC',
          6: 'NC', 7: 'GND', 8: 'P1_TXD', 9: 'P1_MCB', 10: 'NC', 11: 'NC',
          12: 'GND', 13: '+5V'}

# U2: 3.3 V -> 5 V.  DIR high = A to B, so CTS and RI drive the machine.
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

# U6 panel expander, 0x58 (AD1=0, AD0=0)
NET_U6 = {1: '+3V3', 2: 'GND', 3: 'I2C_SDA', 4: 'I2C_SCL', 5: 'GND', 6: 'GND',
          7: 'INT_PANEL', 8: 'EXP_RSTN',
          12: 'NC', 13: 'NC', 14: 'NC', 15: 'NC', 16: 'NC'}
for _net, _pin in LED_SRC:
    NET_U6[_pin] = _net
for _net, _pin in LED_SINK:
    NET_U6[_pin] = _net + '_K'

# U7 interface expander, 0x59 (AD1=0, AD0=1)
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
    # P1 interface and level stage
    ('J1', 'J1', 'Conn_02x05 IDC (P1 MODEM)', 55, 75, NET_J1),
    ('U1', 'U1', '74LVC4T245 (TXD/MCB 5V->3V3)', 135, 70, NET_U1),
    ('U2', 'U2', '74LVC4T245 (CTS/RI 3V3->5V)', 135, 145, NET_U2),
    ('U3', 'U3', '74LVC1G07 (MSB open-drain)', 215, 70, NET_U3),
    ('U4', 'U4', 'MAX3232 (RXD bipolar)', 215, 145, NET_U4),
    # ESP32-S2 module
    ('U5', 'U5', 'ESP32-S2-MINI-2U', 375, 105, NET_U5),
    # panel expander and its lamps
    ('U6', 'U6', 'AW9523B panel 0x58', 75, 265, NET_U6),
    ('U7', 'U7', 'AW9523B interface 0x59', 420, 265, NET_U7),
    # audio
    ('U8', 'U8', 'MAX98357A', 520, 265, NET_U8),
    ('J2', 'J2', 'Speaker', 570, 315, NET_J2),
    # power
    ('SW1', 'SW1', 'Slide switch, latching', 405, 45, NET_SW1),
    ('U9', 'U9', 'TPS54331 buck 12.6->5', 470, 120, NET_U9),
    ('U10', 'U10', 'AP2112K-3.3 LDO', 545, 190, NET_U10),
    ('J3', 'J3', 'USB-C sink', 470, 350, NET_J3),
]

# two-terminal parts: (symbol type, ref, value, x, y, net1, net2)
TWO = [
    ('C', 'C1', '220u', 445, 45, '+12V_SW', 'GND'),
    ('C', 'C2', '100n', 405, 100, 'BOOT_N', 'PH_N'),
    ('C', 'C3', '10n', 405, 125, 'SS_N', 'GND'),
    ('L', 'L1', '10uH', 540, 95, 'PH_N', '+5V_P1'),
    ('D', 'D12', 'SS34 catch', 540, 125, 'GND', 'PH_N'),
    ('R', 'R12', '10k', 405, 160, '+5V_P1', 'FB_N'),
    ('R', 'R13', '1k91', 445, 160, 'FB_N', 'GND'),
    ('C', 'C4', '1n', 405, 190, 'COMP_N', 'GND'),
    ('R', 'R14', '10k', 445, 190, 'COMP_N', 'GND'),
    ('C', 'C5', '22u', 540, 160, '+5V_P1', 'GND'),
    ('D', 'D13', 'SS14 OR', 500, 235, '+5V_P1', '+5V'),
    ('D', 'D14', 'SS14 OR', 540, 235, '+5V_USB', '+5V'),
    ('C', 'C6', '22u', 470, 235, '+5V', 'GND'),
    ('C', 'C7', '10u', 500, 190, '+3V3', 'GND'),
    ('F', 'F1', 'polyfuse 1A', 405, 350, 'VBUS_IN', '+5V_USB'),
    ('R', 'R15', '5k1', 445, 350, 'USB_CC1', 'GND'),
    ('R', 'R16', '5k1', 445, 375, 'USB_CC2', 'GND'),
    ('R', 'R17', '22R', 510, 350, 'USB_DP_ESP', 'USB_DP_CON'),
    ('R', 'R18', '22R', 510, 375, 'USB_DM_ESP', 'USB_DM_CON'),
    # MAX3232 charge pump
    ('C', 'C8', '100n', 140, 195, 'C1P', 'C1N'),
    ('C', 'C9', '100n', 140, 221, 'C2P', 'C2N'),
    ('C', 'C10', '100n', 140, 247, 'VP', 'GND'),
    ('C', 'C11', '100n', 140, 273, 'VN', 'GND'),
    ('C', 'C12', '100n', 140, 299, '+3V3', 'GND'),
    # ESP32 support
    ('R', 'R19', '10k', 320, 160, 'ESP_EN', '+3V3'),
    ('C', 'C13', '1u', 320, 185, 'ESP_EN', 'GND'),
    ('R', 'R20', '4k7', 320, 210, 'I2C_SDA', '+3V3'),
    ('R', 'R21', '4k7', 320, 235, 'I2C_SCL', '+3V3'),
    # expander support
    ('R', 'R22', '10k', 120, 330, 'INT_PANEL', '+3V3'),
    ('R', 'R23', '10k', 160, 330, 'INT_IF', '+3V3'),
    ('R', 'R24', '10k', 200, 330, 'EXP_RSTN', '+3V3'),
    ('C', 'C14', '100n', 240, 330, 'EXP_RSTN', 'GND'),
    ('R', 'R25', '10k', 350, 330, 'IF_CTS', '+3V3'),
    ('R', 'R26', '10k', 390, 330, 'IF_RI', '+3V3'),
    ('R', 'R27', '10k', 430, 330, 'IF_MSB', '+3V3'),
]

# lamps: source side (pin -> R -> LED -> GND) and sink side (3V3 -> LED -> R -> pin)
for _i, (_net, _pin) in enumerate(LED_SRC):
    _x = 200 + (_i % 4) * 62
    _y = 200 + (_i // 4) * 26
    TWO.append(('R', f'R{_i + 1}', '470R', _x, _y, _net, _net + '_A'))
    TWO.append(('LED', f'D{_i + 1}', '3528', _x + 30, _y, _net + '_A', 'GND'))
for _i, (_net, _pin) in enumerate(LED_SINK):
    _x = 200 + _i * 62
    _y = 285
    TWO.append(('LED', f'D{_i + 9}', '3528', _x, _y, '+3V3', _net + '_A'))
    TWO.append(('R', f'R{_i + 9}', '470R', _x + 30, _y, _net + '_A', _net + '_K'))

NOTES = [
    'wifi-comm-pac Rev A - O1NEXT WiFi COMM PAC (issues #324, #325, part of #56)',
    'J1 is a 2x5 IDC: pin n = DE-9 pin n for 1..9; pin 10 is spare.',
    'Pin 7 is +12.6 V DC direct from the machine (2.02 A rail), NOT via R21.',
    'U1/U2 translate the 5 V TTL side; U3 is the open-drain MSB sink.',
    'U4 MAX3232 runs on 3V3 so its drivers swing +/-5.5 V into the bipolar RXD.',
    'U6 = panel expander 0x58 (P0 push-pull CC, P1 open-drain). U7 = handshake 0x59.',
    'Both expanders are fitted: neither is full, so the pin budget is closed.',
    'Audio is MAX98357A on +5V. Power is diode-OR: 12.6V path and USB-C path.',
    'IC pin numbers here are LOGICAL; bind them at footprint annotation.',
]
SYMS['F'] = two_pin('FUSE', 'F', 7.62)

# --------------------------------------------------------------- emit
out = [
    '(kicad_sch (version 20230121) (generator "eeschema") (generator_version "7.0")',
    f'  (uuid "{uid()}")',
    '  (paper "A2")',
    '  (title_block (title "o1next wifi-comm-pac - O1NEXT WiFi COMM PAC")'
    f' (date "{TODAY}") (rev "A")',
    '    (comment 1 "Issues #324, #325 (part of #56). P1 MODEM 2x5 IDC; 5V TTL level'
    ' stage; AW9523B panel + handshake; MAX98357A audio; 12.6V/USB diode-OR power."))',
    '  (lib_symbols',
]
for _k in ['J1', 'U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'U7', 'U8', 'U9', 'U10',
           'J2', 'J3', 'SW1', 'R', 'C', 'L', 'D', 'LED', 'F']:
    out.append(SYMS[_k].lib_sexpr())
out.append('  )')

wires, labels, ncs, insts, sinst = [], [], [], [], []


def snap(v):
    """KiCad wants wire and label ends on the 1.27 mm grid."""
    return round(round(v / 1.27) * 1.27, 3)


def place(key, ref, value, x, y, netmap):
    s = SYMS[key]
    x, y = snap(x), snap(y)
    sinst.append((ref, value))
    body = [
        f'  (symbol (lib_id "{s.lib_id}") (at {x} {y} 0) (unit 1)'
        f' (exclude_from_sim no) (in_bom yes) (on_board yes) (uuid "{uid()}")',
        f'    (property "Reference" "{ref}" (at {x} {y - s.h / 2 - 2.54} 0)'
        ' (effects (font (size 1.27 1.27))))',
        f'    (property "Value" "{value}" (at {x} {y - s.h / 2 - 5.08} 0)'
        ' (effects (font (size 1.27 1.27))))',
        '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
    ]
    for n, pname, side, off in s.pins:
        body.append(f'    (pin "{n}" (uuid "{uid()}"))')
        sx, sy = s.pin_sym(n)
        X, Y = snap(x + sx), snap(y - sy)   # symbol Y-up -> sheet Y-down
        net = netmap.get(n)
        if not net or net == 'NC':
            ncs.append((X, Y))
            continue
        dx = -5.08 if side == 'L' else 5.08
        wires.append((X, Y, X + dx, Y))
        labels.append((net, X + dx, Y, 'right' if side == 'L' else 'left'))
    body.append('  )')
    insts.append('\n'.join(body))


for _key, _ref, _val, _x, _y, _net in PLACE:
    place(_key, _ref, _val, _x, _y, _net)

for _key, _ref, _val, _x, _y, _n1, _n2 in TWO:
    place(_key, _ref, _val, _x, _y, {1: _n1, 2: _n2})

for (x1, y1, x2, y2) in wires:
    insts.append(f'  (wire (pts (xy {x1} {y1}) (xy {x2} {y2}))'
                 f' (stroke (width 0) (type default)) (uuid "{uid()}"))')
for (net, x, y, just) in labels:
    insts.append(f'  (label "{net}" (at {x} {y} 0)'
                 f' (effects (font (size 1.27 1.27)) (justify {just} bottom))'
                 f' (uuid "{uid()}"))')
for (x, y) in ncs:
    insts.append(f'  (no_connect (at {x} {y}) (uuid "{uid()}"))')
for i, note in enumerate(NOTES):
    insts.append(f'  (text "{note}" (at 30 {352 + i * 6} 0)'
                 f' (effects (font (size 1.6 1.6)) (justify left)) (uuid "{uid()}"))')

out.extend(insts)
out.append('  (sheet_instances (path "/" (page "1")))')
si = '  (symbol_instances'
for ref, val in sinst:
    si += f' (path "/" (reference "{ref}") (unit 1) (value "{val}") (footprint ""))'
si += ')'
out.append(si)
out.append(')')

with open('wifi-comm-pac.kicad_sch', 'w') as f:
    f.write('\n'.join(out) + '\n')
print('wrote wifi-comm-pac.kicad_sch:',
      len(wires), 'wires,', len(labels), 'labels,',
      len(ncs), 'no-connects,', len(sinst), 'symbols')
