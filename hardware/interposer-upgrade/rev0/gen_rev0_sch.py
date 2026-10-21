#!/usr/bin/env python3
"""Generate the Rev 0 'test probe' KiCad 7 schematic.

Structural schematic for routing: Z80 pass-through (plug + socket),
4x 74AHCT165 PISO snapshot front end, Pico 2 W module, 5 V input, decoupling.
Buses are connected by net labels (standard practice), so re-mapping
GPIO assignments later is a label edit, not a re-route.

Regenerate: python3 gen_rev0_sch.py  (writes rev0.kicad_sch)
KiCad is not required to generate; open/re-save in KiCad 7+ to normalize.
"""
import uuid, datetime

def uid():
    return str(uuid.uuid4())

def prop(name, value, x, y, hide=False):
    fx = '(effects (font (size 1.27 1.27))' + (' (hide yes))' if hide else ')')
    return f'    (property "{name}" "{value}" (at {x} {y} 0) {fx})\n'

class Symbol:
    def __init__(self, lib, name, ref_letter, w, h):
        self.lib_id = f'{lib}:{name}'
        self.name = name
        self.ref_letter = ref_letter
        self.w, self.h = w, h
        self.pins = []  # (number, pinname, side, offset_from_top)
    def add(self, num, pname, side, off):
        self.pins.append((num, pname, side, off))
        return self
    def pin_pos(self, num):
        """symbol-local connection point, in KiCad symbol space (Y up).

        `off` counts down from the TOP of the box, so the symbol-space Y is
        `+hh - off` (top edge = +hh).  The sheet is Y-down, so a placed
        symbol's pin lands at `(x + px, y - py)` -- see place().
        """
        for n, p, side, off in self.pins:
            if n == num:
                hw, hh = self.w/2, self.h/2
                if side == 'L': return (-hw, hh - off)
                if side == 'R': return ( hw, hh - off)
                if side == 'T': return (-hw + off, hh)
                return (-hw + off, -hh)
        raise KeyError(num)
    def lib_sexpr(self):
        s = f'  (symbol "{self.lib_id}" (pin_names (offset 0.508)) (in_bom yes) (on_board yes)\n'
        s += prop('Reference', self.ref_letter, 0, -self.h/2 - 2.54)
        s += prop('Value', self.name, 0, -self.h/2 - 5.08)
        s += prop('Footprint', '', 0, 0, True)
        s += prop('Datasheet', '', 0, 0, True)
        hw, hh = self.w/2, self.h/2
        s += f'    (symbol "{self.name}_0_1"\n      (rectangle (start {-hw} {-hh}) (end {hw} {hh}) (stroke (width 0.254) (type default)) (fill (type background))))\n'
        s += f'    (symbol "{self.name}_1_1"\n'
        for n, p, side, off in self.pins:
            x, y = self.pin_pos(n)
            rot = {'L': 0, 'R': 180, 'T': 270, 'B': 90}[side]
            # anchor at box edge; pin body extends outward
            if side == 'L': ax, ay = x - 2.54, y
            elif side == 'R': ax, ay = x + 2.54, y
            elif side == 'T': ax, ay = x, y - 2.54
            else: ax, ay = x, y + 2.54
            s += (f'      (pin passive line (at {ax} {ay} {rot}) (length 2.54)'
                  f' (name "{p}" (effects (font (size 1.27 1.27))))'
                  f' (number "{n}" (effects (font (size 1.27 1.27)))))\n')
            # store absolute anchor for wiring: adjust pin_pos to anchor
        s += '    )\n  )\n'
        return s
    def anchor(self, num):
        """symbol-local connection point (pin outer end)."""
        for n, p, side, off in self.pins:
            if n == num:
                hw, hh = self.w/2, self.h/2
                if side == 'L': return (-hw - 2.54, hh - off)
                if side == 'R': return ( hw + 2.54, hh - off)
                if side == 'T': return (-hw + off, hh + 2.54)
                return (-hw + off, -hh - 2.54)
        raise KeyError(num)

# ---------- symbol definitions ----------
# ---------- Z80 pinout (single source of truth) ----------
# Standard Zilog Z80 / NEC uPD780C DIP-40: pins 1-20 run down the left side,
# 40-21 down the right.  Both the symbol geometry and the net names below are
# derived from this table -- hand-maintaining two copies is exactly how an
# off-by-one survived here (pin 11 is +5V and pin 29 is GND, not pin 12/30).
# tools/check_schematics.py now enforces the datasheet pinout.
Z80_LEFT = [
    (1,'A11'),(2,'A12'),(3,'A13'),(4,'A14'),(5,'A15'),(6,'CLK'),(7,'D4'),(8,'D3'),
    (9,'D5'),(10,'D6'),(11,'+5V'),(12,'D2'),(13,'D7'),(14,'D0'),(15,'D1'),(16,'/INT'),
    (17,'/NMI'),(18,'/HALT'),(19,'/MREQ'),(20,'/IORQ')]
Z80_RIGHT = [
    (40,'A10'),(39,'A9'),(38,'A8'),(37,'A7'),(36,'A6'),(35,'A5'),(34,'A4'),(33,'A3'),
    (32,'A2'),(31,'A1'),(30,'A0'),(29,'GND'),(28,'/RFSH'),(27,'/M1'),(26,'/RESET'),
    (25,'/BUSRQ'),(24,'/WAIT'),(23,'/BUSAK'),(22,'/WR'),(21,'/RD')]
Z80NET = dict(Z80_LEFT) | dict(Z80_RIGHT)


# ---------- symbol definitions ----------
def make_z80(name, ref):
    s = Symbol('local', name, ref, 25.4, 106.68)
    for i,(n,p) in enumerate(Z80_LEFT):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(Z80_RIGHT): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_165(name):
    # 74AHCT165 PISO: latch 8 bus lines at SH//LD strobe; PIO clocks out
    s = Symbol('local', name, 'U', 20.32, 45.72)
    left = [(1,'SH//LD'),(2,'CLK'),(15,'CLK_INH'),(11,'A'),(12,'B'),(13,'C'),(14,'D'),(3,'E'),(4,'F'),(5,'G'),(6,'H')]
    right = [(16,'VCC'),(10,'SER'),(9,'QH'),(7,'/QH'),(8,'GND')]
    for i,(n,p) in enumerate(left):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(right): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_pico():
    phys = [(1,'GP0'),(2,'GP1'),(3,'GND'),(4,'GP2'),(5,'GP3'),(6,'GP4'),(7,'GP5'),(8,'GND'),(9,'GP6'),(10,'GP7'),(11,'GP8'),(12,'GP9'),(13,'GND'),(14,'GP10'),(15,'GP11'),(16,'GP12'),(17,'GP13'),(18,'GND'),(19,'GP14'),(20,'GP15'),
            (21,'GP16'),(22,'GP17'),(23,'GND'),(24,'GP18'),(25,'GP19'),(26,'GP20'),(27,'GP21'),(28,'GND'),(29,'GP22'),(30,'RUN'),(31,'GP26'),(32,'GP27'),(33,'GND'),(34,'GP28'),(35,'ADC_VREF'),(36,'3V3_OUT'),(37,'3V3_EN'),(38,'GND'),(39,'VSYS'),(40,'VBUS')]
    s = Symbol('local', 'PICO2W', 'U', 25.4, 106.68)
    for i,(n,p) in enumerate(phys[:20]): s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(phys[20:]): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_cap():
    s = Symbol('local', 'CAP_100N', 'C', 10.16, 7.62)
    s.add(1,'1','L', 3.81); s.add(2,'2','R', 3.81)
    return s

def make_pwr():
    s = Symbol('local', 'PWR_5V_IN', 'J', 12.7, 7.62)
    s.add(1,'+5V','L', 3.81); s.add(2,'GND','R', 3.81)
    return s

# ---------- net assignment ----------
# Z80NET comes from Z80_LEFT/Z80_RIGHT at the top of this file.
# 74AHCT165 PISO chain: 4 chips x 8 inputs = 32 bus lines latched at the
# cycle strobe, then clocked into the Pico (~210ns for 32 bits via PIO).
BUF = [
    ('U1', ['A0','A1','A2','A3','A4','A5','A6','A7']),
    ('U2', ['A8','A9','A10','A11','A12','A13','A14','A15']),
    ('U3', ['D0','D1','D2','D3','D4','D5','D6','D7']),
    ('U4', ['/MREQ','/IORQ','/RD','/WR','/M1','/RFSH','/RESET','CLK']),
]
# chain: U1.SER<-GND-style start... SER of first = GND? no: U1 SER <- GND
# would shift zeros; standard: U1.QH->U2.SER, U2.QH->U3.SER, U3.QH->U4.SER,
# U4.QH->Pico SDAT. SH//LD and SCLK common to all.
# pico gp -> net (preliminary mapping; firmware owns final assignment)
PICO_NET = {'GP0':'SH//LD',   # PIO: latch strobe (all '165)
            'GP1':'SCLK',     # PIO: shift clock (all '165)
            'GP2':'SDAT',     # from U4.QH
            'GP3':'Z80_CLK',  # cycle timing reference
            'GP4':'STROBE',   # bus-cycle strobe (MREQ/IORQ glue)
            'GP5':'TRIG'}     # external trigger in

# ---------- emit ----------
syms = {'Z80': make_z80('Z80_DIP40','J'), '165': make_165('74AHCT165'),
        'PICO': make_pico(), 'CAP': make_cap(), 'PWR': make_pwr()}

out = []
out.append('(kicad_sch (version 20231120) (generator "o1next-gen")')
out.append(f'  (uuid "{uid()}")')
out.append('  (paper "A3")')
out.append(f'  (title_block (title "o1next interposer Rev 0 test probe") (date "{datetime.date.today()}") (rev "0.1") (comment 1 "Snoop-only Z80 bus probe: pass-through socket, 4x 74AHCT165 PISO snapshot front end, Pico 2 W. NOT the production interposer."))')
out.append('  (lib_symbols')
for s in syms.values(): out.append(s.lib_sexpr().rstrip('\n'))
out.append('  )')

wires, labels, ncs, insts, sinst = [], [], [], [], []

def place(symkey, ref, value, x, y, netmap):
    s = syms[symkey]
    # Snap the origin to the 1.27 mm connection grid.  Every derived pin and
    # stub endpoint inherits it, so ERC stops raising endpoint_off_grid (the
    # raw layout numbers below are only nominal).  Netlist is unaffected.
    x, y = round(round(x / 1.27) * 1.27, 2), round(round(y / 1.27) * 1.27, 2)
    sinst.append((ref, value))
    body = [f'  (symbol (lib_id "{s.lib_id}") (at {x} {y} 0) (unit 1) (in_bom yes) (on_board yes) (uuid "{uid()}")',
            f'    (property "Reference" "{ref}" (at {x} {y - s.h/2 - 2.54} 0) (effects (font (size 1.27 1.27))))',
            f'    (property "Value" "{value}" (at {x} {y - s.h/2 - 5.08} 0) (effects (font (size 1.27 1.27))))',
            '    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))',
            '    (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))']
    for n, p, side, off in s.pins:
        body.append(f'    (pin "{n}" (uuid "{uid()}"))')
        net = netmap.get(p) or netmap.get(n)
        if net:
            ax, ay = s.anchor(n)
            # symbol space is Y-up, the sheet is Y-down: subtract ay.  (Adding
            # it put every stub on the mirror-image pin, so nothing netted.)
            X, Y = x + ax, y - ay
            if net == 'NC':
                # 'NC' is a sentinel, not a net: labelling unused pins with it
                # ties them all together.  Flag them as no-connect instead.
                ncs.append((round(X, 2), round(Y, 2)))
                continue
            dx, dy = {'L':(-5.08,0),'R':(5.08,0),'T':(0,-5.08),'B':(0,5.08)}[side]
            wires.append((X, Y, X + dx, Y + dy))
            just = 'right' if side == 'L' else 'left'   # text away from the body
            labels.append((net, X + dx, Y + dy, 0, just))
    body.append('  )')
    insts.append('\n'.join(body))

# layout
place('Z80','J1','Z80_PLUG_TO_MB', 60, 90, Z80NET)
place('Z80','J2','Z80_SOCKET_CPU', 120, 90, Z80NET)
CHAIN = ['GND', 'QH1', 'QH2', 'QH3']        # SER sources: U1<-GND(pad), U2<-U1.QH, ...
QHNET = ['QH1', 'QH2', 'QH3', 'SDAT']       # QH nets; last feeds Pico GP2
for i,(ref, nets) in enumerate(BUF):
    nm = {abcd: nets[k] for k, abcd in enumerate(['A','B','C','D','E','F','G','H'])}
    nm.update({'SH//LD':'SH//LD','CLK':'SCLK','CLK_INH':'GND','GND':'GND',
               'VCC':'+5V','SER':CHAIN[i],'QH':QHNET[i]})
    place('165', ref, '74AHCT165', 190, 55 + i*60, nm)
pm = {gp: net for gp, net in PICO_NET.items()}
pm.update({'VSYS':'+5V','3V3_OUT':'+3V3','GND':'GND'})
place('PICO','U5','PICO_2_W', 280, 90, pm)
place('PWR','J3','5V_INPUT', 340, 60, {'+5V':'+5V','GND':'GND'})
for i in range(6):
    place('CAP', f'C{i+1}', '100nF', 340, 90 + i*15, {'1':'+5V','2':'GND'})

for (x1,y1,x2,y2) in wires:
    insts.append(f'  (wire (pts (xy {x1} {y1}) (xy {x2} {y2})) (stroke (width 0) (type default)) (uuid "{uid()}"))')
for (net,x,y,rot,just) in labels:
    insts.append(f'  (label "{net}" (at {round(x,2)} {round(y,2)} {rot}) (effects (font (size 1.27 1.27)) (justify {just} bottom)) (uuid "{uid()}"))')
for (x,y) in ncs:
    insts.append(f'  (no_connect (at {x} {y}) (uuid "{uid()}"))')

out.extend(insts)
out.append('  (sheet_instances (path "/" (page "1")))')
si = '  (symbol_instances'
for ref, val in sinst:
    si += f' (path "/" (reference "{ref}") (unit 1) (value "{val}") (footprint ""))'
si += ')'
out.append(si)
out.append(')')

with open('rev0.kicad_sch','w') as f:
    f.write('\n'.join(out) + '\n')
print('wrote rev0.kicad_sch:', len(wires), 'wires,', len(labels), 'labels,',
      len(ncs), 'no-connects,', len(sinst), 'symbols')
