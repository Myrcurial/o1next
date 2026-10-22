#!/usr/bin/env python3
"""Generate the floppy-adapter (switchable Gotek / physical-drive daughter card)
KiCad schematic for issue #62.

Regenerate: python3 gen_floppy_adapter_sch.py   (writes floppy-adapter.kicad_sch)
KiCad is not required to generate; open/re-save in KiCad 8+ to normalise.

Three things this file does that its first version did not.  All three are the
"mechanical" half of a schematic that survives KiCad -- the netlist was right
before, and the *drawing* was not:

1. **Every net is drawn as wires.**  The first version attached a net *label* to
   every pin and drew no wire between any two parts.  KiCad connected it; a
   reader saw a pile of disconnected stubs and had to trust the labels.  Now
   every signal net is routed as orthogonal segments on a 1.27 mm grid, and
   **exactly one label per net** survives, so the net *names* are still in the
   file.  One label and not fifteen is also the safety property: with a single
   label, a missing wire *breaks* the netlist instead of being hidden by a label
   doing the connecting.

2. **Every symbol carries a footprint** except K1 -- see FOOTPRINTS and
   FOOTPRINT_OPEN.  `Update PCB from Schematic` transfers **nothing** for a
   symbol whose Footprint field is empty, so a schematic without them cannot
   become a board at all, which is the one thing this board has to become.

3. **The rails are wired too, not stacked under a glyph per pin.**  GND lands on
   eleven pins of each 34-pin connector and +12 V on four consecutive ones; a
   power symbol per pin would put 3.81 mm glyphs 2.54 mm apart, on top of each
   other.  So GND/+5V/+12V are routed like any other net -- the comb of taps is
   what the ground topology actually looks like -- and each rail gets **one**
   power symbol, which is also what names the net.

The router is a deliberate copy of the one in
../wifi-comm-pac/gen_wifi_comm_pac_sch.py.  The copy is not an oversight:
`tools/check_schematics.py` regenerates each board's schematic by running its
generator **alone, in a scratch directory**, so a generator cannot import a
shared module -- there is nothing beside it to import.  Same algorithm, same
rules, same normalisation; the comments at the router say why each rule exists.

NOTE ON GEOMETRY: KiCad stores symbol pin coordinates with Y up, but the
sheet has Y down, so a placed symbol's pin lands at (x + px, y - py).  The
older generators added py instead, which silently netted pins to their
mirror-image partners; this script uses the correct `y - py` convention.
"""
import datetime
import heapq
import re
import uuid
from collections import Counter, defaultdict


def uid():
    return str(uuid.uuid4())


def snap(v):
    """KiCad wants wire and label ends on the 1.27 mm grid."""
    return round(round(v / 1.27) * 1.27, 3)


TODAY = str(datetime.date.today())

# The three rails.  They are routed like signals (see the header) and each gets
# one power symbol, which is what names the net -- so they carry no label.
RAIL_NETS = {'GND', '+5V', '+12V'}

# --------------------------------------------------------------- O1 floppy pinout
# 34-pin Shugart-like interface; +5V and +12V are carried on the cable (the O1
# has no separate drive power connectors).  Transcribed from the archived
# WayneVisser adapter (research/osborne1/floppy-adapter/FloppyAdapter.sch) and
# cross-checked against:
#   * O1 Field Service Manual 2F00040 - "The A drive has an 8 pin 150 OHM
#     Terminator resistor pack. B DRIVE DOES NOT."; logic-board 34-pin connector
#     P8 is a MALE header ("be careful not to bend any pins").
#   * O1 mainboard schematic 1A2011-00 Rev E, sheet 9 (DISC CONTROLLER), the
#     34-pin header P8: GND = 1,2,3,5,9,19,27,29,31,33; +12V = 11,13,15,17;
#     +5V = 21,23,25; pin 4 = TG43 and pin 6 = EARLY (both FDC-driven through
#     7406 open-collector buffers); pins 7 and 14 are not drawn on P8 at all.
#   * O1 disk-electronics schematic DWG 1A3004 sheet 1, connector P2 (the drive
#     end of the same cable): GND = 1,3,5,7,9,19,27,29,31,33, CASE = 32.
#     P2 and P8 disagree about pin 2 vs pin 7.  Neither is a driven signal on
#     the O1, so both are tied to GND here - correct whichever drawing is right.
#
# Pins 4 and 6 are NOT ground.  TG43 is the FDC's track>43 output, which on a
# 96 tpi drive is the write-current-reduce input: grounding it would assert
# reduced write current permanently.  Both pass straight through to J2.
O1 = {
    1: 'GND',   2: 'GND',   3: 'GND',   4: 'FLP_TG43', 5: 'GND', 6: 'FLP_EARLY',
    7: 'GND',   8: 'FLP_INDEX', 9: 'GND', 10: 'FLP_DS_A', 11: '+12V',
    12: 'FLP_DS_B', 13: '+12V', 14: 'NC', 15: '+12V', 16: 'FLP_4MHZ', 17: '+12V',
    18: 'FLP_DIR', 19: 'GND', 20: 'FLP_STEP', 21: '+5V', 22: 'FLP_WDATA',
    23: '+5V', 24: 'FLP_WGATE', 25: '+5V', 26: 'FLP_TRK0', 27: 'GND',
    28: 'FLP_WPROT', 29: 'GND', 30: 'FLP_RDATA', 31: 'GND', 32: 'FLP_SIDE',
    33: 'GND', 34: 'FLP_LATE',
}
O1_SHORT = {  # cosmetic pin names drawn inside the connector box
    1: 'GND', 2: 'GND', 3: 'GND', 4: 'TG43', 5: 'GND', 6: 'EARLY', 7: 'GND',
    8: 'INDEX', 9: 'GND', 10: 'DS_A', 11: '+12V', 12: 'DS_B', 13: '+12V',
    14: 'NC', 15: '+12V', 16: '4MHZ', 17: '+12V', 18: 'DIR', 19: 'GND',
    20: 'STEP', 21: '+5V', 22: 'WDATA', 23: '+5V', 24: 'WGATE', 25: '+5V',
    26: 'TRK0', 27: 'GND', 28: 'WPROT', 29: 'GND', 30: 'RDATA', 31: 'GND',
    32: 'SIDE', 33: 'GND', 34: 'LATE',
}
# Signals routed to the Gotek header J3 (Loxley's 11-line audit, on drive A):
GOTEK_SIG = {8, 18, 20, 22, 24, 26, 28, 30, 32, 34}


# --------------------------------------------------------------- symbols
class Symbol:
    """Minimal KiCad symbol builder (rectangle body, L/R pins)."""

    def __init__(self, name, ref_letter, w, h):
        self.name = name
        self.ref_letter = ref_letter
        self.w, self.h = w, h
        self.pins = []          # (number, name, side, offset_from_top)
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



# --------------------------------------------------------------- symbol builders
def make_conn(name, ref, side, names):
    """34-pin (2x17) connector; pins in numeric order, 1 at the top.

    *side* is which edge the pins are drawn on, and it is a routing decision as
    much as a drawing one: two connectors whose pins face each other are joined
    by straight wires, and a connector whose pins face away from its neighbour
    forces every net around its body.
    """
    s = Symbol(name, ref, 15.24, 96.52)
    for i in range(34):
        n = i + 1
        off = 5.08 + (33 - i) * 2.54          # pin 1 highest
        s.add(n, names.get(n, str(n)), side, off)
    return s


def make_bus_switch():
    """NC7SB3157P6X: single 2:1 analog/bus switch, SC70-6 (SOT-363).

    Pin numbers are the **part's own**, taken from Fairchild's datasheet and
    cross-checked against KiCad's symbol for the same part: 1 = B1, 2 = GND,
    3 = B0, 4 = A (the common), 5 = V+, 6 = S.  The truth table is what makes
    this the right switch for DS-A:

        S = low   ->  B0 connected to A
        S = high  ->  B1 connected to A

    So **B0 is the physical drive and B1 is the Gotek**: a low, floating or
    unplugged control parks the machine on the real drive, which is the same
    fail-safe the relay's NC contact gave.  The part also has
    **break-before-make** select circuitry, so the two devices are never both
    connected to DS-A even momentarily -- the property the relay gave for free.
    """
    s = Symbol('BUS_SW_2TO1', 'U', 25.4, 25.4)
    s.add(4, 'A_COM', 'L', 5.08)
    s.add(6, 'S', 'L', 12.70)
    s.add(2, 'GND', 'L', 20.32)
    s.add(3, 'B0_PHY', 'R', 5.08)
    s.add(1, 'B1_GOTEK', 'R', 10.16)
    s.add(5, 'V+', 'R', 20.32)
    return s


def make_load_switch():
    """TPS22918 DBV: 1 VIN, 2 GND, 3 ON, 4 CT, 5 QOD, 6 VOUT.

    Pin numbers are the part's own, and the pinout is the DBV-6 one KiCad's own
    library carries for TPS22917DBV -- the 80 mohm sibling in the same family,
    same package, same six functions.  52 mohm at 5 V, 2 A, and an N-channel
    switch with a charge pump, so the ON input is a logic pin rather than a gate
    to drive.

    **CT and QOD are deliberately left open.**  CT sets the rise time (open is
    fastest); QOD is the configurable quick-output-discharge *terminal*, and
    leaving it open disables it.  Neither is needed: what turns the Gotek off is
    the **GND** switch, not a discharge path, exactly as it was with the relay.
    If the bench shows the Gotek lingering, QOD is the pin to come back to.
    """
    s = Symbol('LOAD_SW', 'U', 25.4, 25.4)
    s.add(1, 'VIN', 'L', 5.08)
    s.add(3, 'ON', 'L', 12.70)
    s.add(2, 'GND', 'L', 20.32)
    s.add(6, 'VOUT', 'R', 5.08)
    s.add(5, 'QOD', 'R', 12.70)
    s.add(4, 'CT', 'R', 20.32)
    return s


def make_nfet():
    """AO3400A SOT-23: 1 = gate, 2 = source, 3 = drain (KiCad's Q_NMOS_GSD).

    28 mohm at Vgs = 4.5 V, so the Gotek's ground return sits 14 mV above the
    board's ground at half an amp.  That number is the reason this is a MOSFET
    and not a second PhotoMOS: an AQY212GS would put 0.7 ohm in the return path,
    which is 0.35 V of ground offset between the Gotek and the machine's TTL
    signals -- half the noise margin, on the read-data line.
    """
    s = Symbol('NFET_GSD', 'Q', 20.32, 15.24)
    s.add(1, 'G', 'L', 5.08)
    s.add(2, 'S', 'L', 12.70)
    s.add(3, 'D', 'R', 5.08)
    return s



def make_2pin(name, ref, n1, n2):
    """Horizontal two-terminal part: pin 1 left, pin 2 right."""
    s = Symbol(name, ref, 10.16, 5.08)
    s.add(1, n1, 'L', 2.54)
    s.add(2, n2, 'R', 2.54)
    return s


def make_hdr(name, ref, n, side='R'):
    s = Symbol(name, ref, 12.7, 5.08 + n * 2.54)
    for i in range(n):
        s.add(i + 1, str(i + 1), side, 5.08 + i * 2.54)
    return s


SYMS = {
    # J1 is the socket that mates the O1 logic-board P8 header; its pins face
    # right, into the corridor the pass-through runs down.
    'J1': make_conn('CONN_O1_SOCK', 'J', 'R', O1_SHORT),
    # J2 is the pass-through to the OEM cable: pins face *left*, back at J1, so
    # the 24 nets that only pass through are straight horizontal wires.
    'J2': make_conn('CONN_O1_HDR', 'J', 'L', O1_SHORT),
    # J3 is the Gotek signal header, below J2 with its pins facing left as well.
    'J3': make_conn('CONN_GOTEK_HDR', 'J', 'L',
                    {n: O1_SHORT[n] for n in GOTEK_SIG} | {10: 'DS_A'}),
    # The switching is three silicon parts now, not a relay: U1 picks which
    # device owns DS-A, U2 and Q1 switch the Gotek's two rails together.
    'U1': make_bus_switch(),
    'U2': make_load_switch(),
    'Q1': make_nfet(),
    'R': make_2pin('RES', 'R', '1', '2'),
    'LED': make_2pin('LED', 'D', 'A', 'K'),
    'J4': make_hdr('HDR_1x04', 'J', 4, 'L'),      # Gotek power, pins at U2/Q1
    'J5': make_hdr('HDR_1x02', 'J', 2, 'R'),      # panel switch, pins at R1/U1/U2
}

# --------------------------------------------------------------- net maps
# J1 = O1-side socket.  Every pin but DS-A (10) passes straight through to J2.
NET_J1 = dict(O1)

# J2 = pass-through header to the OEM cable (physical drives).  Only DS-A is
# intercepted: the relay common goes to J1.10, the NC contact returns to J2.10.
NET_J2 = dict(O1)
NET_J2[10] = 'FLP_DS_A_PHY'

# J3 = Gotek signal header.  DS-A arrives via the relay NO contact; +5V/GND do
# NOT appear here (they come only through J4, so switching GND actually works);
# every other pin is deliberately not connected.
NET_J3 = {}
for n in range(1, 35):
    if n == 10:
        NET_J3[n] = 'FLP_DS_A_GOTEK'
    elif n in GOTEK_SIG:
        NET_J3[n] = O1[n]
    else:
        NET_J3[n] = 'NC'

# U1 = the DS-A 2:1 switch (NC7SB3157P6X).  Its **common** is the machine's
# DS-A, its **B0** is the physical drive and its **B1** is the Gotek -- because
# the part's own truth table is "S low -> B0", so a low, floating or unplugged
# control is the fail-safe.  V+ is the board's +5 V and S is the control.
NET_U1 = {4: 'FLP_DS_A', 3: 'FLP_DS_A_PHY', 1: 'FLP_DS_A_GOTEK',
          6: 'CTRL', 5: '+5V', 2: 'GND'}

# U2 = the +5 V side of the Gotek's supply (TPS22918).  CT (rise time) and QOD
# (quick output discharge) are left open -- see the symbol.
NET_U2 = {1: '+5V', 3: 'CTRL', 2: 'GND', 6: '+5V_SW', 4: 'NC', 5: 'NC'}

# Q1 = the GND side (AO3400A).  Both rails are switched because switching only
# +5 V leaves the Gotek parasitically powered through the pulled-up signal
# lines, and switching only GND upsets the other drive (sec.4.2).
NET_Q1 = {1: 'CTRL', 2: 'GND', 3: 'GND_SW'}

NET = {
    'R1': {1: 'CTRL', 2: 'GND'},                  # 10k control pull-down
    'R2': {1: 'CTRL', 2: 'LED_A'},                # optional indicator dropper
    'D2': {1: 'LED_A', 2: 'GND'},                 # optional "Gotek active" LED
    'R3': {1: 'FLP_DS_A_GOTEK', 2: '+5V'},        # DS-A pull-up, 1k default
    'R4': {1: 'FLP_DS_A_GOTEK', 2: '+5V'},        # DS-A pull-up, 150R option (DNP)
    # R5 is the series resistor **in the switch lead**, and it is not optional
    # reasoning: that lead leaves the board and goes to the front panel, so it is
    # the one net here that can arrive carrying something the board never sent.
    # 1 k in series limits what a transient can push into three CMOS gates, and
    # the 630 pF gate of the FET turns in ~1 us through it -- irrelevant for a
    # switch a hand moves.  R1 still pulls the *control* side down, so the
    # fail-safe is unchanged: an unplugged lead is a low, and a low is the
    # physical drives.
    'R5': {1: 'SW_LEAD', 2: 'CTRL'},
    'J4': {1: '+5V_SW', 2: 'GND_SW', 3: 'GND_SW', 4: 'NC'},   # Gotek power
    # J5 is the panel switch: **UP = physical drives, DOWN = Gotek**.  The switch
    # is a plain SPST in series between the cable's +5 V and the control node, so
    # closed (down) is the Gotek and open (up) is the pull-down -- the physical
    # drives.  The connector is a **bare 2-pin 2.54 mm header** (DECIDED
    # 2026-10-22): the lead is a series SPST, so there is no polarity to key, and
    # a switch on a twisted pair of Dupont leads is trivial to implement.  The
    # shrouded JST PH alternative was considered and is recorded in the design
    # doc sec.4.5 rather than left open.
    'J5': {1: '+5V', 2: 'SW_LEAD'},
}

# --------------------------------------------------------------- placement
# x/y are on the 1.27 mm grid and the *layout is a routing decision*: J1 and J2
# face each other across the pass-through corridor, J3 sits below J2 with its
# pins on the same column, and K1 sits in the open space between the connectors
# and the small parts so the switched nets stay short.
PLACE = [  # (symbol type, ref, value, x, y, netmap)
    ('J1', 'J1', 'Conn_02x17 socket (O1 side)',    50.80,  76.20, NET_J1),
    ('J2', 'J2', 'Conn_02x17 header (OEM cable)', 198.12,  76.20, NET_J2),
    ('J3', 'J3', 'Conn_02x17 header (Gotek)',     198.12, 215.90, NET_J3),
    ('U1', 'U1', 'NC7SB3157P6X DS-A switch',       95.25, 203.20, NET_U1),
    ('U2', 'U2', 'TPS22918 +5V switch',            95.25, 241.30, NET_U2),
    ('Q1', 'Q1', 'AO3400A GND switch',            127.00, 254.00, NET_Q1),
    ('R',  'R1', '10k (CTRL pull-down)',           50.80, 223.52, NET['R1']),
    ('R',  'R5', '1k (lead series)',               50.80, 212.09, NET['R5']),
    ('R',  'R2', '1k (DNP)',                       50.80, 236.22, NET['R2']),
    ('LED','D2', 'LED (DNP)',                      68.58, 236.22, NET['D2']),
    ('R',  'R3', '1k',                            142.24, 203.20, NET['R3']),
    ('R',  'R4', '150R (DNP)',                    142.24, 213.36, NET['R4']),
    ('J5', 'J5', 'Panel switch',                   50.80, 203.20, NET['J5']),
    ('J4', 'J4', 'Gotek power',                   160.02, 236.22, NET['J4']),
]


# --------------------------------------------------------------- footprints
# **A schematic with no footprints cannot become a board.**  Every Footprint
# field was empty in the first revision of this file, on the theory that the
# assignment happens later, at annotation.  It does not: `Update PCB from
# Schematic` transfers *nothing* when the field is empty, so the board could not
# be started at all without hand-assigning every footprint in KiCad -- which is
# the hand transcription this generator exists to avoid.
#
# **Every name below was checked against KiCad's own libraries before it was
# written here** -- confirmed to exist as
# `<kicad>/footprints/<lib>.pretty/<name>.kicad_mod`, and confirmed to carry the
# pads this symbol's pin numbers need (34, 34, 34, 4, 2 and 2x2).  A footprint
# that does not exist is worse than an empty one, because it *looks* assigned.
#
# Through-hole throughout, and that is a decision rather than an omission: this
# is the project's first deliverable and the board a person builds by hand, so
# the parts are the parts somebody can solder.  It is also why the series parts
# are axial and the connectors are the plain vertical/right-angle ones.
FOOTPRINTS = {
    # J1 mates the logic board's P8 header, so it is a **socket** -- 2x17 pins,
    # 2.54 mm, vertical, and it has to be a socket rather than a header because
    # P8 is male (FSM 2F00040: "be careful not to bend any pins").
    'J1':  'Connector_PinSocket_2.54mm:PinSocket_2x17_P2.54mm_Vertical',
    # J2/J3 are headers the OEM cable and the Gotek pigtail push onto.
    'J2':  'Connector_IDC:IDC-Header_2x17_P2.54mm_Vertical',
    'J3':  'Connector_IDC:IDC-Header_2x17_P2.54mm_Vertical',
    # J4 is the switched Gotek power lead: right angle, because the lead leaves
    # the card the way the Gotek pigtail does.
    'J4':  'Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Horizontal',
    # J5 is the panel-switch lead: two pins, vertical, into a 2-way shell.
    'J5':  'Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical',
    # The three switches.  **These three are SMD and there is no through-hole
    # alternative**: the 5 V-capable analog/bus switches in DIP (CD4053, 74HC4053)
    # are 70-120 ohm, which in series with a 1 kohm pull-up puts the DS-A low
    # level at 0.7-0.9 V against a 0.8 V TTL threshold -- a part that "works" on
    # paper and fails on a machine.  Everything else on the card stays
    # through-hole.  Each footprint is the one KiCad's own symbol for the same
    # part carries.
    'U1':  'Package_TO_SOT_SMD:SOT-363_SC-70-6',
    'U2':  'Package_TO_SOT_SMD:SOT-23-6',
    'Q1':  'Package_TO_SOT_SMD:SOT-23',
    'LED': 'LED_THT:LED_D5.0mm',
    'R':   'Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal',
}

# **Empty, and that is the point of the entry.**  K1's footprint could not be
# assigned while the switch was an *undecided part*; the part is now decided
# (solid state, three parts, all three assigned above), so there is nothing
# waiting.  The mechanism stays: a footprint that cannot be assigned yet is
# recorded here rather than silently left blank, and the generator prints it.
FOOTPRINT_OPEN = {}

for _k, _s in SYMS.items():
    _s.footprint = FOOTPRINTS.get(_k, '')

ref_fp = {}          # ref -> footprint, for symbol_instances

NOTES = [
    'floppy-adapter: switchable Gotek / physical-drive daughter card (issue #62)',
    'J1 (female 2x17 socket) mates the O1 logic-board 34-pin MALE header (P8).',
    'J2 passes every pin but DS-A straight through to the OEM cable.',
    'PANEL SWITCH: UP = physical drives, DOWN = Gotek.  It ties the lead to',
    '+5V (down) or leaves it to R1 (up), so up is the fail-safe position.',
    'U1 = NC7SB3157P6X 2:1 switch: DS-A goes to B0 (physical) when S is LOW,',
    'and to B1 (Gotek) when S is HIGH.  Low/float/unplugged = physical drives.',
    'R5 = 1k in series with the switch lead: it leaves the board, so it gets one.',
    'R1 = 10k control pull-down, so a broken or unplugged switch lead is safe.',
    'U2 = TPS22918 switches the Gotek +5V; Q1 = AO3400A switches its GND.',
    'Both rails, always: +5V alone leaves the Gotek parasitically powered,',
    'GND alone upsets the other drive (design doc sec.4.2).  CT and QOD are open.',
    'Gotek +5V and GND reach it ONLY via J4, never through the J3 signal header.',
    'R3 = 1k DS-A pull-up on the Gotek side; R4 = 150R alternative (fit one).',
    'O1 150R terminator, and the Gotek has no pull-up on its select lines.',
    'Set the Gotek select jumper to the position that answers the O1 drive-A',
    'select (pin 10) - see docs/floppy-adapter-design.md sec. 8.',
    'Pins 4 (TG43) and 6 (EARLY) carry live FDC outputs: pass through, never GND.',
    'GND/+5V/+12V are wired like any other net, with one power symbol per rail.',
]

# Region titles, so the sheet says what each cluster is for.  **Short, and placed
# in clear space**: the four anchors below were each checked against the routed
# wires and the symbol bodies (a longer "PASS-THROUGH -- J1 -> J2, every pin but
# DS-A" has nowhere to sit near its cluster, because the lower half of the sheet
# is crossed by the J2 -> J3 bundle).  What each region *means* is in the notes.
SECTIONS = [
    ('PASS-THROUGH', 40.00, 20.00),
    ('GOTEK SIGNALS', 40.00, 130.00),
    ('SWITCHING', 40.00, 146.00),
    ('GOTEK POWER', 117.50, 146.00),
]



# --------------------------------------------------------------- emitter
out = [
    '(kicad_sch (version 20231120) (generator "o1next-gen")',
    f'  (uuid "{uid()}")',
    '  (paper "A3")',
    f'  (title_block (title "o1next floppy-adapter - switchable Gotek / physical drives") (date "{TODAY}") (rev "A")',
    '    (comment 1 "Issue #62. J1 2x17 socket on the O1 logic-board P8 header; J2 pass-through to the OEM cable; J3 Gotek signals; J4 switched Gotek power; J5 panel switch. DS-A, +5V and GND are switched by U1/U2/Q1, solid state: no relay, because the case has no height for one. Drive B is never switched."))',
    '  (lib_symbols',
]
for _k in ['J1', 'J2', 'J3', 'U1', 'U2', 'Q1', 'R', 'LED', 'J4', 'J5']:
    out.append(SYMS[_k].lib_sexpr())
for _n in sorted(RAIL_NETS):
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

# Parts that are on the schematic and on the board but deliberately **not
# fitted**: R4 is the 150 ohm alternative to the 1 kohm DS-A pull-up (fit one of
# R3/R4), and R2+D2 are the optional front-panel "Gotek active" indicator.  `dnp`
# is what says so to KiCad -- it keeps them out of the BOM and off the placement
# file, which is the difference between "left unfitted on purpose" and "we forgot
# to order it".  The pads stay, so either can be fitted later.
DNP = {'R2', 'D2', 'R4'}


def emit_symbol(key, ref, value, x, y, netmap):
    s = SYMS[key]
    x, y = snap(x), snap(y)
    sinst.append((ref, value))
    ref_fp[ref] = s.footprint
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


def emit_flag(ref, x, y):
    """PWR_FLAG: one per rail, so ERC knows the rail is driven."""
    sinst.append((ref, 'PWR_FLAG'))
    insts.append('\n'.join([
        f'  (symbol (lib_id "local:PWR_FLAG") (at {x} {y} 180) (unit 1)'
        f' (in_bom yes) (on_board yes) (uuid "{uid()}")',
        f'    (property "Reference" "{ref}" (at {x} {y + 5.08} 0)'
        ' (effects (font (size 1.27 1.27)) (hide yes)))',
        f'    (property "Value" "PWR_FLAG" (at {x} {y - 5.08} 0)'
        ' (effects (font (size 1.27 1.27))))',
        '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (pin "1" (uuid "' + uid() + '"))',
        '  )',
    ]))


for _key, _ref, _val, _x, _y, _net in PLACE:
    emit_symbol(_key, _ref, _val, _x, _y, _net)


# --------------------------------------------------------------- router
# A* on a 1.27 mm grid.  Symbols are blocked; another net's wire blocks travel
# *along* it (collinear overlap would short) but not across it (a crossing is
# unambiguous in KiCad: no junction, no connection).  Cells that hold another
# net's wire end are blocked outright, because an endpoint touching a wire is a
# junction.  Another component's **pin** is blocked too: a wire through a pin is
# a short no label reveals.
GRID = 1.27
XMAX = int(420 / GRID)          # the sheet is A3
YMAX = int(297 / GRID)


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
    """A wire must never pass through another component's pin.

    **Including the no-connect pins.**  They are not in ``pinpts`` -- they carry
    no net -- so they are easy to forget, and the first run of this router proved
    the cost: a wire ended on J3.14 and K1.11 and the netlist grew two pins on
    FLP_DS_A_GOTEK.  A no-connect marker is a statement that the pin goes
    *nowhere*; a wire through it says otherwise, and the netlist believes the
    wire.
    """
    if pin_own:
        return
    for n, pts in pinpts.items():
        for (_r, _p, x, y, _s) in pts:
            pin_own[cell((x, y))] = n
    for (x, y) in ncs:
        pin_own[cell((x, y))] = None     # None matches no net, so nothing may reach it


def astar(net, s, g, limit=3000000):
    """A* over (cell, heading), with turn cost so the route prefers long runs.

    Another net's wire is **impassable** rather than expensive: travelling *along*
    it would short the two nets, and ending *on* it would make a junction.  A
    crossing is allowed and is what the four-neighbour search gives for free --
    in KiCad a crossing is unambiguous, because neither net's wire ends there.

    (The copy this came from carried a `penalty()` for those cells that could
    never be reached, because the neighbour loop rejects them first.  Dead code
    with a docstring claiming a behaviour is worse than no code, so it is gone.)
    """
    DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))

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
    """Drop the points in the middle of a straight run."""
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
        # No legal route.  Fall back to an L, record it, and let the report and
        # the netlist check say so -- a silent wrong answer is worse.
        fallbacks.append((net, a, b))
        path = [s, (g[0], s[1]), g]
    else:
        path = simplify(path)
    pts = [a] + [pt(c) for c in path[1:-1]] + [b]
    for i in range(len(pts) - 1):
        if pts[i] != pts[i + 1]:
            mark(net, pts[i], pts[i + 1])
            segs.append((net, pts[i], pts[i + 1]))


# --------------------------------------------------------------- route every net
# A **spanning tree**, not a star.  Each pin is joined to the nearest point
# already on the net, so branches share a trunk instead of every one of them
# running the whole way back to the first pin -- which is what produced
# overlapping collinear segments, and what KiCad then rewrote.
def _span(n):
    pts = pinpts[n]
    xs = [p[2] for p in pts]
    ys = [p[3] for p in pts]
    return (max(xs) - min(xs)) + (max(ys) - min(ys))


def _mh(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


for net in sorted(pinpts, key=_span, reverse=True):
    pts = pinpts[net]
    tree = [(pts[0][2], pts[0][3])]
    for (_ref, _pin, X, Y, _side) in pts[1:]:
        near = min(tree, key=lambda c: _mh(c, (X, Y)))
        route(net, near, (X, Y))
        tree.append((X, Y))
    if net in RAIL_NETS:
        # One power symbol per rail, at the first pin, which is what names the
        # net -- so a rail carries no label.  The stub is **marked** as well as
        # emitted, so the router treats it as an obstacle: an unmarked stub is a
        # wire another net can be routed along, which is a short.
        _r, _p, X, Y, side = pts[0]
        dx = 5.08 if side == 'R' else -5.08
        fx = snap(X + dx)
        emit_power(net, fx, Y)
        mark(net, (X, Y), (fx, Y))
        segs.append((net, (X, Y), (fx, Y)))
        flag_no[0] += 1
        emit_flag(f'#FLG{flag_no[0]:02d}', fx, Y)
    else:
        labels.append((net, pts[0][2], pts[0][3]))


# --------------------------------------------------------------- normalise wires
# Split every segment wherever any point of the same net lies on it, then drop
# the duplicates that leaves.  Two collinear wires that overlap become one wire;
# a pin that sat in the middle of a wire becomes a wire *end*, which is the only
# place KiCad connects a pin.  Then a junction wherever three or more wire ends
# meet.
#
# This is the fix for the defect that cost wifi-comm-pac 14 pins and 10 nets: a
# star router emitted 17 overlapping collinear pairs, KiCad normalised them on
# its first save, and the pins that had been attached only by sitting inside an
# overlap came adrift.  Doing the normalisation ourselves means KiCad has nothing
# left to rewrite.  **A wire KiCad would rewrite is a wire drawn wrong.**
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
    return sorted((pt for (net, pt), c in ends.items() if c >= 3),
                  key=lambda p: (p[1], p[0]))


NET_PINS = {net: [(X, Y) for (_r, _p, X, Y, _s) in pts]
            for net, pts in pinpts.items()}
segs = normalise(segs, NET_PINS)
juncs = junction_points(segs)

# Every pin must be attached: a wire end, or a deliberate no-connect.  A pin that
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


# --------------------------------------------------------------- write it out
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
for (title, sx, sy) in SECTIONS:
    insts.append(f'  (text "{title}" (at {sx} {sy} 0)'
                 f' (effects (font (size 2.5 2.5) (thickness 0.4) bold)'
                 f' (justify left)) (uuid "{uid()}"))')
for i, note in enumerate(NOTES):
    insts.append(f'  (text "{note}" (at 232 {30 + i * 6} 0)'
                 f' (effects (font (size 1.6 1.6)) (justify left))'
                 f' (uuid "{uid()}"))')

out.extend(insts)
out.append('  (sheet_instances (path "/" (page "1")))')
si = '  (symbol_instances'
for ref, val in sinst:
    si += (f' (path "/" (reference "{ref}") (unit 1) (value "{val}")'
           f' (footprint "{ref_fp.get(ref, "")}"))')
si += ')'
out.append(si)
out.append(')')

with open('floppy-adapter.kicad_sch', 'w') as f:
    f.write('\n'.join(out) + '\n')


# --------------------------------------------------------------- report
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
comp = [ref for ref, _ in sinst if not ref.startswith('#')]
missing = [ref for ref in comp if not ref_fp.get(ref)]
print('wrote floppy-adapter.kicad_sch: %d nets, %d symbols, %d wire segments, '
      '%d junctions, %d labels, %d no-connects'
      % (len(pinpts), len(comp), len(segs), len(juncs), len(labels), len(ncs)))
print('wires: %d overlapping, %d duplicate (both must be 0)' % (_ov, _dup))
print('footprints: %d of %d component symbols have one; %d do not'
      % (len(comp) - len(missing), len(comp), len(missing)))
for _ref in sorted(FOOTPRINT_OPEN):
    print('  OPEN  %-4s %s' % (_ref, FOOTPRINT_OPEN[_ref]))
if fallbacks:
    print('WARNING %d unroutable net(s): %s' % (len(fallbacks), fallbacks))
if _floating:
    print('FLOATING -- %d pin(s) with no wire and no no-connect marker:' % len(_floating))
    for ref, pin, X, Y in _floating:
        print('  %-6s pin %-4s at (%s, %s)' % (ref, pin, X, Y))
    print('  Every pin must reach something.  A part that reaches nothing is the')
    print('  "it just shows a label" complaint, from the other side.')
