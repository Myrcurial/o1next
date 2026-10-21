#!/usr/bin/env python3
"""Generate the wifi-comm-pac Rev A schematic for issues #324 / #325.

**Two directories, and the generator only ever writes into one of them.**

    wifi-comm-pac-generated/   the generator's output.  Regenerated at will.
    wifi-comm-pac-edited/      the copy a person works on.

The generator is the *first take* -- the mathematical proof that the circuit is
what the netlist says it is.  It is not a finished drawing, and it cannot be one:
turning it into something a person can read and work on takes a person.  So both
exist, and the rule between them is one line:

    if -edited/ holds a schematic, the copy is ABORTED and the generator says so.
    if -edited/ is empty, the generated schematic is copied across.

That way a regeneration can never overwrite somebody's work, and the first time
anyone picks the board up they get a starting point without having to run
anything.  To deliberately re-seed from a fresh generation, empty -edited/ first
-- and know that doing so discards whatever was in it.

Geometry: KiCad stores symbol pins with Y up and the sheet with Y down, so a
placed symbol's pin lands at (x + px, y - py).  check_schematics.py asserts the
resulting nets.

Routing: signal nets are wired, not label-connected, and the wiring is a
**spanning tree** whose segments are then normalised so that no two ever overlap
and every pin that lands mid-wire gets a junction.  That normalisation is not
cosmetic: the earlier star router emitted overlapping collinear segments, KiCad
tidied them on its first save, and the tidying disconnected 14 pins across 10
nets.  Anything KiCad would rewrite is a wire we have drawn wrong.

NOTE ON PIN NUMBERS: for the multi-pin ICs the numbers are *logical*, not the
vendor footprint's.  They exist so the netlist checker can name a pin; the real
assignment is made at footprint annotation, as the floppy adapter's relay does.
The connectors and the two AW9523B parts use their real numbering, and J3 uses
the USB-C part's own (A1-A12, B1-B12, SH1-SH6).  See pin_partial in
tools/check_schematics.py for which parts are still logical and why.

Regenerate: python3 gen_wifi_comm_pac_sch.py   (writes into -generated/)
"""
import datetime
import re
import shutil
import uuid
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
BOARD = 'wifi-comm-pac'
GEN_DIR = HERE / (BOARD + '-generated')
EDIT_DIR = HERE / (BOARD + '-edited')


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
        self.pins = []          # (number, name, side, offset_from_bottom, hide)
        self.lib_id = 'local:' + name
        self.footprint = ''     # set from FOOTPRINTS below, keyed by SYMS key

    def add(self, num, pname, side, off, hide=False):
        self.pins.append((num, pname, side, off, hide))
        return self

    def _find(self, num):
        for n, p, side, off, _hide in self.pins:
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
        for n, p, side, off, hide in self.pins:
            ax, ay = self.pin_sym(n)
            rot = 0 if side == 'L' else 180
            hid = ' hide' if hide else ''
            s += (f'      (pin passive line (at {ax} {ay} {rot}) (length 2.54){hid}'
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


def stack_onto(sym, anchor, nums, name):
    """Hide *nums* behind *anchor*, on the same symbol point.

    A module brings out pads a symbol does not want to draw.  The
    ESP32-S2-MINI-2U has **33 ground pads** -- GND1, GND2 and GND3 in the
    module's own grouping -- and the footprint has a pad for every one, so every
    one has to land on a net or `Update PCB from Schematic` leaves it floating.
    Drawing 33 GND pins would make the symbol 84 mm tall and cover the sheet in
    ground symbols, so they are stacked: one visible pin carries the name, the
    rest sit behind it and are hidden.  KiCad connects stacked pins, so the
    netlist still carries all 33 numbers.

    This is the vendor's own convention -- SnapEDA's symbol for this module does
    exactly this -- and it is why a 73-pad module is a readable symbol.
    """
    _p, side, off = sym._find(anchor)
    for n in nums:
        sym.add(n, name, side, off, hide=True)
    return sym


# ------------------------------------------------- U5's pads, named once
# The module's 33 ground pads, its 26 unused GPIO, and its own pad 27.  Named here
# rather than repeated, so the symbol, the net map and the checker cannot drift
# apart -- and so the arithmetic is checkable: 13 used + 33 ground + 27 unused is
# exactly the 73 pads the footprint has.
U5_GND = (['1', '2', '30', '42', '43'] + [str(p) for p in range(46, 56)]
          + ['56', '57', '58', '59', '60', '62']
          + [f'61_{i}' for i in range(1, 10)]
          + ['63', '64', '65'])
# The 26 GPIO this board leaves free, as **pad -> the module's own IO name**.  One
# table used three ways: to build U5's symbol, to name the nets, and to label the
# breakout header.  That is deliberate -- three separate lists would drift, and
# the first thing to drift would be a header pin labelled IO18 that is really
# IO17, which is the worst possible bug on a header a hobbyist is meant to use.
U5_FREE = [
    ('4', 'IO0'), ('5', 'IO1'), ('6', 'IO2'), ('7', 'IO3'), ('8', 'IO4'),
    ('9', 'IO5'), ('10', 'IO6'), ('11', 'IO7'), ('12', 'IO8'), ('13', 'IO9'),
    ('14', 'IO10'), ('15', 'IO11'), ('16', 'IO12'), ('17', 'IO13'),
    ('18', 'IO14'), ('21', 'IO17'), ('22', 'IO18'), ('26', 'IO26'),
    ('35', 'IO39'), ('36', 'IO40'), ('37', 'IO41'), ('38', 'IO42'),
    ('39', 'IO43'), ('40', 'IO44'), ('41', 'IO45'), ('44', 'IO46'),
]
U5_FREE_PADS = [p for p, _ in U5_FREE]
U5_NC = ['27'] + U5_FREE_PADS
U5_USED = ['3', '45', '19', '20', '28', '29', '31', '32', '33', '34', '25',
           '23', '24']
U5_PADS = U5_USED + U5_GND + U5_NC

# 33 ground pads behind one visible pin, which is what makes a 73-pad module a
# readable symbol.  See stack_onto.  (The call is below the SYMS table, because it
# needs the symbol to exist.)

# --------------------------------------------------------------- symbols
# Pin sides follow the signal flow left -> right: the machine (J1) on the left,
# then the level stage, then the ESP32, then the expanders and the panel.
SYMS = {
    # ---- J1: the 2x5 IDC on the machine's P1 pigtail -------------------------
    # **Right angle, shrouded, keyed** -- `IDC-Header_2x05_P2.54mm_Horizontal`, a
    # DIN 41651 / IEC 60603-13 box header, not the plain pin header this used to
    # be.  Two reasons, and the second is the one that was wrong before:
    #
    #   1. the cable comes out the front of the floppy pocket, so the connector has
    #      to be right angle, not vertical;
    #   2. the cable **is keyed**, and a keyed socket cannot go on plain pins --
    #      it needs the shroud with its polarising feature.  The old footprint
    #      could not accept the cable it was specified for.
    #
    # Orientation is fixed by the footprint, at rotation 0, and it is worth writing
    # down because it is the answer to the mechanical unknown this board carried:
    # the pads are at x=0 (odd) and x=2.54 (even) running in +Y, the shroud body is
    # offset +X, so the **mating face points +X**.  Standing in front of it looking
    # in, your right hand is +Y, and pin numbers increase with +Y -- so **pin 1 is
    # on the left**, which is what was asked for.  check_schematics.py asserts the
    # horizontal footprint so this cannot silently regress.
    #
    # The key is a rib inside the shroud at y=7.13, between the third and fourth pin
    # pairs, and the part must be fitted **key down, toward the PCB**.  That one the
    # schematic can only record: a footprint is 2D and has no "which way up".
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
    # ---- U5: the module, with the part's OWN pin numbers --------------------
    # U5 is the second symbol here that uses the part's real numbering, for the
    # same reason J3 does: its footprint has 73 pads and every one must land on a
    # net, or `Update PCB from Schematic` leaves it floating.  The old symbol had
    # 18 pins numbered 1..18 and the numbers **collided by name while disagreeing
    # in meaning** -- symbol pin 1 was +3V3 and the module's pad 1 is GND1, so a
    # transfer shorted 3.3 V to ground.
    #
    # The map is the module's, from the datasheet's pin layout, and it is
    # cross-checked against SnapEDA's own symbol for the part -- a second source
    # for the same table rather than a substitute for it:
    #
    #     pad  3     3V3          pad 45       EN
    #     pads 4-25  IO0-IO21     pads 1,2,30,42,43,46-55  GND1
    #     pad  26    IO26         pads 56-60,62,61_1-61_9  GND2
    #     pad  27    the module's own NC   pads 63-65       GND3
    #     pads 28,29 IO33,IO34
    #     pads 31-41 IO35-IO45    pad 44       IO46
    #
    # The thirteen used pins are **pinmap.md's allocation, not a fresh choice**:
    # IO15/IO16 UART1, IO33/IO34 I2C, IO35/36/37 I2S, IO38 panel INTN, IO21
    # interface INTN, IO19/IO20 USB D-/D+, and EN.  The other 26 GPIO are carried
    # and marked no-connect rather than omitted, so their pads are visibly unused
    # instead of silently floating -- and so ERC has 27 pins to *not* complain
    # about rather than 27 pin_not_connected errors.
    'U5': ic('ESP32-S2-MINI-2U', 'U',
             [('3', '3V3'), ('45', 'EN'),
              ('19', 'IO15'), ('20', 'IO16'),
              ('28', 'IO33'), ('29', 'IO34'),
              ('31', 'IO35'), ('32', 'IO36'), ('33', 'IO37'),
              ('34', 'IO38'), ('25', 'IO21'),
              ('23', 'IO19'), ('24', 'IO20'),
              ('1', 'GND')],
             U5_FREE + [('27', 'NC')],
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
    # J3 is the USB-C receptacle, and it is the one symbol here whose pin numbers
    # are the **real ones** rather than logical: A1-A12 and B1-B12 are the contacts
    # and SH1-SH6 the shield pads, exactly as Same Sky numbers them, because the
    # footprint has 30 pads and a net has to land on every one.  The ten contacts
    # this board does not use -- the eight SuperSpeed pairs and both SBU -- are
    # **carried and marked no-connect rather than omitted**: an omitted pin is a pad
    # with no net, which is how a USB-C footprint ends up half-wired, and the ERC
    # then has nothing to complain about.  Pin map from SnapEDA's
    # UJ32-C-H-G-DSMT-1-P24-TR.kicad_sym, which is the part's own symbol; the used
    # pins are on the left where the wires go, the unused on the right.
    'J3': ic('USB_C_SINK', 'J',
             [('A4', 'VBUS'), ('A9', 'VBUS'), ('B4', 'VBUS'), ('B9', 'VBUS'),
              ('A5', 'CC1'), ('B5', 'CC2'),
              ('A6', 'DP1'), ('B6', 'DP2'), ('A7', 'DN1'), ('B7', 'DN2'),
              ('A1', 'GND'), ('A12', 'GND'), ('B1', 'GND'), ('B12', 'GND'),
              ('SH1', 'SHIELD'), ('SH2', 'SHIELD'), ('SH3', 'SHIELD'),
              ('SH4', 'SHIELD'), ('SH5', 'SHIELD'), ('SH6', 'SHIELD')],
             [('A2', 'SSTXP1'), ('A3', 'SSTXN1'),
              ('A10', 'SSRXN2'), ('A11', 'SSRXP2'),
              ('B2', 'SSTXP2'), ('B3', 'SSTXN2'),
              ('B10', 'SSRXN1'), ('B11', 'SSRXP1'),
              ('A8', 'SBU1'), ('B8', 'SBU2')],
             w=25.4, pitch=2.54),
    'SW1': two_pin('SW_LATCH', 'SW', 12.7),
    'J2': two_pin('SPEAKER', 'J', 10.16),
    'R': two_pin('R', 'R', 7.62),
    'C': two_pin('C', 'C', 7.62),
    'L': two_pin('L', 'L', 7.62),
    'D': two_pin('D', 'D', 7.62),
    'LED': two_pin('LED', 'D', 7.62),
    'LEDR': two_pin('LED', 'D', 7.62),
    'F': two_pin('FUSE', 'F', 7.62),
    # ---- J4: the free GPIO, brought out so they are not trapped in the module --
    # U5 leaves 26 GPIO unused and they were marked no-connect, which is correct
    # but *terminal*: the pad is on the footprint, the header is not, and there is
    # no way to reach it without redoing the board.  A 2x13 header fixes that, and
    # 26 pins is exactly the 26 GPIO -- which is why it is 2x13 and not 2x14 with
    # grounds.  **It is left unpopulated**: it costs nothing to have the pads
    # there, and it means a later hobbyist can solder a header on and use the
    # radio, the DACs, the touch channels and the second SPI set without touching
    # U5's footprint.  Pins are numbered the way a 2x13 is -- odd on row 1, even
    # on row 2 -- and named with the module's own IO names, so pin 3 says IO1 and
    # a datasheet lookup is not needed.
    'J4': ic('EXP_GPIO_2X13', 'J',
             [(str(2 * i + 1), U5_FREE[i][1]) for i in range(13)],
             [(str(2 * i + 2), U5_FREE[13 + i][1]) for i in range(13)],
             w=25.4, pitch=2.54),
    # ---- J5: 5 V out, to the keyboard adapter -------------------------------
    # A keyed JST PH: fully shrouded with a polarising slot, so the plug cannot go
    # in the wrong way round and there is no reverse-voltage case to design for.
    'J5': two_pin('PWR_OUT_5V', 'J', 10.16),
    # ---- U11: the current limit on that 5 V out -----------------------------
    # TPS2553, a current-limited power-distribution switch.  It exists because
    # D13/D14 are SS14 -- **1 A each** -- so the 5 V rail cannot source more than
    # about an amp, and a "5 V out" port invites somebody to plug in a load that
    # wants three.  The limit is set by R28 on ILIM: I_OS = 25.6 / R_ILIM, so
    # 27 kohm gives about 0.95 A, under the diodes and 15x the adapter's ~60 mA.
    # EN is active LOW, so it is tied to GND to leave the switch on.  FAULT is
    # open-drain and unused here -- there is no MCU pin to spare for it, and the
    # part limits rather than latches, so nothing needs to know.
    'U11': ic('TPS2553', 'U',
              [(1, 'IN'), (3, '/EN'), (5, 'ILIM')],
              [(6, 'OUT'), (4, '/FAULT'), (2, 'GND')]),
    # ---- D15: the ESD clamp on the USB-C input power -------------------------
    # The port is meant for a computer and nothing else, but "meant for" is not a
    # protection.  VBUS arrives on J3, passes the polyfuse, and this clamps the
    # transient before it reaches the diode-OR.  Its own symbol key because the
    # footprint is different from the SS14s' -- SOD-323, not SMA.
    'TVS': two_pin('D_ESD', 'D', 7.62),
}

# 33 ground pads behind one visible pin -- see stack_onto.
stack_onto(SYMS['U5'], '1', U5_GND[1:], 'GND')

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
# U5, all 73 pads.  The numbers are the module's own (see the symbol above), so
# this reads as a pinout rather than as a list of indices -- and because the pin
# count and the pad count now agree, `Update PCB from Schematic` puts every net on
# the pad it actually belongs to.  It used to put +3V3 on pad 1, which is GND1.
NET_U5 = {
    '3': '+3V3', '45': 'ESP_EN',
    '19': 'UART1_TX', '20': 'O1_TXD_3V3',
    '28': 'I2C_SDA', '29': 'I2C_SCL',
    '31': 'I2S_BCLK', '32': 'I2S_LRCLK', '33': 'I2S_DIN',
    '34': 'INT_PANEL', '25': 'INT_IF',
    '23': 'USB_DM_ESP', '24': 'USB_DP_ESP',
}
for _p in U5_GND:
    NET_U5[_p] = 'GND'
# The free GPIO are **named, not no-connected**: each one goes to J4, so the pad,
# the net and the header pin all carry the module's own IO name.  Only pad 27 --
# which is not connected inside the module either -- stays NC.
for _pad, _name in U5_FREE:
    NET_U5[_pad] = _name
NET_U5['27'] = 'NC'
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
# J3, all 30 pins accounted for.  VBUS is all four VBUS contacts (A4/A9/B4/B9)
# because a sink draws on whichever pair the cable presents; GND is the four
# ground returns **plus all six shield pads**, since the shell is the ground path
# on a receptacle this small.  DP1/DP2 and DN1/DN2 are the two halves of the USB
# 2.0 pair and **both are wired** -- that is what makes the connector
# orientation-independent, and wiring only one half is the classic way to get a
# port that works with the cable upside down and not right way up.  CC1 and CC2
# go to 5k1 pulldowns (R15/R16), which is the sink's Rd.
#
# The ten unused contacts are 'NC' rather than absent, so each gets a no-connect
# marker on its pad.  Eight are the SuperSpeed pairs -- this is a USB 2.0 sink, so
# they are genuinely unused -- and two are SBU, which a plain sink does not need.
NET_J3 = {
    'A4': 'VBUS_IN', 'A9': 'VBUS_IN', 'B4': 'VBUS_IN', 'B9': 'VBUS_IN',
    'A5': 'USB_CC1', 'B5': 'USB_CC2',
    'A6': 'USB_DP_CON', 'B6': 'USB_DP_CON',
    'A7': 'USB_DM_CON', 'B7': 'USB_DM_CON',
    'A1': 'GND', 'A12': 'GND', 'B1': 'GND', 'B12': 'GND',
    'SH1': 'GND', 'SH2': 'GND', 'SH3': 'GND',
    'SH4': 'GND', 'SH5': 'GND', 'SH6': 'GND',
    'A2': 'NC', 'A3': 'NC', 'A10': 'NC', 'A11': 'NC',
    'B2': 'NC', 'B3': 'NC', 'B10': 'NC', 'B11': 'NC',
    'A8': 'NC', 'B8': 'NC',
}
NET_SW1 = {1: '+12V', 2: '+12V_SW'}
# J4 carries the 26 free GPIO.  The mapping is built the same way the symbol's is
# -- odd pins on row 1, even on row 2 -- because a header whose silk says IO1 on a
# pin that is really IO2 is worse than no header at all.
NET_J4 = {}
for _i in range(13):
    NET_J4[str(2 * _i + 1)] = U5_FREE[_i][1]
    NET_J4[str(2 * _i + 2)] = U5_FREE[13 + _i][1]

# U11, the current limit on the 5 V out.  IN comes off the diode-OR output, so
# whichever source is present feeds the port -- that is the whole point of putting
# it here rather than on one of the two inputs.  EN is active low, so it is tied
# to ground to leave the switch permanently on.  FAULT is unused: the part limits
# rather than latches, so there is nothing for an MCU to react to.
NET_U11 = {1: '+5V', 3: 'GND', 5: 'ILIM_5V', 6: '+5V_OUT', 4: 'NC', 2: 'GND'}
# J5 pin 1 is +5 V and pin 2 is ground.  The shroud makes that not a choice.
NET_J5 = {1: '+5V_OUT', 2: 'GND'}
# Pin 1 is the '+' terminal.  The datasheet gives the polarity: the cone moves
# forward with positive dc on '+'.  SPK_P is the amplifier's OUT+, so pin 1 takes
# SPK_P and the speaker pushes on a positive half-cycle rather than pulling.
NET_J2 = {1: 'SPK_P', 2: 'SPK_N'}

# --------------------------------------------------------------- placement
# Four sections, and a part goes in the one it belongs to **and next to what it
# connects to**.  The sheet is A1 (841 x 594 mm) and it is divided like this:
#
#     POWER    the machine rail and USB   x  30-830, y 400-580   (bottom band)
#     LOGIC    machine interface, level stage, modem, expanders
#                                         x  30-600, y  40-390
#     PANEL    the 11 lamps               x 600-830, y  40-330
#     AUDIO    amp and speaker            x 600-830, y 360-560
#
# The rule the sections exist to serve: a part sits near the pins it shares a net
# with, so the wire between them is short enough to follow.  That is what the
# "it is only notionally connected" complaint was about -- not the connection,
# the distance.
SECTIONS = [
    ('POWER', '12.6 V from P1 and 5 V from USB-C -- diode-OR, buck, LDO',
     30, 400),
    ('LOGIC', 'machine interface, level stage, ESP32, both expanders',
     30, 40),
    ('PANEL', 'the 11 lamps: 8 sourced by the panel expander, 3 sunk by it',
     600, 40),
    ('AUDIO', 'I2S class-D amp and the speaker', 600, 360),
]

PLACE = [
    # --- LOGIC: the machine connector and the level stage, left to right -------
    ('J1', 'J1', 'Conn_02x05 IDC (P1 MODEM)', 75, 120, NET_J1),
    ('U1', 'U1', '74LVC4T245 (TXD/MCB)', 180, 70, NET_U1),
    ('U3', 'U3', '74LVC1G07 (MSB)', 180, 145, NET_U3),
    ('U4', 'U4', 'MAX3232 (RXD)', 180, 235, NET_U4),
    ('U2', 'U2', '74LVC4T245 (CTS/RI)', 180, 355, NET_U2),
    # the modem, and its support parts immediately to its left
    ('U5', 'U5', 'ESP32-S2-MINI-2U', 370, 130, NET_U5),
    # the panel expander, at the PANEL boundary because that is what it drives
    ('U6', 'U6', 'AW9523B panel 0x58', 470, 130, NET_U6),
    # the interface expander, beside the level stage it talks to
    ('U7', 'U7', 'AW9523B interface 0x59', 320, 355, NET_U7),
    # --- PANEL: the lamps, in two columns, resistors inside -------------------
    # --- AUDIO ---------------------------------------------------------------
    ('U8', 'U8', 'MAX98357A', 680, 420, NET_U8),
    ('J2', 'J2', 'CMS-151103-088SP', 762, 420, NET_J2),
    # --- LOGIC: the free-GPIO breakout, beside the module whose GPIO they are --
    ('J4', 'J4', '2x13 header, GPIO breakout (DNP)', 490, 290, NET_J4),
    # --- POWER: 5 V out to the keyboard adapter, and the current limit on it ---
    ('U11', 'U11', 'TPS2553 current limit ~0.95A', 620, 530, NET_U11),
    ('J5', 'J5', '5V out to keyboard adapter', 760, 530, NET_J5),
    # --- POWER: the 12.6 V chain along the top of the band, USB below it ------
    ('SW1', 'SW1', 'Slide switch, latching', 400, 445, NET_SW1),
    ('U9', 'U9', 'TPS54331 buck 12.6->5', 470, 450, NET_U9),
    ('U10', 'U10', 'AP2112K-3.3 LDO', 770, 440, NET_U10),
    ('J3', 'J3', 'USB-C sink', 75, 498, NET_J3),
]

# two-terminal parts: (symbol type, ref, value, x, y, net1, net2)
TWO = [
    # --- POWER: the buck and everything hanging off it -----------------------
    ('C', 'C1', '220u', 400, 490, '+12V_SW', 'GND'),
    ('C', 'C2', '100n', 470, 490, 'BOOT_N', 'PH_N'),
    ('C', 'C3', '10n', 540, 490, 'SS_N', 'GND'),
    ('L', 'L1', '10uH', 600, 440, 'PH_N', '+5V_P1'),
    ('D', 'D12', 'SS34 catch', 600, 470, 'GND', 'PH_N'),
    ('R', 'R12', '10k', 660, 440, '+5V_P1', 'FB_N'),
    ('R', 'R13', '1k91', 700, 440, 'FB_N', 'GND'),
    ('C', 'C4', '1n', 660, 470, 'COMP_N', 'GND'),
    ('R', 'R14', '10k', 700, 470, 'COMP_N', 'GND'),
    ('C', 'C5', '22u', 740, 490, '+5V_P1', 'GND'),
    ('C', 'C7', '10u', 810, 440, '+3V3', 'GND'),
    # --- POWER: the current limit's set resistor, and the ESD clamp on VBUS ---
    # R28 sets U11's limit: I_OS = 25.6 / R_ILIM, so 27 kohm is about 0.95 A --
    # under the SS14 diodes' 1 A, and 15x what the keyboard adapter draws.
    ('R', 'R28', '27k', 660, 530, 'ILIM_5V', 'GND'),
    # D15 sits on VBUS_IN, upstream of the diode-OR, so the clamp is the first
    # thing a transient meets.  PESD5V0S1BA: 5 V standoff, so it does not conduct
    # on a 5.25 V VBUS, and it clamps low enough not to overstress the AP2112K.
    ('TVS', 'D15', 'PESD5V0S1BA ESD', 105, 440, 'VBUS_IN', 'GND'),
    # --- POWER: the diode-OR and the USB-C front end, below the rail ---------
    ('D', 'D13', 'SS14 OR', 290, 500, '+5V_P1', '+5V'),
    ('D', 'D14', 'SS14 OR', 290, 530, '+5V_USB', '+5V'),
    ('C', 'C6', '22u', 350, 515, '+5V', 'GND'),
    ('F', 'F1', 'polyfuse 1A', 145, 495, 'VBUS_IN', '+5V_USB'),
    ('R', 'R15', '5k1', 190, 490, 'USB_CC1', 'GND'),
    ('R', 'R16', '5k1', 190, 520, 'USB_CC2', 'GND'),
    ('R', 'R17', '22R', 240, 490, 'USB_DP_ESP', 'USB_DP_CON'),
    ('R', 'R18', '22R', 240, 520, 'USB_DM_ESP', 'USB_DM_CON'),
    # --- LOGIC: the MAX3232 charge pump, right beside U4 ---------------------
    ('C', 'C8', '100n', 255, 210, 'C1P', 'C1N'),
    ('C', 'C9', '100n', 255, 232, 'C2P', 'C2N'),
    ('C', 'C10', '100n', 255, 254, 'VP', 'GND'),
    ('C', 'C11', '100n', 255, 276, 'VN', 'GND'),
    ('C', 'C12', '100n', 255, 298, '+3V3', 'GND'),
    # --- LOGIC: ESP32 support, between U5 and the level stage ----------------
    ('R', 'R19', '10k', 300, 215, 'ESP_EN', '+3V3'),
    ('C', 'C13', '1u', 300, 237, 'ESP_EN', 'GND'),
    ('R', 'R20', '4k7', 300, 259, 'I2C_SDA', '+3V3'),
    ('R', 'R21', '4k7', 300, 281, 'I2C_SCL', '+3V3'),
    # --- LOGIC: expander support, beside the expander each one serves --------
    ('R', 'R22', '10k', 555, 100, 'INT_PANEL', '+3V3'),
    ('R', 'R23', '10k', 555, 130, 'INT_IF', '+3V3'),
    ('R', 'R24', '10k', 555, 160, 'EXP_RSTN', '+3V3'),
    ('C', 'C14', '100n', 555, 190, 'EXP_RSTN', 'GND'),
    ('R', 'R25', '10k', 390, 335, 'IF_CTS', '+3V3'),
    ('R', 'R26', '10k', 426, 335, 'IF_RI', '+3V3'),
    ('R', 'R27', '10k', 462, 335, 'IF_MSB', '+3V3'),
]

# lamps: source side (pin -> R -> LED -> GND) and sink side (3V3 -> LED -> R -> pin)
# Eleven rows in one block, resistors on the left, so the pair for each lamp reads
# as one line.  Rows 1-8 are the sourced lamps, 9-11 the sunk ones.
for _i, (_net, _pin) in enumerate(LED_SRC):
    _y = 60 + _i * 22
    TWO.append(('R', f'R{_i + 1}', '470R', 640, _y, _net, _net + '_A'))
    TWO.append(('LED', f'D{_i + 1}', '3528', 676, _y, _net + '_A', 'GND'))
for _i, (_net, _pin) in enumerate(LED_SINK):
    _y = 60 + (len(LED_SRC) + _i) * 22
    TWO.append(('LEDR', f'D{_i + 9}', '3528', 676, _y, '+3V3', _net + '_A'))
    TWO.append(('R', f'R{_i + 9}', '470R', 640, _y, _net + '_K', _net + '_A'))

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
    # J1 is a **right-angle shrouded IDC box header**, not a plain pin header: the
    # cable is keyed, and the key needs the shroud.  See the symbol above for the
    # pin-1-on-the-left derivation.
    'J1':  'Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal',
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
    # J2 is a **real speaker**, not a piezo buzzer: Same Sky CMS-151103-088SP,
    # 15 x 11 x 3 mm rectangular frame, 0.7 W (1.0 W max), 8 ohm, PEEK cone,
    # Nd-Fe-B magnet, solder-pad terminals.  Only the **8 ohm** is load-bearing --
    # it is what the MAX98357A wants.  The panel is a noise generator, not a hi-fi:
    # it runs in free air in an unsealed case with a perforated front panel, and
    # nothing here is designed around a response curve.  So the datasheet's Fo and
    # its SPL are deliberately not repeated anywhere as if they were the board's
    # specification -- they are 1 cc-box figures, and the box is not ours.
    # The part was chosen on 2026-10-21 (the piezo it replaces --
    # Multicomp Pro MCKPT-G1340-3917 -- is out; its footprint has been deleted).
    #
    # Why a speaker and not a buzzer: the panel has to make **the noise a modem
    # makes** -- dial tone, DTMF, ring cadence -- and a transducer that only knows
    # one note cannot.  The MAX98357A is an I2S class-D amplifier with its own DAC,
    # so the waveform is synthesised in firmware (#322) and the transducer only has
    # to be linear across 300-3400 Hz.  8 ohm is the load the amp wants.
    #
    # The footprint is ours, and its geometry is read off the datasheet's
    # mechanical drawing: 15 x 11 x 3 mm body, two **0.6 mm square** solder pads on
    # the left and right sides, and the pads **flush with the frame edge**.
    'J2':  'o1next:Speaker_SameSky_CMS-151103-088SP',
    # J3 is Same Sky UJ32-C-H-G-DSMT-1-P24-TR, and this one is the vendor's own
    # footprint from SnapEDA -- all 24 contacts (A1-A12, B1-B12) plus the six shield
    # pads.  It could not be assigned until the **symbol** had 30 pins to match, so
    # that every pad got a net; before the rebuild 17 of them would have been left
    # with none.  See the symbol above.
    'J3':  'o1next:USB_C_SameSky_UJ32-C-H-G-DSMT-1-P24-TR',
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
    # J4 is the free-GPIO breakout, **left unpopulated** -- see its symbol comment.
    # 2x13 because that is exactly the 26 GPIO, not 2x14 with grounds.
    'J4':  'Connector_PinHeader_2.54mm:PinHeader_2x13_P2.54mm_Vertical',
    # J5 is the 5 V out to the keyboard adapter.  JST PH, side entry, SMD: the
    # shroud and its polarising slot *are* the reverse-voltage protection, and
    # KiCad carries the footprint, so nothing is drawn here.
    'J5':  'Connector_JST:JST_PH_S2B-PH-SM4-TB_1x02-1MP_P2.00mm_Horizontal',
    # U11 is the current limit on that port.
    'U11': 'Package_TO_SOT_SMD:SOT-23-6',
    # D15 clamps ESD on the USB-C input power.  SOD-323, because it is a 5 V
    # transient suppressor and not a rectifier.
    'TVS': 'Diode_SMD:D_SOD-323',
}

# **Open, and deliberately not guessed.**  Each needs a part decision that
# changes the board, and a plausible-but-wrong footprint is a board that does not
# fit -- which is worse than a blank one, because a blank one is visibly undone.
# The generator prints this list on every run so it cannot be forgotten.
#
# **Empty as of 2026-10-21: J3 was the last entry.**  It waited on the symbol
# rebuild above, not on a part decision, and it is now assigned.  The dict stays
# because the mechanism is the point: a footprint that cannot be assigned yet is
# recorded here rather than silently left blank, and a schematic with an empty
# footprint transfers nothing to the PCB.
FOOTPRINT_OPEN = {}

# A third category, and a different failure: the part is decided and the footprint
# **is** assigned, but some dimension in it was placed rather than read, because
# the source gives it only as a figure.  That is not the same as FOOTPRINT_OPEN --
# the board is complete and opens -- but it is not finished either, so it is
# printed on every run beside it.
#
# **Empty as of 2026-10-21.**  J2 was the only entry: its pads were placed at
# 2.0 x 2.0 mm, 5.08 mm apart, because the speaker datasheet's mechanical drawing
# is a figure and does not extract as text.  The drawing was then read by eye and
# the values corrected (0.6 mm square, 14.4 mm apart), and the pad-to-edge offset
# -- the one remaining inference, taken as flush -- was confirmed.  So the
# category is empty and the mechanism stays.
FOOTPRINT_UNCONFIRMED = {}

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
           'J2', 'J3', 'J4', 'J5', 'U11', 'SW1', 'R', 'C', 'L', 'D', 'LED',
           'LEDR', 'F', 'TVS']:
    out.append(SYMS[_k].lib_sexpr())
for _n in sorted(POWER_NETS):
    out.append(PowerSym(_n).lib_sexpr())
out.append(FlagSym().lib_sexpr())
out.append('  )')

insts = []          # placed symbol sexprs
sinst = []          # (ref, value) for symbol_instances

# Parts that are on the schematic and on the board but deliberately **not fitted**.
# J4 is the free-GPIO breakout: the pads are there so a hobbyist can solder a
# header on later, and the board as shipped has none.  `dnp` is what tells KiCad
# that -- it keeps the part out of the BOM and off the placement file, which is
# the difference between "left unpopulated on purpose" and "we forgot to order it".
DNP = {'J4'}
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
    # **Do not populate.**  J4 is the free-GPIO breakout and is deliberately left
    # unfitted: the pads cost nothing and mean a later hobbyist can solder a header
    # on, but the board as shipped has no header there.  `dnp` is what says so to
    # KiCad -- it keeps the part out of the BOM and off the placement file, which
    # is the difference between "unpopulated" and "we forgot to order it".
    dnp = ref in DNP
    rects.append((x - s.w / 2 - 0.6, y - s.h / 2 - 0.6,
                  x + s.w / 2 + 0.6, y + s.h / 2 + 0.6))
    body = [
        f'  (symbol (lib_id "{s.lib_id}") (at {x} {y} 0) (unit 1)'
        f' (in_bom {"no" if dnp else "yes"}) (on_board yes)'
        f'{" (dnp yes)" if dnp else ""} (uuid "{uid()}")',
        f'    (property "Reference" "{ref}" (at {x} {y - s.h / 2 - 2.54} 0)'
        ' (effects (font (size 1.27 1.27))))',
        f'    (property "Value" "{value}" (at {x} {y - s.h / 2 - 5.08} 0)'
        ' (effects (font (size 1.27 1.27))))',
        f'    (property "Footprint" "{s.footprint}" (at 0 0 0)'
        ' (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
    ]
    for n, pname, side, off, _hide in s.pins:
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
        f' (in_bom yes) (on_board yes) (uuid "{uid()}")',
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
    seen = set()
    for (_ref, _pin, X, Y, side) in pinpts.get(net, []):
        # Stacked pins share one point on the sheet -- U5's 33 ground pads are one
        # visible pin with 32 hidden behind it -- so they are one connection and
        # want one symbol, not 33 on top of each other.
        if (X, Y) in seen:
            continue
        seen.add((X, Y))
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
            f' (in_bom yes) (on_board yes) (uuid "{uid()}")',
            f'    (property "Reference" "{ref}" (at {first[0]} {first[1] + 5.08} 0)'
            ' (effects (font (size 1.27 1.27)) (hide yes)))',
            f'    (property "Value" "PWR_FLAG" (at {first[0]} {first[1] - 5.08} 0)'
            ' (effects (font (size 1.27 1.27))))',
            '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
            '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
            '    (pin "1" (uuid "' + uid() + '"))',
            '  )',
        ]))

# signal nets: a **spanning tree**, not a star.  Each pin is joined to the nearest
# point already on the net, so branches share a trunk instead of every one of them
# running the whole way back to the first pin -- which is what produced overlapping
# collinear segments, and what KiCad then rewrote.
def _span(n):
    pts = pinpts[n]
    xs = [p[2] for p in pts]
    ys = [p[3] for p in pts]
    return (max(xs) - min(xs)) + (max(ys) - min(ys))


def _mh(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


for net in sorted(pinpts, key=_span, reverse=True):
    if net in POWER_NETS:
        continue
    pts = pinpts[net]
    tree = [(pts[0][2], pts[0][3])]
    for (_ref, _pin, X, Y, _side) in pts[1:]:
        near = min(tree, key=lambda c: _mh(c, (X, Y)))
        route(net, near, (X, Y))
        tree.append((X, Y))
    labels.append((net, pts[0][2], pts[0][3]))


# --------------------------------------------------------------- normalise wires
# Split every segment wherever any point of the same net lies on it, then drop the
# duplicates that leaves.  Two collinear wires that overlap become one wire; a pin
# that sat in the middle of a wire becomes a wire *end*, which is the only place
# KiCad connects a pin.  Then a junction wherever three or more wire ends meet.
#
# This is the fix for the defect that cost 14 pins and 10 nets: the old star
# router emitted 17 overlapping collinear pairs, KiCad normalised them on its
# first save, and the pins that had been attached only by sitting inside an
# overlap came adrift.  Doing the normalisation ourselves means KiCad has nothing
# left to rewrite.
def normalise(raw, net_pins):
    fixed = []
    by_net = defaultdict(list)
    for (net, a, b) in raw:
        by_net[net].append((a, b))
    for net, ss in by_net.items():
        marks = set()
        for (a, b) in ss:
            marks.add(a)
            marks.add(b)
        marks |= set(net_pins.get(net, ()))
        pieces = set()
        for (a, b) in ss:
            if a[0] == b[0]:                       # vertical
                lo, hi = sorted((a[1], b[1]))
                cuts = sorted({p[1] for p in marks
                               if p[0] == a[0] and lo <= p[1] <= hi})
                for i in range(len(cuts) - 1):
                    if cuts[i] != cuts[i + 1]:
                        pieces.add(((a[0], cuts[i]), (a[0], cuts[i + 1])))
            elif a[1] == b[1]:                     # horizontal
                lo, hi = sorted((a[0], b[0]))
                cuts = sorted({p[0] for p in marks
                               if p[1] == a[1] and lo <= p[0] <= hi})
                for i in range(len(cuts) - 1):
                    if cuts[i] != cuts[i + 1]:
                        pieces.add(((cuts[i], a[1]), (cuts[i + 1], a[1])))
        for p in sorted(pieces):
            fixed.append((net, p[0], p[1]))
    return fixed


def junction_points(normalised):
    ends = Counter()
    for (net, a, b) in normalised:
        ends[(net, a)] += 1
        ends[(net, b)] += 1
    return sorted((pt for (net, pt), c in ends.items() if c >= 3), key=lambda p: (p[1], p[0]))


NET_PINS = {net: [(X, Y) for (_r, _p, X, Y, _s) in pts]
            for net, pts in pinpts.items()}
segs = normalise(segs, NET_PINS)
juncs = junction_points(segs)

# every pin must be attached: a wire end, or a deliberate no-connect.  A pin that
# is neither is a part floating on the sheet, which is what "it just shows a label
# and isn't connected to anything" looks like from the other side.
_wire_ends = set()
for (_net, a, b) in segs:
    _wire_ends.add(a)
    _wire_ends.add(b)
_nc_pts = set(ncs)
_floating = []
for net, pts in pinpts.items():
    for (ref, pin, X, Y, _side) in pts:
        if (X, Y) not in _wire_ends and (X, Y) not in _nc_pts:
            _floating.append((ref, pin, X, Y))
_floating.sort()

for (net, a, b) in segs:
    insts.append(f'  (wire (pts (xy {a[0]} {a[1]}) (xy {b[0]} {b[1]}))'
                 f' (stroke (width 0) (type default)) (uuid "{uid()}"))')
for (x, y) in juncs:
    insts.append(f'  (junction (at {x} {y}) (diameter 0) (color 0 0 0 0)'
                 f' (uuid "{uid()}"))')
for (net, x, y) in labels:
    insts.append(f'  (label "{net}" (at {x} {y} 0)'
                 f' (effects (font (size 1.27 1.27)) (justify left bottom))'
                 f' (uuid "{uid()}"))')
for (x, y) in ncs:
    insts.append(f'  (no_connect (at {x} {y}) (uuid "{uid()}"))')
for (title, subtitle, sx, sy) in SECTIONS:
    insts.append(f'  (text "{title} -- {subtitle}" (at {sx} {sy - 12} 0)'
                 f' (effects (font (size 2.5 2.5) (thickness 0.4) bold) (justify left))'
                 f' (uuid "{uid()}"))')
for i, note in enumerate(NOTES):
    insts.append(f'  (text "{note}" (at 30 {545 + i * 6} 0)'
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

# --------------------------------------------------------------- write it out
# The generator writes into -generated/ and nowhere else.  -edited/ is a person's
# copy and is only ever seeded, never overwritten -- see the docstring.
GEN_DIR.mkdir(exist_ok=True)
EDIT_DIR.mkdir(exist_ok=True)
out_path = GEN_DIR / (BOARD + '.kicad_sch')
out_path.write_text('\n'.join(out) + '\n')

# The project-local footprint library lives one level up, beside the generator, so
# both directories need their own fp-lib-table pointing at it.  Without this the
# o1next: footprints stop resolving the moment the schematic moves into a
# subdirectory -- ${KIPRJMOD} becomes that subdirectory.
FP_TABLE = (
    '(fp_lib_table\n'
    '  (version 7)\n'
    '  (lib (name "o1next")(type "KiCad")(uri "${KIPRJMOD}/../footprints/o1next.pretty")'
    '(options "")(descr "Footprints this board needs that no library carries -- '
    'see the README beside them"))\n'
    ')\n'
)
for d in (GEN_DIR, EDIT_DIR):
    t = d / 'fp-lib-table'
    if not t.exists() or t.read_text() != FP_TABLE:
        t.write_text(FP_TABLE)
    # A project file, because ${KIPRJMOD} is the *project* directory: without one
    # KiCad cannot resolve ${KIPRJMOD}/../footprints and every o1next: footprint
    # comes back as a footprint_link_issue.  Written only if absent, so a fuller
    # file KiCad has saved over it is never clobbered.
    p = d / (BOARD + '.kicad_pro')
    if not p.exists():
        p.write_text('{\n  "board": { "design_settings": {}, "layers": [] }\n}\n')

seed = sorted(EDIT_DIR.glob('*.kicad_sch'))
if seed:
    print()
    print('ABORTED the copy into %s/ -- it already holds a schematic:' % BOARD + '-edited')
    for s in seed:
        print('    %s  (%d bytes, %s)' % (s.name, s.stat().st_size,
                                          datetime.datetime.fromtimestamp(
                                              s.stat().st_mtime).strftime('%Y-%m-%d %H:%M')))
    print('  Nothing was touched.  Empty that directory to re-seed from a fresh')
    print('  generation -- which discards what is in it, so know that first.')
else:
    shutil.copy2(out_path, EDIT_DIR / out_path.name)
    print()
    print('COPIED the generated schematic into %s/ (it was empty)' % (BOARD + '-edited'))
if fallbacks:
    print('WARNING', len(fallbacks), 'unroutable nets:', fallbacks)

if _floating:
    print()
    print('FLOATING -- %d pin(s) with no wire and no no-connect marker:' % len(_floating))
    for ref, pin, X, Y in _floating:
        print('  %-6s pin %-4s at (%s, %s)' % (ref, pin, X, Y))
    print('  Every pin must reach something.  A part that reaches nothing is the')
    print('  "it just shows a label" complaint, from the other side.')

# a wire KiCad would rewrite is a wire we drew wrong: overlapping collinear
# segments are exactly what its own cleaner removes, and the pins attached only
# through the overlap come adrift when it does.  Segments that merely *touch*
# end-to-end are fine -- that is what a split wire looks like -- so this counts
# strict overlap and duplicate only.
def _overlaps(ss):
    groups = defaultdict(list)
    for (_net, a, b) in ss:
        if a[0] == b[0]:
            groups[('V', a[0])].append(tuple(sorted((a[1], b[1]))))
        elif a[1] == b[1]:
            groups[('H', a[1])].append(tuple(sorted((a[0], b[0]))))
    strict = dupe = 0
    for iv in groups.values():
        iv.sort()
        for i in range(len(iv) - 1):
            if iv[i] == iv[i + 1]:
                dupe += 1
            elif iv[i][1] > iv[i + 1][0]:
                strict += 1
    return strict, dupe


_ov, _dup = _overlaps(segs)
print()
print('wires: %d segments, %d junctions, %d overlapping, %d duplicate '
      '(both must be 0)' % (len(segs), len(juncs), _ov, _dup))

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

print()
print('UNCONFIRMED -- footprint assigned, but a dimension in it was placed, not read:')
for _k in sorted(FOOTPRINT_UNCONFIRMED):
    print('  %-5s %s' % (_k, FOOTPRINT_UNCONFIRMED[_k]))

print()
print('wrote %s: %d wire segments, %d junctions, %d labels, %d no-connects, '
      '%d symbols, %d bodies'
      % (out_path.relative_to(HERE), len(segs), len(juncs), len(labels),
         len(ncs), len(sinst), len(rects)))
