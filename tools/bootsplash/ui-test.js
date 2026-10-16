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
function typeMod(key) {
  window.dispatchEvent(new window.KeyboardEvent('keydown',
    { key: key, ctrlKey: true, bubbles: true, cancelable: true }));
}
function dragSelect(r0, c0, r1, c1) {
  const rect = $('screen').getBoundingClientRect();
  const at = (row, col) => ({
    clientX: rect.left + rect.width * (col + 0.5) / S.COLS,
    clientY: rect.top + rect.height * (row + 0.5) / S.ROWS,
    bubbles: true, cancelable: true
  });
  $('screen').dispatchEvent(new window.MouseEvent('mousedown', at(r0, c0)));
  $('screen').dispatchEvent(new window.MouseEvent('mousemove', at(r1, c1)));
  window.dispatchEvent(new window.MouseEvent('mouseup', at(r1, c1)));
}
// The palette's contents change with the pen mode, so find a swatch by its glyph
// rather than by its position.
function swatchFor(glyph) {
  return doc.querySelector('#palette .swatch[data-glyph="' + glyph + '"]');
}
function paletteCount() { return doc.querySelectorAll('#palette .swatch').length; }
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
check('standard characters show the 95 standard glyphs and no blocks',
      paletteCount() === 95 && swatchFor(0x41) !== null &&
      swatchFor(0x00) === null && swatchFor(0x7F) === null,
      paletteCount() + ' swatches');
check('and each is labelled with the character you type',
      swatchFor(0x41).querySelector('.k').textContent === 'A' &&
      swatchFor(0x20).querySelector('.k').textContent === 'sp' &&
      swatchFor(0x70).querySelector('.k').textContent === 'p');
check('the hint names the set and its size',
      /95 standard characters/.test($('paletteHint').textContent), $('paletteHint').textContent);
pickRadio('keys', 'sui65');
check('graphical characters show the 34 blocks and the hatch, and no letters',
      paletteCount() === 34 && swatchFor(0x00) !== null &&
      swatchFor(0x7F) !== null && swatchFor(0x41) === null,
      paletteCount() + ' swatches');
check('and each is labelled with the sui 65 key that reaches it',
      swatchFor(0x00).querySelector('.k').textContent === 'A' &&
      swatchFor(0x20).querySelector('.k').textContent === 'a' &&
      swatchFor(0x7F).querySelector('.k').textContent === '\u00C0',
      swatchFor(0x00).querySelector('.k').textContent + ' / ' +
      swatchFor(0x7F).querySelector('.k').textContent);
check('and the tooltip names this mode\'s key, and says when the other has none',
      /graphical: type "A"/.test(swatchFor(0x00).title) &&
      /standard: no key/.test(swatchFor(0x00).title), swatchFor(0x00).title);
pickRadio('keys', 'direct');
check('and switching back restores the standard set',
      paletteCount() === 95 && swatchFor(0x00) === null, paletteCount() + ' swatches');
check('the monitor list is populated', $('monitor').options.length === 4);
// 80 columns at 1x: 128 cells x 8 dots x 0.65 = 666 wide, 32 x 10 = 320 tall.
check('the screen canvas is 666 x 320 (80 columns, 1x)',
      $('screen').width === 666 && $('screen').height === 320,
      $('screen').width + ' x ' + $('screen').height);
check('the screen canvas was drawn',
      !!$('screen').__pixels &&
      $('screen').__pixels.data.length === 666 * 320 * 4);

// The zoom has to change what you *see*, not only the backing store.  It once did
// not: the canvas was stretched to 100% of its column, so every zoom step produced
// the same picture at a different resolution and nothing moved on screen.
check('the grid is shown at its own size, not stretched to its column',
      $('screen').style.width === '666px' && $('screen').style.height === '320px' &&
      $('screenBox').style.width === '666px',
      $('screen').style.width + ' / box ' + $('screenBox').style.width);
setValue('zoom', 2);
check('2x doubles what is on screen',
      $('screen').style.width === '1331px' && $('screen').width === 1331,
      $('screen').style.width + ' css, ' + $('screen').width + ' backing');
setValue('zoom', 3);
check('and 3x is bigger again',
      $('screen').style.width === '1997px' && $('screenBox').style.width === '1997px',
      $('screen').style.width);
setValue('zoom', 1);
check('and back to 1x', $('screen').style.width === '666px', $('screen').style.width);

// The one thing about the letterbox that can be checked without a layout engine.
// At 1x in a wide window there is a large area beside the canvas, and it must be
// the machine's panel colour -- black beside the black the canvas draws reads as a
// hole, and so would the page background, which is darker than the box it sits in.
// jsdom cannot resolve `var(--panel)` through getComputedStyle, so this reads the
// rule itself rather than the computed style.
const wrapRule = /\.screenwrap\s*\{([^}]*)\}/.exec(html)[1];
check('the area beside the canvas is the panel colour, not a hard-coded black',
      /background:\s*var\(--panel\)/.test(wrapRule) && !/#000/.test(wrapRule),
      wrapRule.trim());
check('and the canvas is inset, so the panel shows as a bezel on every side',
      /padding:\s*6px/.test(wrapRule), wrapRule.trim());
check('and the canvas sits in a box of its own size, inside the panel',
      $('screen').parentNode.className === 'screenbox' &&
      $('screen').parentNode.parentNode.className === 'screenwrap',
      $('screen').parentNode.className + ' in ' +
      $('screen').parentNode.parentNode.className);

// The window's home is buffer column 0, row 0 -- which is where the ROM puts it
// (VFLO = -22 cancels osborne1.cpp's 0x0b of horizontal blanking), and NOT column
// 11, which is what evaluating that driver constant at scroll zero looks like.
check('the viewport defaults to home: column 0, row 0',
      $('vpcol').value === '0' && $('vprow').value === '0' &&
      $('viewportBox').style.left === '0%' && $('viewportBox').style.top === '0%',
      $('vpcol').value + ',' + $('vprow').value + ' css ' +
      $('viewportBox').style.left + ',' + $('viewportBox').style.top);
setValue('vpcol', 11);
check('the origin field moves the viewport',
      $('viewportBox').style.left !== '0%', $('viewportBox').style.left);
clickOn('vpstock');
check('the home button puts it back at (0,0)',
      $('vpcol').value === '0' && $('viewportBox').style.left === '0%',
      $('vpcol').value + ' ' + $('viewportBox').style.left);
check('and the status explains why home is column 0, not 11',
      /VFLO/.test(status()) && /column 0/.test(status()), status());

// --- 2. click a cell, then type -------------------------------------------
section('click a cell, then type');
clickCell(0, 0);
type('p');
let st = status();
let f = currentFrames();
check('typing "p" writes glyph 0x70 at the cell',
      f[0].cells[0] === 0x70, 'got 0x' + S.hex(f[0].cells[0], 2));
check('and the cell is bright', f[0].attrs[0] === 1);
check('and the status named the glyph', /glyph 0x70/.test(st), st);

type('A');
st = status();
f = currentFrames();
check('typing "A" writes a capital A \u2014 glyph 0x41, the thing the ROM could not author',
      f[0].cells[1] === 0x41, 'got 0x' + S.hex(f[0].cells[1], 2));
check('and the status calls it a character glyph', /0x41 \(character\)/.test(st), st);

type(' ');
f = currentFrames();
check('space writes the blank', f[0].cells[2] === 0x20,
      'got 0x' + S.hex(f[0].cells[2], 2));

pickRadio('keys', 'sui65');
type('A');
st = status();
f = currentFrames();
check('with graphical characters the same key types the block glyph 0x00',
      f[0].cells[3] === 0x00, 'got 0x' + S.hex(f[0].cells[3], 2));

pickRadio('keys', 'direct');
pickRadio('bright', 'dim');
type('p');
f = currentFrames();
check('the dim pen writes the glyph but clears the ninth bit',
      f[0].cells[4] === 0x70 && f[0].attrs[4] === 0,
      'cell 0x' + S.hex(f[0].cells[4], 2) + ', attr ' + f[0].attrs[4]);

// --- 3. the palette, and the cells that are not the designer's -------------
section('the palette, and the trailer');
// The hatch is a graphical block, so it lives in the graphical palette; the pen
// survives the switch back, which is what "fill with pen" needs.
pickRadio('keys', 'sui65');
swatchFor(0x7F).click();
check('clicking the hatch swatch selects glyph 0x7F', /glyph 0x7F/.test(status()), status());
pickRadio('keys', 'direct');
// A cell click aims by default.  It must NOT paint, or click-then-type lands a
// cell to the right of where you clicked -- which is the whole complaint.
clickCell(5, 10);
const aimStatus = status();
f = currentFrames();
check('a cell click only aims, it does not paint the palette glyph',
      f[0].cells[5 * S.COLS + 10] === S.BLANK,
      '0x' + S.hex(f[0].cells[5 * S.COLS + 10], 2));
check('and the status says it is aiming',
      /type a key to place a glyph/.test(aimStatus), aimStatus);
$('paintOnClick').checked = true;
$('paintOnClick').dispatchEvent(new window.Event('change', { bubbles: true }));
clickCell(5, 10);
f = currentFrames();
check('with paint-on-click ticked, a click does paint it there',
      f[0].cells[5 * S.COLS + 10] === 0x7F,
      '0x' + S.hex(f[0].cells[5 * S.COLS + 10], 2));
$('paintOnClick').checked = false;
$('paintOnClick').dispatchEvent(new window.Event('change', { bubbles: true }));
clickCell(31, 120);
type('p');
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
      f[0].cells[0] === 0x70 && f[0].cells[1] === 0x41 &&
      f[0].cells[5 * S.COLS + 10] === 0x7F && f[0].attrs[4] === 0);

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
const txtStatus = status();
const txt = lastBytes();
check('the art text is 32 lines of 128 characters and a trailing newline',
      txt.length === 32 * 129, txt.length + ' bytes');
const art = S.parseArtText(String.fromCharCode.apply(null, txt));
check('nothing in it is unreadable', art.unknown.length === 0, art.unknown.join(' '));
f = currentFrames();
// Art text is read with `sui 65`, so it cannot carry a cell holding glyph
// 0x41-0x61 -- and this frame has a capital in it, typed with standard characters.
const lossy = S.artTextLossy(f[0].cells);
let artDiff = 0, artOutside = 0;
for (let i = 0; i < S.FRAME; i++) {
  if (S.isReserved(i) || art.cells[i] === f[0].cells[i]) continue;
  artDiff++;
  if (lossy.indexOf(i) < 0) artOutside++;
}
check('the .txt reads back to the glyphs on screen, except the lossy ones',
      artOutside === 0 && artDiff === lossy.length && lossy.length > 0,
      artDiff + ' differ, ' + lossy.length + ' reported as lossy');
check('and the export warned rather than exporting them silently',
      /0x41-0x61/.test(txtStatus), txtStatus);

function sameGlyphs(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

// --- 7. the .gif ----------------------------------------------------------
// The images are exported at the zoom's dot scale, so pin the zoom to 2x to match
// what this section expects -- the page's own default is 1x.
setValue('zoom', 2);
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

  // --- 9. copy forward, with an offset ------------------------------------
  section('copy forward, with an offset');
  // The import left exactly one frame.  Put a glyph in it, then move the screen.
  // The pen toggle, self-contained: a standard character, picked and then cleared.
  const penSwatch = swatchFor(0x41);
  penSwatch.click();
  check('clicking a swatch makes it the pen', /pen is glyph 0x41/.test(status()), status());
  penSwatch.click();
  check('clicking the selected swatch again clears the pen',
        /pen cleared/.test(status()), status());
  clickCell(0, 0);
  type('p');
  setValue('copyFrom', 'screen');
  setValue('copyDx', 4);
  setValue('copyDy', 2);
  clickOn('copyNext');
  check('copy adds a frame when there is no next one',
        $('frameCount').textContent === '2 / 2', $('frameCount').textContent);
  const copyStatus = status();
  const fr = currentFrames();
  check('the new frame is the old one, moved four right and two down',
        fr.length === 2 && fr[1].cells[2 * S.COLS + 4] === 0x70 &&
        fr[1].cells[0] === S.BLANK,
        '0x' + S.hex(fr[1].cells[2 * S.COLS + 4], 2) + ' where it landed, 0x' +
        S.hex(fr[1].cells[0], 2) + ' where it was');
  check('and the status says what it did',
        /moved the screen by \(\+4, \+2\)/.test(copyStatus), copyStatus);
  const dd = S.frameDiff(fr[0].cells, fr[0].attrs, fr[1].cells, fr[1].attrs);
  check('the diff is 2 cells, not 4096 -- which is the whole point',
        dd.cells === 2, dd.cells + ' cells');
  check('and the readout says so', /2 of 4088 cells differ/.test($('diffHint').textContent),
        $('diffHint').textContent);
  // With a next frame already there, it copies into it rather than adding one.
  clickOn('prev');
  clickOn('copyNext');
  check('with a next frame present it copies into that one instead',
        $('frameCount').textContent === '2 / 2', $('frameCount').textContent);

  // --- 10. the clipboard, and the ninth bit -------------------------------
  section('the clipboard, and the ninth bit');
  clickOn('first');
  clickOn('pasteSel');
  check('paste with an empty clipboard says so',
        /clipboard is empty/.test(status()), status());

  dragSelect(0, 0, 0, 1);
  check('dragging makes a selection and the hint says how big',
        /selection: 2\u00d71/.test($('selHint').textContent), $('selHint').textContent);
  clickOn('copySel');
  const copyMsg = status();
  check('copy reports the rectangle', /copied 2\u00d71/.test(copyMsg), copyMsg);
  check('and the hint knows the clipboard is not empty',
        /clipboard: 2\u00d71/.test($('selHint').textContent), $('selHint').textContent);

  clickCell(5, 5);
  clickOn('pasteSel');
  check('paste lands at the cursor', /pasted 2\u00d71 at row 5, column 5/.test(status()), status());
  let cf = currentFrames();
  check('the glyph came back, and so did the blank',
        cf[0].cells[5 * S.COLS + 5] === 0x70 && cf[0].cells[5 * S.COLS + 6] === S.BLANK,
        '0x' + S.hex(cf[0].cells[5 * S.COLS + 5], 2) + ' / 0x' +
        S.hex(cf[0].cells[5 * S.COLS + 6], 2));

  // Tab flips the ninth bit without the glyph being touched.  Assert against what
  // the cell actually was, since the pen's brightness has been changed by earlier
  // sections and this is about the *flip*, not about a particular state.
  clickCell(5, 5);
  cf = currentFrames();
  const wasDim = cf[0].attrs[5 * S.COLS + 5] === 0;
  type('Tab');
  check('Tab names the state it flipped to',
        new RegExp('now ' + (wasDim ? 'bright' : 'dim')).test(status()), status());
  cf = currentFrames();
  check('the ninth bit is the opposite of what it was, and the glyph is untouched',
        cf[0].attrs[5 * S.COLS + 5] === (wasDim ? 1 : 0) &&
        cf[0].cells[5 * S.COLS + 5] === 0x70,
        'was ' + (wasDim ? 'dim' : 'bright') + ', now attr ' + cf[0].attrs[5 * S.COLS + 5] +
        ', cell 0x' + S.hex(cf[0].cells[5 * S.COLS + 5], 2));
  type('Tab');
  cf = currentFrames();
  check('and Tab again flips it back', cf[0].attrs[5 * S.COLS + 5] === (wasDim ? 0 : 1),
        'attr ' + cf[0].attrs[5 * S.COLS + 5]);

  // The usual keys, on a selection.
  dragSelect(5, 5, 5, 6);
  typeMod('x');
  check('Ctrl-X cuts', /cut 2\u00d71/.test(status()), status());
  cf = currentFrames();
  check('and blanks what it took', cf[0].cells[5 * S.COLS + 5] === S.BLANK);
  clickCell(8, 8);
  typeMod('v');
  cf = currentFrames();
  check('Ctrl-V pastes it somewhere else',
        cf[0].cells[8 * S.COLS + 8] === 0x70,
        '0x' + S.hex(cf[0].cells[8 * S.COLS + 8], 2));
  check('and the cut cell is still blank where it was',
        cf[0].cells[5 * S.COLS + 5] === S.BLANK);

  finish();
}()).catch(function (e) {
  console.log('  FAIL  the tail threw: ' + ((e && e.stack) || e));
  finish();
});
