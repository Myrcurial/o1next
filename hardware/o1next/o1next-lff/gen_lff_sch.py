#!/usr/bin/env python3
"""Generate the o1next-LFF (1:1 mainboard replacement) KiCad skeleton:
root sheet with hierarchical sheet symbols + child sheets carrying
design notes. Block-level starting point for full schematic capture.
Regenerate: python3 gen_lff_sch.py"""
import uuid, datetime, os

def uid(): return str(uuid.uuid4())
TODAY = str(datetime.date.today())

SHEETS = [
    ('cpu_mem',   'CPU + SRAM + ROM: Z84C00 (socketed DIP-40 for interposer upgrade path), 64KB SRAM (replaces 16x 4116 DRAM + refresh logic), 27C128/Flash BIOS, address decode, bank switching (bank 1 RAM / bank 2 IO+video) per docs/o1-memory-io-map.md'),
    ('video',     'Video: char-gen ROM socket (accepts original font ROM), 6845-class CRTC or discrete equivalent, 1Kx8/2Kx8 video RAM dual-port, composite out; HDMI option deferred to interposer'),
    ('floppy',    'Floppy: MB8877/FDC179x-class FDC, original Shugart connector pinout, DD data separator (enables PC 360K MFM reads for FATCOPY #51); header matches hardware/floppy-adapter expectations'),
    ('io',        'Serial + IEEE-488: 6850 ACIA (MODEM TTL P1 + RS-232 P2 per docs/o1-modem-serial.md), 6821 PIA IEEE-488 port, CTC for 60Hz interrupt, NMI logic'),
    ('keyboard',  'Keyboard: P4 connector (O1A 24-hole/20-pin, pin 19 = +12V via J6+R21), 8x8 matrix scan (74LS05-class OC drivers + pull-ups); interposer KVM/2nd-keyboard injects here'),
    ('power',     'Power: USB-C PD trigger (15-19V) -> +5V and +12V rails (replaces original PSU incl. RIFA caps); optionally stock power connector passthrough for purists'),
    ('clock',     'Clock/reset: single-oscillator design (#55), 4.0 MHz base, reset supervisor; NO turbo on LFF (turbo is a lunchbox feature)'),
]

def child_sch(name, note):
    lines = note.split(': ', 1)
    text = '\n'.join('  (text "' + l + '" (at 30 ' + str(40 + i*7.62) + ' 0) (effects (font (size 2 2))) (uuid "' + uid() + '"))' for i, l in enumerate([lines[0]] + [lines[1][j:j+110] for j in range(0, len(lines[1]), 110)]))
    return ('(kicad_sch (version 20230121) (generator "eeschema") (generator_version "7.0")\n'
        f'  (uuid "{uid()}")\n  (paper "A4")\n'
        f'  (title_block (title "o1next-LFF: {name}") (date "{TODAY}") (rev "0.0-block"))\n'
        '  (lib_symbols)\n' + text + '\n'
        '  (sheet_instances (path "/" (page "1")))\n)\n')

root = ['(kicad_sch (version 20230121) (generator "eeschema") (generator_version "7.0")',
        f'  (uuid "{uid()}")', '  (paper "A2")',
        f'  (title_block (title "o1next-LFF 1:1 mainboard replacement") (date "{TODAY}") (rev "0.0-block") (comment 1 "Faithful reproduction: socketed DIP-40 Z80; interposer is the upgrade path. L-shaped board, 4 mounting bosses, stock port locations."))',
        '  (lib_symbols)']
x, y, page = 40, 40, 2
for i, (name, note) in enumerate(SHEETS):
    root.append(f'''  (sheet (at {x} {y}) (size 140 50) (fields_autoplaced yes) (stroke (width 0.1524) (type solid)) (fill (color 0 0 0 0.0000)) (uuid "{uid()}")
    (property "Sheetname" "{name}" (at {x} {y-2} 0) (effects (font (size 1.27 1.27)) (justify left bottom)))
    (property "Sheetfile" "{name}.kicad_sch" (at {x} {y+52} 0) (effects (font (size 1.27 1.27)) (justify left top)))
  )''')
    with open(os.path.join(os.path.dirname(__file__), f'{name}.kicad_sch'), 'w') as f:
        f.write(child_sch(name, note))
    y += 62
    if i == 3: x, y = 210, 40
root.append('  (sheet_instances (path "/" (page "1")' + ''.join(f' (path "/{uid()[:8]}" (page "{page+i}"))' for i in range(len(SHEETS))) + '))')
root.append(')')
with open(os.path.join(os.path.dirname(__file__), 'o1next-lff.kicad_sch'), 'w') as f:
    f.write('\n'.join(root) + '\n')
print('wrote root +', len(SHEETS), 'child sheets')
