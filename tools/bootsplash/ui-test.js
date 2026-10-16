#!/usr/bin/env node
/* ui-test.js -- drive bootsplash.html in a real DOM, and check what it produces.
 *
 * selftest.js proves the *format*; this proves the *tool*: that the page starts,
 * that a keystroke puts the glyph the pen promised into the frame, that the
 * reserved cells stay reserved, and that the four download buttons emit bytes
 * that decode back to what is on the screen.
 *
 * It needs a DOM, and this repo has no browser in its toolchain, so it uses
 * jsdom -- a host tool, not a repo dependency, and deliberately NOT wired into
 * CI (see tools/bootsplash/README.md).  Install it wherever you like:
 *
 *     npm install jsdom
 *     node tools/bootsplash/ui-test.js
 *
 * Without jsdom it says so and exits 0, so it is never a broken check.
 */
'use strict';

const fs = require('fs');
const path = require('path');

let JSDOM;
try {
  JSDOM = require('jsdom').JSDOM;
} catch (e) {
  console.log('jsdom is not installed, so the UI cannot be driven here.');
  console.log('  npm install jsdom        # then: node tools/bootsplash/ui-test.js');
  process.exit(0);
}

const HERE = __dirname;
const S = require('./core.js');
const D = require('./decoders.js');

let passed = 0, failed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('  ok    ' + name); }
  else { failed++; console.log('  FAIL  ' + name + (detail ? '\n        ' + detail : '')); }
  return ok;
}
function section(t) { console.log('\n' + t); }

// --- load the page, with the few things jsdom has no implementation of -----
const html = fs.readFileSync(path.join(HERE, 'bootsplash.html'), 'utf8');
const inline = /<script>\n([\s\S]*?)\n<\/script>/.exec(html);
if (!inline) { console.log('no inline script found in bootsplash.html'); process.exit(1); }

const blobs = [];
const dom = new JSDOM(html, {
  runScripts: 'outside-only',
  url: 'file://' + path.join(HERE, 'bootsplash.html'),
  pretendToBeVisual: true
});
const window = dom.window;
const doc = window.document;
const $ = (id) => doc.getElementById(id);

(function stub() {
  window.ImageData = function (data, w, h) {
    this.data = data; this.width = w; this.height = h;
  };
  window.Blob = function (parts, opts) {
    this.parts = parts; this.type = (opts || {}).type; blobs.push(this);
  };
  window.URL.createObjectURL = function () { return 'blob:stub'; };
  window.URL.revokeObjectURL = function () {};
  // jsdom has no canvas backend, so record what is drawn instead of rasterising.
  window.HTMLCanvasElement.prototype.getContext = function () {
    const cv = this;
    return {
      canvas: cv,
      fillStyle: '#000',
      fillRect: function () {},
      putImageData: function (img) { cv.__pixels = img; }
    };
  };
  window.HTMLCanvasElement.prototype.getBoundingClientRect = function () {
    return { left: 0, top: 0, right: 1024, bottom: 320, width: 1024, height: 320 };
  };
}());

window.eval(fs.readFileSync(path.join(HERE, 'core.js'), 'utf8'));
let startupError = null;
try {
  window.eval(inline[1]);
} catch (e) {
  startupError = e;
}

// --- the DOM as a user drives it -------------------------------------------
function type(key) {
  window.dispatchEvent(new window.KeyboardEvent('keydown', { key: key, bubbles: true, cancelable: true }));
}
function clickOn(id) { $(id).click(); }
function setValue(id, value) {
  const el = $(id);
  el.value = String(value);
  el.dispatchEvent(new window.Event('change', { bubbles: true }));
}
function pickRadio(name, value) {
  const el = doc.querySelector('input[name=' + name + '][value=' + value + ']');
  el.checked = true;
  el.dispatchEvent(new window.Event('change', { bubbles: true }));
}
function clickCell(row, col) {
  const rect = $('screen').getBoundingClientRect();
  const x = rect.left + rect.width * (col + 0.5) / S.COLS;
  const y = rect.top + rect.height * (row + 0.5) / S.ROWS;
  const at = { clientX: x, clientY: y, bubbles: true, cancelable: true };
  $('screen').dispatchEvent(new window.MouseEvent('mousedown', at));
  $('screen').dispatchEvent(new window.MouseEvent('mousemove', at));
  window.dispatchEvent(new window.MouseEvent('mouseup', at));
}
function lastBytes() { return new Uint8Array(blobs[blobs.length - 1].parts[0]); }
function status() { return $('status').textContent; }

// jsdom cannot download, so record the anchor instead of letting it navigate
// (which it reports as "not implemented" and which tests nothing anyway).
const downloads = [];
window.HTMLAnchorElement.prototype.click = function () {
  downloads.push({ name: this.download, href: this.href });
};

// The frame the app would write, read back out of its own download.
function currentFrames() {
  blobs.length = 0;
  clickOn('dlBin');
  const anim = S.parseAnimation(lastBytes());
  if (!anim.ok) throw new Error('the .bin the page wrote does not parse: ' + anim.why);
  return anim.frames.map(function (f) {
    const p = S.parseFrame(f);
    if (!p.ok) throw new Error('a frame in the page\u2019s .bin does not validate: ' + p.why);
    return p;
  });
}

function sameCells(a, b) {
  if (a.cells.length !== b.cells.length) return false;
  for (let i = 0; i < a.cells.length; i++)
    if (a.cells[i] !== b.cells[i] || a.attrs[i] !== b.attrs[i]) return false;
  return true;
}
function sameIdx(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
function waitFor(fn, ms) {
  const until = Date.now() + ms;
  return new Promise(function (resolve) {
    (function poll() {
      if (fn() || Date.now() > until) resolve(fn());
      else window.setTimeout(poll, 20);
    }());
  });
}
function finish() {
  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
}

// --- 1. it starts ----------------------------------------------------------
section('the page starts');
check('the inline script ran without throwing', startupError === null,
      startupError && (startupError.stack || startupError.message));
if (startupError) finish();

check('the provenance line names the ROM and its CRC32',
      $('provenance').textContent.indexOf(S.hex(S.CHAR_ROM_CRC32, 8)) >= 0,
      $('provenance').textContent);
check('the status line is the ready message', /ready/.test(status()), status());
check('the palette is 34 swatches, each with a canvas',
      doc.querySelectorAll('#palette .swatch').length === 34 &&
      doc.querySelectorAll('#palette .swatch canvas').length === 34);
check('the swatches are labelled A..a then the hatch',
      doc.querySelectorAll('#palette .swatch .k')[0].textContent === 'A' &&
      doc.querySelectorAll('#palette .swatch .k')[32].textContent === 'a' &&
      doc.querySelectorAll('#palette .swatch .k')[33].textContent === '\u00C0');
check('the monitor list is populated', $('monitor').options.length === 4);
// 80 columns at 2x: 128 cells x 8 dots x 0.65 x 2 = 1331 wide, 32 x 10 x 2 tall.
check('the screen canvas is 1331 x 640 (80 columns, 2x)',
      $('screen').width === 1331 && $('screen').height === 640,
      $('screen').width + ' x ' + $('screen').height);
check('the screen canvas was drawn',
      !!$('screen').__pixels &&
      $('screen').__pixels.data.length === 1331 * 640 * 4);

// --- 2. click a cell, then type -------------------------------------------
section('click a cell, then type');
clickCell(0, 0);
type('p');
let st = status();
let f = currentFrames();
check('typing "p" in the character font writes glyph 0x70 at the cell',
      f[0].cells[0] === 0x70, 'got 0x' + S.hex(f[0].cells[0], 2));
check('and the cell is bright', f[0].attrs[0] === 1);
check('and the status named the glyph', /glyph 0x70/.test(st), st);

type('A');
st = status();
f = currentFrames();
check('the character pen refuses a capital, which is a graphics key',
      f[0].cells[1] === 0x20 && /graphics key/.test(st), st);

pickRadio('face', 'graphics');
type('A');
f = currentFrames();
check('the graphics pen turns "A" into glyph 0x00', f[0].cells[1] === 0x00,
      'got 0x' + S.hex(f[0].cells[1], 2));

pickRadio('face', 'char');
pickRadio('bright', 'dim');
type('p');
f = currentFrames();
check('the dim pen writes the glyph but clears the ninth bit',
      f[0].cells[2] === 0x70 && f[0].attrs[2] === 0,
      'cell 0x' + S.hex(f[0].cells[2], 2) + ', attr ' + f[0].attrs[2]);

// --- 3. the palette, and the cells that are not the designer's -------------
section('the graphics palette, and the trailer');
doc.querySelectorAll('#palette .swatch')[33].click();
check('clicking the hatch swatch selects glyph 0x7F', /glyph 0x7F/.test(status()), status());
clickCell(5, 10);
f = currentFrames();
check('clicking a cell with a palette glyph paints it there',
      f[0].cells[5 * S.COLS + 10] === 0x7F,
      'got 0x' + S.hex(f[0].cells[5 * S.COLS + 10], 2));
clickCell(31, 120);
check('row 31, columns 120-127 refuse the pen \u2014 that is the trailer',
      /trailer/.test(status()), status());

// --- 4. frames ------------------------------------------------------------
section('frames');
clickOn('addFrame');
check('"+1 frame" adds one at the end', $('frameCount').textContent === '2 / 2',
      $('frameCount').textContent);
check('and the filmstrip grows a thumbnail',
      doc.querySelectorAll('#filmstrip .thumb').length === 2);
clickOn('prev');
clickOn('dupFrame');
f = currentFrames();
check('"copy" duplicates the current frame, in place after it',
      f.length === 3 && sameCells(f[0], f[1]), f.length + ' frames');
clickOn('delFrame');
f = currentFrames();
check('"delete" removes it again', f.length === 2, f.length + ' frames');
clickOn('dupFrame');
f = currentFrames();
check('three frames, and the .bin carries all of them', f.length === 3);
check('frame 2 is a copy of frame 1', sameCells(f[1], f[2]));
check('frame 0 still holds what was typed into it',
      f[0].cells[0] === 0x70 && f[0].cells[5 * S.COLS + 10] === 0x7F &&
      f[0].attrs[2] === 0);

// --- 5. the .bin ----------------------------------------------------------
section('the .bin download');
setValue('fps', 15);
$('loop').checked = false;
$('loop').dispatchEvent(new window.Event('change', { bubbles: true }));
blobs.length = 0;
clickOn('dlBin');
const raw = lastBytes();
const anim = S.parseAnimation(raw);
check('the header carries the fps and the loop flag',
      anim.ok && anim.fps === 15 && anim.loop === false, anim.why || ('fps ' + anim.fps));
check('the header says 128 x 32',
      (raw[10] | raw[11] << 8) === S.COLS && (raw[12] | raw[13] << 8) === S.ROWS);
check('the file is the header plus three frames',
      raw.length === S.ANIM_HEADER + 3 * S.FRAME * 2, raw.length + ' bytes');
check('tail -c +33 of the container is frame 0, unchanged',
      Buffer.from(raw.subarray(S.ANIM_HEADER, S.ANIM_HEADER + S.FRAME * 2))
        .equals(Buffer.from(anim.frames[0])));
check('the status reports what it wrote', /wrote bootsplash\.bin/.test(status()), status());

// --- 6. the .txt ----------------------------------------------------------
section('the .txt download');
clickOn('first');
blobs.length = 0;
clickOn('dlTxt');
const txt = lastBytes();
check('the art text is 32 lines of 128 characters and a trailing newline',
      txt.length === 32 * 129, txt.length + ' bytes');
const art = S.parseArtText(String.fromCharCode.apply(null, txt));
check('nothing in it is unreadable', art.unknown.length === 0, art.unknown.join(' '));
f = currentFrames();
check('and it reads back to the glyphs that were on screen',
      sameGlyphs(art.cells, f[0].cells));

function sameGlyphs(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

// --- 7. the .gif ----------------------------------------------------------
section('the .gif download');
$('loop').checked = true;                      // the .bin test turned it off
$('loop').dispatchEvent(new window.Event('change', { bubbles: true }));
blobs.length = 0;
downloads.length = 0;
clickOn('dlGif');
check('the download is named for the tool', downloads.length === 1 &&
      downloads[0].name === 'bootsplash.gif', JSON.stringify(downloads));
const gif = D.decodeGIF(Buffer.from(lastBytes()));
const vpOpts = { columns: 80, scale: 2, col0: 0, row0: 0, cols: 80, rows: 24 };
const want0 = S.renderIndexed(f[0].cells, f[0].attrs, vpOpts);
check('one GIF frame per animation frame', gif.frames.length === 3,
      gif.frames.length + ' frames');
check('the GIF loops', gif.loopCount === 0, 'loop count ' + gif.loopCount);
check('the delay is 100/fps hundredths', gif.frames[0].delay === 7,
      'delay ' + gif.frames[0].delay);
check('a GIF frame is the viewport, 80 columns at 2x',
      gif.frames[0].w === want0.w && gif.frames[0].h === want0.h,
      gif.frames[0].w + 'x' + gif.frames[0].h + ', want ' + want0.w + 'x' + want0.h);
check('and its pixels are the ones the renderer produced',
      sameIdx(gif.frames[0].idx, want0.idx));
check('the GIF palette is the monitor palette',
      JSON.stringify(gif.frames[0].palette) === JSON.stringify(S.paletteFor('white')));

// --- 8. the .png, and a round trip through the import ---------------------
(async function tail() {
  section('the .png download');
  blobs.length = 0;
  clickOn('dlPng');
  await waitFor(function () { return blobs.length > 0; }, 3000);
  check('the PNG download produced a file', blobs.length > 0);
  if (blobs.length) {
    const png = D.decodePNG(Buffer.from(lastBytes()));
    check('the PNG is the viewport at 80 columns, 2x',
          png.w === want0.w && png.h === want0.h, png.w + 'x' + png.h);
    check('and its indices are the ones the renderer produced',
          sameIdx(png.idx, want0.idx));
    check('and the status reports the size it wrote',
          new RegExp('wrote bootsplash-f1\\.png: ' + want0.w + '\u00d7' + want0.h)
            .test(status()), status());
  }

  section('import');
  const one = S.buildAnimation([S.buildFrame(f[1].cells, f[1].attrs)], 7, true);
  const file = new window.File([one], 'roundtrip.bin', { type: 'application/octet-stream' });
  const input = $('file');
  Object.defineProperty(input, 'files', { value: [file], configurable: true });
  input.dispatchEvent(new window.Event('change', { bubbles: true }));
  await waitFor(function () { return /imported/.test(status()); }, 3000);
  check('a .bin imports back: one frame, 7 fps, looping',
        /imported 1 frame at 7 fps, looping/.test(status()), status());
  check('and the frame count follows', $('frameCount').textContent === '1 / 1',
        $('frameCount').textContent);
  const back = currentFrames();
  check('and the frame that came back is the frame that went in',
        sameCells(back[0], { cells: f[1].cells, attrs: f[1].attrs }));

  finish();
}()).catch(function (e) {
  console.log('  FAIL  the tail threw: ' + ((e && e.stack) || e));
  finish();
});
