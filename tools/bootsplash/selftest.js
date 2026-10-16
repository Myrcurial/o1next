#!/usr/bin/env node
/* selftest.js -- check tools/bootsplash/core.js against the repo's own files.
 *
 * The point of this file is that the browser tool is not trusted on its own word.
 * Every claim `bootsplash.html` makes about its output is checked here, against
 * something that is not this tool:
 *
 *   1. the embedded character ROM is the ROM          -- CRC32 5297c109
 *   2. the trailer is the machine's trailer           -- re-seals the committed
 *                                                        firmware/rom-service/frame.bin
 *                                                        and must reproduce it byte for byte
 *   3. the whole frame builder is the machine's       -- builds a frame and has
 *                                                        tools/research/rom2strokes.py
 *                                                        build the same one from the same
 *                                                        art, then compares the bytes
 *   4. the container round-trips                      -- and `tail -c +33` of a
 *                                                        one-frame animation is a frame
 *   5. the PNG decodes to the pixels that went in     -- zlib + our own unfilter
 *   6. the GIF decodes to the pixels that went in     -- our own LZW reader AND
 *                                                        macOS's ImageIO, via sips
 *
 * Usage: node tools/bootsplash/selftest.js
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { execFileSync } = require('child_process');

const S = require('./core.js');

const HERE = __dirname;
const REPO = path.resolve(HERE, '..', '..');
const ROM_PATH = path.join(REPO, 'tools', 'emulator-setup', 'roms', 'char.ua15');
const FRAME_PATH = path.join(REPO, 'firmware', 'rom-service', 'frame.bin');
const STROKES = path.join(REPO, 'tools', 'research', 'rom2strokes.py');

let passed = 0, failed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('  ok    ' + name); }
  else { failed++; console.log('  FAIL  ' + name + (detail ? '\n        ' + detail : '')); }
  return ok;
}
function section(title) { console.log('\n' + title); }

// --- 1. the ROM ------------------------------------------------------------
section('the character generator ROM');
{
  const rom = fs.readFileSync(ROM_PATH);
  check('the embedded ROM is char.ua15 (' + rom.length + ' bytes)',
        S.romOk() && S.romCrc32() === S.crc32(rom),
        'embedded CRC32 ' + S.hex(S.romCrc32(), 8) +
        ', char.ua15 CRC32 ' + S.hex(S.crc32(rom), 8));
  // Spot-check the layout: rom[row*128 + code], bit 7 leftmost.
  let bad = 0;
  for (let code = 0; code < 128; code++)
    for (let r = 0; r < 10; r++)
      for (let c = 0; c < 8; c++)
        if (S.glyphDot(code, r, c) !== ((rom[r * 128 + code] >> (7 - c)) & 1)) bad++;
  check('every glyph dot decodes as rom[row*128 + code], bit 7 leftmost', bad === 0,
        bad + ' dots differ');
  check('the graphics palette is 34 cells, A-a plus the hatch',
        S.GRAPHICS_KEYS.length === 34 &&
        S.GRAPHICS_KEYS[0].key === 'A' && S.GRAPHICS_KEYS[0].glyph === 0 &&
        S.GRAPHICS_KEYS[32].key === 'a' && S.GRAPHICS_KEYS[32].glyph === 0x20 &&
        S.GRAPHICS_KEYS[33].glyph === 0x7F,
        S.GRAPHICS_KEYS.map(k => k.key + '=' + k.glyph).join(' '));
}

// --- 2. the trailer, against the committed frame ---------------------------
section('the trailer, against the committed frame');
{
  const frame = fs.readFileSync(FRAME_PATH);
  check('frame.bin is 8192 bytes', frame.length === 8192, frame.length + ' bytes');
  for (const [name, off] of [['character', 0], ['attribute', 4096]]) {
    const half = frame.subarray(off, off + 4096);
    const resealed = S.seal(half.subarray(0, S.TRAILER_AT));
    let same = resealed.length === half.length;
    for (let i = 0; same && i < half.length; i++) if (resealed[i] !== half[i]) same = false;
    const res = S.checkHalf(half);
    check('re-sealing the ' + name + ' half reproduces it byte for byte', same,
          'sum ' + S.hex(res.sum));
  }
  check('checkFrame() accepts the committed frame', S.checkFrame(frame).ok,
        S.checkFrame(frame).why);
  // And a single flipped body byte must be caught.
  const bent = Buffer.from(frame);
  bent[10] ^= 0x01;
  check('a flipped body byte is caught', !S.checkFrame(bent).ok);
  const bentMagic = Buffer.from(frame);
  bentMagic[4088] = 0x00;
  check('a bent magic is caught', !S.checkFrame(bentMagic).ok);
}

// --- a representative screen, built the way the app builds one -------------
function sampleScreen() {
  const cells = S.blankCells(), attrs = S.brightAttrs();
  const put = (r, c, glyph, bright) => {
    const i = r * S.COLS + c;
    if (S.isReserved(i)) return;
    cells[i] = glyph & 0x7F;
    attrs[i] = bright === false ? 0 : 1;
  };
  const text = (r, c, s) => {
    // Through the app's own pen, so the sample is a screen the app could really
    // have produced -- refusals and all.  `a` and the capitals are the graphics
    // keys and are therefore skipped, which is the documented cost of `sui 65`.
    for (let i = 0; i < s.length; i++) {
      const g = S.glyphForKey(s.charCodeAt(i), 'char');
      if (g !== null) put(r, c + i, g);
    }
  };

  text(0, 2, 'osborne 1 next rom 2.0 2026');
  text(1, 2, 'press return to begin');
  // Every graphics glyph the palette offers, in order, twice over.
  for (let i = 0; i < 34; i++) {
    put(3, 2 + i * 3, S.GRAPHICS_KEYS[i].glyph);
    put(5, 2 + i * 3, S.GRAPHICS_KEYS[i].glyph);
  }
  // A dim run, to prove the attribute plane is not hard-wired bright.
  for (let c = 40; c < 60; c++) put(7, c, 0x7F, false);
  for (let r = 9; r < 14; r++) text(r, 1, 'a solid stem across rows 9-13');
  return { cells, attrs };
}

// --- 3. the whole frame builder, against the repo's own tool ---------------
section('the frame builder, against tools/research/rom2strokes.py');
{
  const { cells } = sampleScreen();
  const mine = Buffer.from(S.buildFrame(cells, S.brightAttrs()));
  check('a built frame is 8192 bytes and validates',
        mine.length === 8192 && S.checkFrame(mine).ok);

  // rom2strokes.py's art loader implements the graphics half of `sui 65` and the
  // printable half, but has no U+00C0 case -- so the 0x7F hatch is expressible in
  // a .bin and in this app's own text round-trip, and NOT in that tool's --art.
  // Swap the hatch out for the blank so the two frames can be compared at all,
  // and check the divergence itself further down.
  const toolCells = Uint8Array.from(cells);
  for (let i = 0; i < toolCells.length; i++)
    if (toolCells[i] === S.HATCH_CODE) toolCells[i] = S.BLANK;

  // rom2strokes.py's CLI cannot be pointed at a 128-column screen: its `main()`
  // runs the stripe proof first, and that proof indexes the letter boxes of the
  // 153-column boot-screen art (BOXES runs to column 152), so a narrower art
  // crashes it in `subgrid`.  Import the module and call the functions that
  // matter -- `load_art`, then `frame`, which is `chars_half` + `attrs_half` +
  // `seal`, exactly what the CLI would have run.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bootsplash-'));
  const driver = path.join(tmp, 'drive.py');
  fs.writeFileSync(driver, [
    'import importlib.util, sys',
    "spec = importlib.util.spec_from_file_location('rom2strokes', sys.argv[1])",
    'm = importlib.util.module_from_spec(spec)',
    'spec.loader.exec_module(m)',
    'rows = m.load_art(sys.argv[2])',
    "open(sys.argv[3], 'wb').write(m.frame(rows, int(sys.argv[4])))",
    ''
  ].join('\n'));

  function viaRom2strokes(artPath, outPath, origin) {
    try {
      execFileSync('python3', [driver, STROKES, artPath, outPath, String(origin)],
                   { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      return { ok: true };
    } catch (e) {
      return { ok: false, why: String((e.stderr || e.message) || '').trim()
                                       .split('\n').slice(-3).join(' | ') };
    }
  }

  const artFile = path.join(tmp, 'art.txt');
  const toolFrame = path.join(tmp, 'frame.bin');
  fs.writeFileSync(artFile, Buffer.from(S.artTextBytes(toolCells)));
  const mineTool = Buffer.from(S.buildFrame(toolCells, S.brightAttrs()));
  const ran = viaRom2strokes(artFile, toolFrame, 0);
  if (check('rom2strokes.py built a frame from the same art', ran.ok, ran.why)) {
    const theirs = fs.readFileSync(toolFrame);
    let diff = -1;
    for (let i = 0; i < Math.max(mineTool.length, theirs.length); i++)
      if (mineTool[i] !== theirs[i]) { diff = i; break; }
    check('the two frames are byte-identical (' + mineTool.length + ' bytes)', diff < 0,
          diff < 0 ? '' : 'first difference at 0x' + diff.toString(16) +
          ': mine ' + mineTool[diff] + ', rom2strokes ' + theirs[diff]);
  }

  // The divergence, asserted rather than assumed: one lone hatch cell.
  {
    const hatched = S.blankCells();
    hatched[0] = S.HATCH_CODE;
    const hArt = path.join(tmp, 'hatch.txt');
    const hFrame = path.join(tmp, 'hatch.bin');
    fs.writeFileSync(hArt, Buffer.from(S.artTextBytes(hatched)));
    const r = viaRom2strokes(hArt, hFrame, 0);
    const theirs = r.ok ? fs.readFileSync(hFrame)[0] : -1;
    check('the 0x7F hatch is in the .bin but not through that art loader (no U+00C0 case)',
          r.ok && theirs === S.BLANK &&
          S.buildFrame(hatched, S.brightAttrs())[0] === S.HATCH_CODE,
          'rom2strokes put ' + S.hex(theirs, 2) + ' where the app puts ' +
          S.hex(S.HATCH_CODE, 2));
  }

  // frame.bin -> planes -> frame.bin, with no art file in the loop at all.
  const planes = S.parseFrame(fs.readFileSync(FRAME_PATH));
  check('the committed frame survives planes -> buildFrame unchanged',
        Buffer.from(S.buildFrame(planes.cells, planes.attrs))
              .equals(fs.readFileSync(FRAME_PATH)));

  const art = S.artTextBytes(S.blankCells());
  check('the art text is 32 lines of 128 characters', art.length === 32 * 129,
        art.length + ' bytes');
}

// --- 4. the animation container --------------------------------------------
section('the animation container');
{
  const one = Buffer.from(fs.readFileSync(FRAME_PATH));
  const anim = Buffer.from(S.buildAnimation([one], 10, true));
  check('a one-frame animation is 32 + 8192 bytes', anim.length === 32 + 8192,
        anim.length + ' bytes');
  check('tail -c +33 of it is the committed frame.bin',
        anim.subarray(S.ANIM_HEADER).equals(one));
  const back = S.parseAnimation(anim);
  check('it parses back with the fps and the loop flag', back.ok &&
        back.fps === 10 && back.loop === true && back.frames.length === 1,
        back.why || '');
  check('and its frame is byte-identical',
        back.ok && Buffer.from(back.frames[0]).equals(one));

  const two = Buffer.from(S.buildAnimation([one, one], 25, false));
  const t = S.parseAnimation(two);
  check('a two-frame animation round-trips', t.ok && t.frames.length === 2 &&
        t.fps === 25 && t.loop === false, t.why || '');
  // The header validates itself, so a bent one is caught rather than obeyed.
  const bent = Buffer.from(two); bent[14] = 99;
  check('a bent header is caught', !S.parseAnimation(bent).ok,
        S.parseAnimation(bent).why);
  check('a truncated animation is caught',
        !S.parseAnimation(two.subarray(0, two.length - 1)).ok);
  check('a file with no magic is caught',
        !S.parseAnimation(Buffer.alloc(64)).ok);
}

// --- 5. the art text round-trips -------------------------------------------
section('the art text form');
{
  const { cells } = sampleScreen();
  const parsed = S.parseArtText(S.artText(cells));
  let diff = 0;
  for (let i = 0; i < S.FRAME; i++)
    if (!S.isReserved(i) && parsed.cells[i] !== cells[i]) diff++;
  check('cells -> art text -> cells is lossless', diff === 0, diff + ' cells differ');
  check('a screen the app can produce has no lossy cells',
        S.artTextLossy(cells).length === 0, S.artTextLossy(cells).length + ' cells');
  const foreign = S.blankCells();
  foreign[0] = 0x61;                    // glyph 0x61: no pen can reach it
  check('a foreign glyph in 0x41-0x61 is reported, not silently mangled',
        S.artTextLossy(foreign).length === 1);

  // The hatch is the one glyph whose art character is not printable ASCII.
  const hatched = S.blankCells();
  hatched[0] = S.HATCH_CODE;
  const text = S.artText(hatched);
  check('the 0x7F hatch is written as U+00C0 and read back',
        text.charCodeAt(0) === 0xC0 &&
        S.parseArtText(text).cells[0] === S.HATCH_CODE);
  check('U+00C0 is the hatch in the mapping, as tools/romfont.py builds it',
        S.glyphForArtChar(0xC0) === 0x7F && S.artCharForGlyph(0x7F) === '\u00C0');

  // The documented cost of `sui 65`, asserted rather than described.
  check('a capital is a glyph index, not a letter',
        S.glyphForArtChar('A'.charCodeAt(0)) === 0x00 &&
        S.glyphForArtChar('a'.charCodeAt(0)) === 0x20);
  check('so the character pen refuses the graphics range',
        S.glyphForKey('A'.charCodeAt(0), 'char') === null &&
        S.glyphForKey('p'.charCodeAt(0), 'char') === 0x70 &&
        S.glyphForKey('A'.charCodeAt(0), 'graphics') === 0x00 &&
        S.glyphForKey('p'.charCodeAt(0), 'graphics') === null);
}

// --- decoders -------------------------------------------------------------
// The PNG, GIF and BMP readers live in decoders.js, so that ui-test.js can check
// what the page’s own download buttons produce with the same eyes.
const D = require('./decoders.js');
const decodePNG = D.decodePNG, decodeGIF = D.decodeGIF, decodeBMP = D.decodeBMP;

// --- 6. the PNG ------------------------------------------------------------
section('the PNG');
{
  const { cells, attrs } = sampleScreen();
  const palette = S.paletteFor('amber');
  // 80 columns is the machine's 65% dot width: the type narrows, the screen does not.
  const img = S.renderIndexed(cells, attrs, { columns: 80, scale: 1 });
  check('an 80-column screen renders 666 x 320', img.w === 666 && img.h === 320,
        img.w + ' x ' + img.h);
  let dim = 0, ink = 0, paper = 0;
  for (let i = 0; i < img.idx.length; i++) {
    if (img.idx[i] === 2) dim++; else if (img.idx[i] === 1) ink++; else paper++;
  }
  check('the attribute plane reaches the pixels (dim cells are dim)',
        dim > 0 && ink > 0 && paper > 0,
        'paper ' + paper + ', ink ' + ink + ', dim ' + dim);
  // 52 columns is the machine's own cell: 128 x 8 pixels across.
  const native = S.renderIndexed(cells, attrs, { columns: 52, scale: 1 });
  check('a 52-column screen renders 1024 x 320',
        native.w === 1024 && native.h === 320, native.w + ' x ' + native.h);
  // The viewport is N columns of 24 rows, and its pixel width never changes.
  const vp52 = S.renderIndexed(cells, attrs,
    { columns: 52, scale: 1, cols: 52, rows: 24, col0: 11 });
  const vp80 = S.renderIndexed(cells, attrs,
    { columns: 80, scale: 1, cols: 80, rows: 24, col0: 11 });
  check('a viewport is the same width in every SCREEN-PAC mode',
        vp52.w === 416 && vp80.w === 416 && vp52.h === 240 && vp80.h === 240,
        vp52.w + 'x' + vp52.h + ' and ' + vp80.w + 'x' + vp80.h);

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bootsplash-png-'));
  const pngPath = path.join(tmp, 'screen.png');
  Promise.all([
    S.encodePNG(img, palette, S.deflateStored),
    S.encodePNG(img, palette, (b) => zlib.deflateSync(b))
  ]).then(([stored, zlibbed]) => {
    fs.writeFileSync(pngPath, Buffer.from(zlibbed));
    for (const [name, bytes] of [['stored blocks', stored], ['zlib', zlibbed]]) {
      let ok = true, why = '';
      try {
        const got = decodePNG(Buffer.from(bytes));
        ok = got.w === img.w && got.h === img.h && got.idx.length === img.idx.length;
        if (ok) {
          for (let i = 0; i < img.idx.length; i++)
            if (got.idx[i] !== img.idx[i]) { ok = false; why = 'first difference at ' + i; break; }
        }
        if (ok) ok = JSON.stringify(got.palette) === JSON.stringify(palette);
        if (!ok && !why) why = 'palette or size mismatch';
      } catch (e) { ok = false; why = e.message; }
      check('the PNG decodes to the pixels that went in (' + name + ')', ok, why);
    }
    let sips = '';
    try {
      sips = execFileSync('sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', pngPath],
                          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) { sips = 'sips failed: ' + e.message; }
    check('sips reads it as ' + img.w + ' x ' + img.h + ' (ImageIO, not our decoder)',
          sips.indexOf('pixelWidth: ' + img.w) >= 0 &&
          sips.indexOf('pixelHeight: ' + img.h) >= 0,
          sips.trim().split('\n').join(' | '));
    gifTests(tmp, cells, attrs, palette);
  }).catch((e) => {
    console.log('  FAIL  the PNG block threw: ' + ((e && e.stack) || e));
    process.exit(1);
  });
}

// --- 7. the GIF ------------------------------------------------------------
//
// Two decoders on purpose.  Ours proves the bit packing and the code-width rule
// against a reader written from the spec; macOS's ImageIO proves it against an
// implementation nobody here wrote.
function gifTests(tmp, cells, attrs, palette) {
  section('the GIF');
  const f2 = { cells: Uint8Array.from(cells), attrs: Uint8Array.from(attrs) };
  for (let c = 0; c < S.COLS; c++) f2.cells[20 * S.COLS + c] = 0x7F;
  const f3 = { cells: Uint8Array.from(cells), attrs: new Uint8Array(S.FRAME) };
  const frames = [{ cells: cells, attrs: attrs }, f2, f3].map(
    (s) => S.renderIndexed(s.cells, s.attrs, { columns: 52, scale: 1 }));

  const gif = Buffer.from(S.encodeGIF(frames, palette, 10, true));
  const gifPath = path.join(tmp, 'screen.gif');
  fs.writeFileSync(gifPath, gif);

  let ok = true, why = '';
  try {
    const got = decodeGIF(gif);
    ok = got.frames.length === 3 && got.w === frames[0].w && got.h === frames[0].h;
    if (!ok) why = got.frames.length + ' frames, ' + got.w + 'x' + got.h;
    else if (got.loopCount !== 0) { ok = false; why = 'loop count ' + got.loopCount; }
    else {
      for (let f = 0; ok && f < 3; f++) {
        if (got.frames[f].delay !== 10) {
          ok = false; why = 'frame ' + f + ' delay ' + got.frames[f].delay; break;
        }
        if (got.frames[f].idx.length !== frames[f].idx.length) {
          ok = false;
          why = 'frame ' + f + ' has ' + got.frames[f].idx.length + ' pixels'; break;
        }
        for (let i = 0; i < frames[f].idx.length; i++)
          if (got.frames[f].idx[i] !== frames[f].idx[i]) {
            ok = false; why = 'frame ' + f + ' first difference at ' + i; break;
          }
      }
    }
  } catch (e) { ok = false; why = e.message; }
  check('the GIF decodes to the frames that went in (our LZW reader)', ok, why);

  const bmpPath = path.join(tmp, 'screen.bmp');
  let sipsOk = true, sipsWhy = '';
  try {
    execFileSync('sips', ['-s', 'format', 'bmp', gifPath, '--out', bmpPath],
                 { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) { sipsOk = false; sipsWhy = 'sips failed: ' + e.message; }
  if (check('sips converts the GIF to a BMP', sipsOk, sipsWhy)) {
    const bmp = decodeBMP(fs.readFileSync(bmpPath));
    let bad = 0, first = '';
    for (let y = 0; y < frames[0].h; y++)
      for (let x = 0; x < frames[0].w; x++) {
        const want = palette[frames[0].idx[y * frames[0].w + x]];
        const got = bmp.px(x, y);
        if (want[0] !== got[0] || want[1] !== got[1] || want[2] !== got[2]) {
          bad++; if (!first) first = x + ',' + y;
        }
      }
    check('ImageIO decodes frame 1 to the same pixels (' + bmp.w + 'x' + bmp.h + ')',
          bmp.w === frames[0].w && bmp.h === frames[0].h && bad === 0,
          bad + ' pixels differ, first at ' + first);
  }

  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
}
