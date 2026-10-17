#!/usr/bin/env python3
"""Generate the interposer Rev A (engineering sample) KiCad 7 schematic.

Structural schematic for routing: Z80 pass-through (plug J1 + on-board SMT
Z84C00 U1), 74AHCT595/245 bus drive, 74AHCT165 capture chain, 74AHCT244/125
control drive, RP2354B + ESP32-C3 + SPI flash, 3V3 LDO.
Buses are connected by net labels (standard practice), so re-mapping
GPIO assignments later is a label edit, not a re-route.

Regenerate: python3 gen_reva_sch.py  (writes reva.kicad_sch)
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

def make_245(name):
    s = Symbol('local', name, 'U', 20.32, 55.88)
    left = [(1,'DIR'),(2,'A1'),(3,'A2'),(4,'A3'),(5,'A4'),(6,'A5'),(7,'A6'),(8,'A7'),(9,'A8'),(10,'GND')]
    right = [(20,'VCC'),(19,'/OE'),(18,'B1'),(17,'B2'),(16,'B3'),(15,'B4'),(14,'B5'),(13,'B6'),(12,'B7'),(11,'B8')]
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

# Rev A ES bus interface: bus mastering stops the Z84C00 (/BUSRQ//BUSAK),
# so all drive/capture can go through slow-tolerant serial registers.
# Drive: 3x 74AHCT595 (A0-15 + CTL0-7) + 1x 74AHCT245 (data, fast /OE)
# Capture: 3x 74AHCT165 (A0-15 echo, D0-7 in, CTL-in)
SR_OUT = [  # (ref, [QA..QH nets])
    ('U3', ['A0','A1','A2','A3','A4','A5','A6','A7']),
    ('U4', ['A8','A9','A10','A11','A12','A13','A14','A15']),
    ('U5', ['/MREQ_DRV','/IORQ_DRV','/RD_DRV','/WR_DRV','/M1_DRV','/RFSH_DRV','NC','NC']),
    ('U15', ['D_/RESET','D_/INT','D_/NMI','D_/WAIT','D_/BUSRQ','NC','NC','NC']),
]
SR_IN = [   # (ref, [A..H nets])
    ('U6', ['A0','A1','A2','A3','A4','A5','A6','A7']),
    ('U7', ['A8','A9','A10','A11','A12','A13','A14','A15']),
    ('U8', ['D0','D1','D2','D3','D4','D5','D6','D7']),
]
# data drive: U9 74AHCT245, A-side driven directly from Pico GP8-15
# (writes are slow by definition while bus-mastering; only the bus-side
# transceiver needs to be fast), /OE = /OE_DATA, DIR = A->B fixed.

PICO_NET = {
    'GP0':'SR_SCK',     # shift clock: 595 SCK + 165 CLK
    'GP1':'SR_MOSI',    # -> U3.SER (595 chain)
    'GP2':'SR_MISO',    # <- U8.QH (165 chain end)
    'GP3':'SR_RCK',     # 595 output latch
    'GP4':'SR_LOAD',    # 165 SH//LD
    'GP5':'/OE_DATA',   # U9 245 output enable (data drive onto bus)
    'GP6':'/OE_ADDR',   # 595 /G commons (address+control+data drive)
    'GP7':'/OE_SYSCTL', # U11 125: /RESET /INT /NMI /WAIT /BUSRQ drive
    'GP8':'PD0','GP9':'PD1','GP10':'PD2','GP11':'PD3',   # U9 A-side (data to drive)
    'GP12':'PD4','GP13':'PD5','GP14':'PD6','GP15':'PD7',
    'GP16':'ESP_TXD',   # RP2354B UART0 TX -> ESP32 RX
    'GP17':'ESP_RXD',   # RP2354B UART0 RX <- ESP32 TX
    'GP18':'FLASH_SCK','GP19':'FLASH_MOSI','GP20':'FLASH_MISO','GP21':'/CS_FLASH',
    'GP22':'/MREQ_RAW', # raw bus lines for PIO strobe/trigger
    'GP26':'/IORQ_RAW','GP27':'Z80_CLK','GP28':'/BUSAK'}

# ctl drive via U11 74AHCT125 (OE common /OE_SYSCTL): RESET/INT/NMI/WAIT/BUSRQ
CTL125 = ['/RESET','/INT','/NMI','/WAIT','/BUSRQ']

# ---------- additional symbols ----------
def make_595():
    s = Symbol('local', '74AHCT595', 'U', 20.32, 45.72)
    left = [(14,'SER'),(11,'SCK'),(12,'RCK'),(13,'/G'),(10,'/SCLR'),(16,'VCC'),(8,'GND')]
    right = [(15,'QA'),(1,'QB'),(2,'QC'),(3,'QD'),(4,'QE'),(5,'QF'),(6,'QG'),(7,'QH'),(9,'QH_')]
    for i,(n,p) in enumerate(left):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(right): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_244():
    s = Symbol('local', '74AHCT244', 'U', 20.32, 45.72)
    left = [(1,'/1OE'),(2,'1A1'),(4,'1A2'),(6,'1A3'),(8,'1A4'),(11,'2A1'),(13,'2A2'),(10,'GND')]
    right = [(20,'VCC'),(19,'/2OE'),(18,'1Y1'),(16,'1Y2'),(14,'1Y3'),(12,'1Y4'),(9,'2Y1'),(7,'2Y2')]
    for i,(n,p) in enumerate(left):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(right): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_125():
    s = Symbol('local', '74AHCT125', 'U', 20.32, 35.56)
    left = [(1,'/1G'),(2,'1A'),(4,'/2G'),(5,'2A'),(10,'/3G'),(9,'3A'),(13,'/4G'),(12,'4A')]
    right = [(14,'VCC'),(3,'1Y'),(6,'2Y'),(8,'3Y'),(11,'4Y'),(7,'GND')]
    for i,(n,p) in enumerate(left):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(right): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_z84():
    # PLCC/QFP-44 SMT Z84C00. Pins 1-40 carry the DIP-40 signals in the same
    # logical order (Z80_LEFT/Z80_RIGHT above); 41-44 are NC. PIN NUMBERS ARE
    # PLACEHOLDERS: assign the correct QFP-44 PEG footprint mapping in KiCad
    # before routing. See README 'known placeholder'.
    s = Symbol('local', 'Z84C00_SMT44', 'U', 25.4, 111.76)   # h/2 = 55.88 = 44 x 1.27
    z = Z80_LEFT + [(21,'/RD'),(22,'/WR')]
    r = [(44,'NC'),(43,'NC'),(42,'NC'),(41,'NC')] + [p for p in Z80_RIGHT if p[0] >= 23]
    for i,(n,p) in enumerate(z): s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(r): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_esp32c3():
    s = Symbol('local', 'ESP32C3_MOD', 'U', 20.32, 45.72)
    left = [(1,'3V3'),(2,'EN'),(3,'IO9_BOOT'),(4,'RXD0'),(5,'TXD0')]
    right = [(10,'GND'),(9,'IO8'),(8,'IO2'),(7,'IO10')]
    for i,(n,p) in enumerate(left):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(right): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_flash():
    s = Symbol('local', 'W25Q_FLASH', 'U', 15.24, 20.32)
    left = [(1,'/CS'),(2,'DO_MISO'),(3,'/WP'),(4,'GND')]
    right = [(8,'VCC'),(7,'/HOLD'),(6,'CLK'),(5,'DI_MOSI')]
    for i,(n,p) in enumerate(left):  s.add(n,p,'L', 5.08 + i*5.08)
    for i,(n,p) in enumerate(right): s.add(n,p,'R', 5.08 + i*5.08)
    return s

def make_ldo():
    s = Symbol('local', 'LDO_3V3', 'U', 12.7, 12.7)
    s.add(1,'GND','L', 5.08); s.add(2,'VIN','L', 10.16)
    s.add(3,'VOUT','R', 6.35)
    return s

# ---------- emit ----------
syms = {'Z80': make_z80('Z80_DIP40','J'), 'Z84': make_z84(), '165': make_165('74AHCT165'), '245': make_245('74AHCT245'),
        '595': make_595(), '244': make_244(), 'PICO': make_pico(), 'ESP': make_esp32c3(),
        'FLASH': make_flash(), 'LDO': make_ldo(), 'CAP': make_cap(), 'PWR': make_pwr()}

out = ['(kicad_sch (version 20230121) (generator "eeschema") (generator_version "7.0")',
       f'  (uuid "{uid()}")', '  (paper "A2")',
       f'  (title_block (title "o1next interposer Rev A engineering sample") (date "{datetime.date.today()}") (rev "A-ES")',
       '    (comment 1 "Active interposer: bus mastering via /BUSRQ, SR-based drive+capture, SMT Z84C00, RP2354B + ESP32-C3. Engineering sample - 2 off."))',
       '  (lib_symbols']
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
    body = [f'  (symbol (lib_id "{s.lib_id}") (at {x} {y} 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (uuid "{uid()}")',
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
                # ties them all together (on U15 that joined four unused 595
                # totem-pole outputs).  Flag them as no-connect instead.
                ncs.append((round(X, 2), round(Y, 2)))
                continue
            dx, dy = {'L':(-5.08,0),'R':(5.08,0),'T':(0,-5.08),'B':(0,5.08)}[side]
            wires.append((X, Y, X + dx, Y + dy))
            just = 'right' if side == 'L' else 'left'   # text away from the body
            labels.append((net, X + dx, Y + dy, 0, just))
    body.append('  )')
    insts.append('\n'.join(body))

# J1: plug to motherboard Z80 socket. U1: on-board SMT Z84C00 (same nets).
place('Z80','J1','Z80_PLUG_TO_MB', 60, 110, Z80NET)
z84net = dict(Z80NET)
z84net.update({'NC': 'NC'})   # pins 41-44 are genuinely unconnected
place('Z84','U1','Z84C00_SMT44', 115, 112, z84net)

# 595 drive chain: U3.SER<-SR_MOSI; QH_->next SER; all SCK/RCK common
ser595 = ['SR_MOSI','QH_U3','QH_U4','QH_U5']
for i,(ref, nets) in enumerate(SR_OUT):
    nm = {q: nets[k] for k, q in enumerate(['QA','QB','QC','QD','QE','QF','QG','QH'])}
    nm.update({'SER':ser595[i],'SCK':'SR_SCK','RCK':'SR_RCK','/G':'/OE_ADDR','/SCLR':'+5V',
               'VCC':'+5V','GND':'GND','QH_': ser595[i+1] if i < 3 else 'NC'})
    place('595', ref, '74AHCT595', 175, 40 + i*55, nm)

# 165 capture chain: U6.SER<-GND; QH->next SER; U8.QH->SR_MISO
# NB: the 595 chain is FOUR devices (U3/U4/U5/U15 -- see SR_OUT), so the
# capture chain starts one slot lower.  At y=205 the first '165 sat exactly on
# top of U15 and shorted SR_RCK/GND, /OE_ADDR/A0, +5V/A1, +5V/A2 and GND/A3.
ser165 = ['GND','QH_U6','QH_U7']
for i,(ref, nets) in enumerate(SR_IN):
    nm = {abcd: nets[k] for k, abcd in enumerate(['A','B','C','D','E','F','G','H'])}
    nm.update({'SH//LD':'SR_LOAD','CLK':'SR_SCK','CLK_INH':'GND','GND':'GND','VCC':'+5V',
               'SER':ser165[i],'QH': ser165[i+1] if i < 2 else 'SR_MISO'})
    place('165', ref, '74AHCT165', 175, 260 + i*55, nm)

# U9: data drive 245, A side = Pico GP8-15, B side = bus D0-7
nm245 = {'DIR':'GND','/OE':'/OE_DATA','GND':'GND','VCC':'+5V'}
nm245.update({f'A{k+1}': DATA for k, DATA in enumerate(['PD0','PD1','PD2','PD3','PD4','PD5','PD6','PD7'])})
nm245.update({f'B{k+1}': DATA for k, DATA in enumerate(['D0','D1','D2','D3','D4','D5','D6','D7'])})
place('245', 'U9', '74AHCT245', 240, 40, nm245)

# U11: 74AHCT244 sysctl drive buffer. Inputs = U15 (595) slow-drive bits;
# outputs tri-state onto the shared Z80 lines (/RESET also driven by the
# motherboard) under /OE_SYSCTL. /BUSRQ included via the octal's 5th channel.
nm244 = {'1A1':'D_/RESET','1A2':'D_/INT','1A3':'D_/NMI','1A4':'D_/WAIT','2A1':'D_/BUSRQ',
         '1Y1':'/RESET','1Y2':'/INT','1Y3':'/NMI','1Y4':'/WAIT','2Y1':'/BUSRQ',
         '/1OE':'/OE_SYSCTL','/2OE':'/OE_SYSCTL','VCC':'+5V','GND':'GND'}
place('244','U11','74AHCT244', 240, 110, nm244)

pm = dict(PICO_NET)
pm.update({'VSYS':'+5V','3V3_OUT':'+3V3','GND':'GND',
           'GP18':'FLASH_SCK','GP19':'FLASH_MOSI','GP20':'FLASH_MISO','GP21':'/CS_FLASH'})
place('PICO','U2','PICO_2', 320, 110, pm)

place('ESP','U12','ESP32C3_MOD', 390, 60,
      {'3V3':'+3V3','GND':'GND','EN':'ESP_EN','IO9_BOOT':'ESP_BOOT',
       'RXD0':'ESP_TXD','TXD0':'ESP_RXD'})
place('FLASH','U13','W25Q_64', 390, 110,
      {'/CS':'/CS_FLASH','CLK':'FLASH_SCK','DI_MOSI':'FLASH_MOSI','DO_MISO':'FLASH_MISO',
       'VCC':'+3V3','GND':'GND','/WP':'+3V3','/HOLD':'+3V3'})
place('LDO','U14','LDO_3V3_1A', 390, 150, {'VIN':'+5V','VOUT':'+3V3','GND':'GND'})
place('PWR','J2','5V_INPUT', 390, 190, {'+5V':'+5V','GND':'GND'})
for i in range(12):
    place('CAP', f'C{i+1}', '100nF', 430, 30 + i*12, {'1':'+5V' if i < 9 else '+3V3','2':'GND'})

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

with open('reva.kicad_sch','w') as f:
    f.write('\n'.join(out) + '\n')
print('wrote reva.kicad_sch:', len(wires), 'wires,', len(labels), 'labels,',
      len(ncs), 'no-connects,', len(sinst), 'symbols')
