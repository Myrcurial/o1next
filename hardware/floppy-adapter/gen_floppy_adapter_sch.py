#!/usr/bin/env python3
"""Generate the floppy-adapter (switchable Gotek / physical-drive daughter card)
KiCad 7 schematic for issue #62.

Structural schematic for routing, in the same spirit as
../interposer/reva/gen_reva_sch.py: symbols are placed and pins are tied to
nets by labels, so the pin/relay mapping can be edited without re-routing.

NOTE ON GEOMETRY: KiCad stores symbol pin coordinates with Y up, but the
sheet has Y down, so a placed symbol's pin lands at (x + px, y - py).  The
older generators added py instead, which silently netted pins to their
mirror-image partners; this script uses the correct `y - py` convention.

Regenerate: python3 gen_floppy_adapter_sch.py  (writes floppy-adapter.kicad_sch)
KiCad is not required to generate; open/re-save in KiCad 7+ to normalize.
"""
import uuid
import datetime

def uid():
    return str(uuid.uuid4())

TODAY = str(datetime.date.today())

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
        s += f'    (property "Reference" "{self.ref_letter}" (at 0 {-self.h/2 - 2.54} 0) (effects (font (size 1.27 1.27))))\n'
        s += f'    (property "Value" "{self.name}" (at 0 {-self.h/2 - 5.08} 0) (effects (font (size 1.27 1.27))))\n'
        s += '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        s += '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))\n'
        hw, hh = self.w / 2, self.h / 2
        s += f'    (symbol "{self.name}_0_1"\n'
        s += f'      (rectangle (start {-hw} {hh}) (end {hw} {-hh}) (stroke (width 0.254) (type default)) (fill (type background))))\n'
        s += f'    (symbol "{self.name}_1_1"\n'
        for n, p, side, off in self.pins:
            ax, ay = self.pin_sym(n)
            rot = 0 if side == 'L' else 180
            s += (f'      (pin passive line (at {ax} {ay} {rot}) (length 2.54)'
                  f' (name "{p}" (effects (font (size 1.27 1.27))))'
                  f' (number "{n}" (effects (font (size 1.27 1.27)))))\n')
        s += '    )\n  )'
        return s


# --------------------------------------------------------------- symbol builders
def make_conn(name, ref, side, names):
    """34-pin (2x17) connector; pins in numeric order, 1 at the top."""
    s = Symbol(name, ref, 15.24, 96.52)
    for i in range(34):
        n = i + 1
        off = 5.08 + (33 - i) * 2.54          # pin 1 highest
        s.add(n, names.get(n, str(n)), side, off)
    return s

def make_relay():
    """4PDT relay, coil on the left, four changeover poles on the right.

    Pin numbers are DIP-14 *logical placeholders* - confirm against the chosen
    4PDT relay's real terminal arrangement at footprint assignment (same
    convention as the interposer Rev A U1 note).  Mapping used here:
      1 = coil+ (A1), 14 = coil- (A2),
      pole1 2/3/4 = COM/NC/NO, pole2 5/6/7, pole3 8/9/10, pole4 11/12/13.
    """
    s = Symbol('RELAY_4PDT', 'K', 30.48, 45.72)
    s.add(1, 'COIL+', 'L', 15.24)
    s.add(14, 'COIL-', 'L', 25.40)
    base = 5.08
    for pole in range(4):
        top = base + pole * 10.16
        s.add(2 + pole * 3, f'P{pole+1}_COM', 'R', top)
        s.add(3 + pole * 3, f'P{pole+1}_NC', 'R', top + 2.54)
        s.add(4 + pole * 3, f'P{pole+1}_NO', 'R', top + 5.08)
    return s

def make_2pin(name, ref, n1, n2):
    s = Symbol(name, ref, 10.16, 5.08)
    s.add(1, n1, 'L', 2.54)
    s.add(2, n2, 'R', 2.54)
    return s

def make_hdr(name, ref, n):
    s = Symbol(name, ref, 12.7, 5.08 + n * 2.54)
    for i in range(n):
        s.add(i + 1, str(i + 1), 'R', 5.08 + i * 2.54)
    return s

SYMS = {
    'J1': make_conn('CONN_O1_SOCK', 'J', 'R', O1_SHORT),          # O1-side socket
    'J2': make_conn('CONN_O1_HDR', 'J', 'R', O1_SHORT),           # pass-through
    'J3': make_conn('CONN_GOTEK_HDR', 'J', 'R',
                    {n: O1_SHORT[n] for n in GOTEK_SIG} | {10: 'DS_A'}),
    'K1': make_relay(),
    'R': make_2pin('RES', 'R', '1', '2'),
    'D': make_2pin('DIODE', 'D', 'A', 'K'),
    'LED': make_2pin('LED', 'D', 'A', 'K'),
    'J4': make_hdr('HDR_1x04', 'J', 4),                            # Gotek power
    'J5': make_hdr('HDR_1x02', 'J', 2),                            # panel switch
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

# K1 relay: pole 1 switches +5V, pole 2 switches GND, pole 3 switches DS-A,
# pole 4 is spare.  De-energised (panel switch open / lead unplugged) = the NC
# contacts, i.e. the physical drives (fail-safe).
NET_K1 = {
    1: 'COIL_PLUS', 14: 'GND',
    2: '+5V',        3: 'NC',  4: '+5V_SW',       # pole 1: +5V -> Gotek
    5: 'GND',        6: 'NC',  7: 'GND_SW',       # pole 2: GND -> Gotek
    8: 'FLP_DS_A',   9: 'FLP_DS_A_PHY', 10: 'FLP_DS_A_GOTEK',  # pole 3: DS-A
    11: 'NC',        12: 'NC', 13: 'NC',          # pole 4: spare
}

NET = {
    'D1': {1: 'GND', 2: 'COIL_PLUS'},             # flyback, cathode to coil+
    'R1': {1: 'COIL_PLUS', 2: 'GND'},             # 10k coil-node pull-down
    'R2': {1: 'COIL_PLUS', 2: 'LED_A'},           # optional indicator dropper
    'D2': {1: 'LED_A', 2: 'GND'},                 # optional "Gotek active" LED
    'R3': {1: 'FLP_DS_A_GOTEK', 2: '+5V'},        # DS-A pull-up, 1k default
    'R4': {1: 'FLP_DS_A_GOTEK', 2: '+5V'},        # DS-A pull-up, 150R option (DNP)
    'J4': {1: '+5V_SW', 2: 'GND_SW', 3: 'GND_SW', 4: 'NC'},   # Gotek power
    'J5': {1: '+5V', 2: 'COIL_PLUS'},             # panel switch -> relay coil
}

# --------------------------------------------------------------- placement
PLACE = [  # (symbol type, ref, value, x, y, netmap); x/y on the 1.27 mm grid
    ('J1', 'J1', 'Conn_02x17 socket (O1 side)',    55.88,  78.74, NET_J1),
    ('J2', 'J2', 'Conn_02x17 header (OEM cable)', 165.10,  78.74, NET_J2),
    ('J3', 'J3', 'Conn_02x17 header (Gotek)',     274.32,  78.74, NET_J3),
    ('K1', 'K1', '4PDT relay, 5V coil',           110.49, 210.82, NET_K1),
    ('D',  'D1', '1N4148',                         50.80, 180.34, NET['D1']),
    ('R',  'R1', '10k',                            50.80, 195.58, NET['R1']),
    ('R',  'R2', '1k (DNP)',                       50.80, 210.82, NET['R2']),
    ('LED','D2', 'LED (DNP)',                      50.80, 226.06, NET['D2']),
    ('R',  'R3', '1k',                             50.80, 245.11, NET['R3']),
    ('R',  'R4', '150R (DNP)',                     50.80, 260.35, NET['R4']),
    ('J5', 'J5', 'Panel switch',                  210.82, 175.26, NET['J5']),
    ('J4', 'J4', 'Gotek power',                   210.82, 245.11, NET['J4']),
]

NOTES = [
    'floppy-adapter: switchable Gotek / physical-drive daughter card (issue #62)',
    'J1 (female 2x17 socket) mates the O1 logic-board 34-pin MALE header (P8).',
    'J2 passes every pin but DS-A straight through to the OEM cable.',
    'K1 4PDT: pole1 = +5V, pole2 = GND, pole3 = DS-A (NC=physical, NO=Gotek).',
    'De-energised = physical drives (fail-safe).  J5 carries coil current only.',
    'Gotek +5V and GND reach it ONLY via J4, never through the J3 signal header.',
    'R3 = 1k DS-A pull-up on the Gotek side; R4 = 150R alternative (fit one).',
    'O1 150R terminator, and the Gotek has no pull-up on its select lines.',
    'Set the Gotek select jumper to the position that answers the O1 drive-A',
    'select (pin 10) - see docs/floppy-adapter-design.md sec. 8.',
]


# --------------------------------------------------------------- emit
out = [
    '(kicad_sch (version 20230121) (generator "eeschema") (generator_version "7.0")',
    f'  (uuid "{uid()}")',
    '  (paper "A3")',
    f'  (title_block (title "o1next floppy-adapter - switchable Gotek / physical drives") (date "{TODAY}") (rev "A")',
    '    (comment 1 "Issue #62. J1 2x17 socket on the O1 logic-board P8 header; J2 pass-through to the OEM cable; J3 Gotek signals; J4 switched Gotek power; J5 panel switch; K1 4PDT relay. Drive B is never switched."))',
    '  (lib_symbols',
]
for _k in ['J1', 'J2', 'J3', 'K1', 'R', 'D', 'LED', 'J4', 'J5']:
    out.append(SYMS[_k].lib_sexpr())
out.append('  )')

wires, labels, ncs, insts, sinst = [], [], [], [], []

def place(key, ref, value, x, y, netmap):
    s = SYMS[key]
    sinst.append((ref, value))
    body = [
        f'  (symbol (lib_id "{s.lib_id}") (at {x} {y} 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (uuid "{uid()}")',
        f'    (property "Reference" "{ref}" (at {x} {y - s.h/2 - 2.54} 0) (effects (font (size 1.27 1.27))))',
        f'    (property "Value" "{value}" (at {x} {y - s.h/2 - 5.08} 0) (effects (font (size 1.27 1.27))))',
        '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
        '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
    ]
    for n, pname, side, off in s.pins:
        body.append(f'    (pin "{n}" (uuid "{uid()}"))')
        sx, sy = s.pin_sym(n)
        X, Y = x + sx, y - sy            # symbol Y-up -> sheet Y-down (correct)
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

for (x1, y1, x2, y2) in wires:
    insts.append(f'  (wire (pts (xy {x1} {y1}) (xy {x2} {y2})) (stroke (width 0) (type default)) (uuid "{uid()}"))')
for (net, x, y, just) in labels:
    insts.append(f'  (label "{net}" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (justify {just} bottom)) (uuid "{uid()}"))')
for (x, y) in ncs:
    insts.append(f'  (no_connect (at {x} {y}) (uuid "{uid()}"))')
for i, note in enumerate(NOTES):
    insts.append(f'  (text "{note}" (at 320 {160 + i * 6} 0) (effects (font (size 1.6 1.6))) (uuid "{uid()}"))')

out.extend(insts)
out.append('  (sheet_instances (path "/" (page "1")))')
si = '  (symbol_instances'
for ref, val in sinst:
    si += f' (path "/" (reference "{ref}") (unit 1) (value "{val}") (footprint ""))'
si += ')'
out.append(si)
out.append(')')

with open('floppy-adapter.kicad_sch', 'w') as f:
    f.write('\n'.join(out) + '\n')
print('wrote floppy-adapter.kicad_sch:',
      len(wires), 'wires,', len(labels), 'labels,',
      len(ncs), 'no-connects,', len(sinst), 'symbols')
