/* bootsplash core -- the Osborne 1 glyphs, the frame format, and the renderers.
 *
 * WHY THIS IS A SEPARATE FILE
 *     It has no DOM in it, so `selftest.js` can require it under node and check
 *     it against the repo's own tooling.  `bootsplash.html` loads it as a classic
 *     script (not a module) so the whole thing works from `file://` with no
 *     server, which is the point of a browser tool.
 *
 * THE GLYPHS
 *     From the character generator ROM in socket UA15 -- `char.ua15`, 2048 bytes,
 *     CRC32 5297c109 -- embedded below.  Its layout is *not* glyph-contiguous:
 *
 *         byte = rom[row * 128 + code]        bit 7 = leftmost of 8
 *
 *     10 rows x 128 glyphs = 1280 bytes; the rest of the 2 KiB is 0xFF.  That is
 *     MAME's `osborne1` driver and `tools/romfont.py`, which are the authorities
 *     this project already cites.  The CRC is asserted at load, so a corrupted or
 *     swapped embed is loud rather than subtle.
 *
 * THE FRAME (docs/rom-pico-protocol.md sections 4 and 5)
 *     8192 bytes: two 4096-byte halves, characters then attributes, each half one
 *     window page with its own trailer at its own 0FF8h:
 *
 *         half[0000h..0FF7h]  the body -- 4096 cells, 128 x 32
 *         half[0FF8h..0FFDh]  'O1NEXT', six bytes of magic
 *         half[0FFEh..0FFFh]  the 16-bit sum of the 4088 body bytes, little-endian
 *
 *     A cell in the character half is a **glyph code**, not a character: the ROM's
 *     loader does `sui 65` over the art, so 0x41-0x61 is graphics (code = char-65)
 *     and everything else printable is its own code.  A cell in the attribute half
 *     is the 4Kx1 array's own image -- bit 7 set is bright, and the low seven bits
 *     read high because they are not physically present, so bright is FFh and dim
 *     is 7Fh (docs/rom-pico-protocol.md section 4.1 step 2: "24 read 7Fh, which is
 *     dim").
 *
 * THE ANIMATION CONTAINER
 *     #247's W5 hands the pacing to the RP2354B, so the asset becomes a *sequence*
 *     of frames: the RP2354B is the display, it paces them from its own flash, and
 *     it stops on the Z80's first video-RAM write.  The container is a 32-byte
 *     header and then the frames back to back, and it is the firmware's contract
 *     now rather than a proposal -- `firmware/rom-service/bootsplash.bin` is the
 *     first instance of it.  Its flags byte carries the playback mode: bit 0
 *     repeats, bit 1 bounces, so all four combinations are a mode, and
 *     `playbackOrder` is the one place that says what each one plays.
 */
(function (root) {
  'use strict';

  // --- the character generator ROM (tools/emulator-setup/roms/char.ua15) -----
  var CHAR_ROM_B64 = '//APDw//AACAAAE8PADwAAD/8MAP////AP/wADzAPDwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADD8A8PD/8AAMAAAzw8APAAAP/wxg9///8A/vAAPMY8PAAYZiQYJjgMDDAIAAAAAAI8GDw8DH48fjw8AAAMADA8PDx8PHx+fjxmPAZmYGNmPHw8fDx+ZmZjZmZ+PkA+GAAwAGAABgAeAGAAAGAwAAAAAAAAADAAAAAAAAAeGHAAKsPwDw8P/wAA4AAHPDw88AAA//DMDz///wD88AA8zDw8ADxmJD52bAgYGCoAAAAABmY4ZmZsYGYGZmYYGBgAGGZCZmZmZmBgZmYYBmxgd2ZmZmZmZhhmZmNmZkYwYAY8ABAAYAAGADAAYBgMYBgAAAAAAAAAMAAAAAAAADAYGDBUw/APDw//AADwPw88/37w//z/8NgPH///APjw/z/Y//wAPAB+WCxsEDAMHBgAAAAMZhgMBmxgYAxmZhgYMH4MBk5mZmBmYGBgZhgGeGB/dmZmZmZgGGZmazxmDDAwBmYACDx8PD48fDx8AABmGGNcPDw8XDx4ZmZjZmZ+MBgYWirD8A8PD/8AAPA/Dzz/fvD//P/wMw8f//8A+PD/PzD//AAYACQ4GDgAMAw+GAB+ABhuGDgcbHx8GDw+AABgAAYMVn58YGZ4eG5+GAZwYGt+ZnxmfDwYZmZrGDwYMBgGQgAABmZmZmYwZmYYDGwYd2ZmZmZmYDBmZmMsZgZgAA4MVMPw8P8PD/AP+D8fPP9+D//88ABrAA//AP/w//8/bv/8ABgAfho0bQAwDBx+AH4AMHYYYAZ+BmYwZgYAADB+DBhcZmZgZmBgZmYYBnhga25mYGZmBhhmPH88GDAwDAYAAAA+ZmBmfjBmZhgMeBhrZmZmZmA8MGZmaxhmGDAYGAAqw/Dw/w8P8A/4Px88/34P//zwANsAD/8A//D//z/D//wAAAAkfG5mABgYKhgYABhgZhhgZgxmZjBmZhgYGAAYAEBmZmZmYGBmZhhmbGBjZmZgdmZmGGY8f2YYYjAGBgAAAGZmZmZgMGZmGAxsGGNmZmZmYAY0Zjw+NGZgMBgYAFTD8PD/Dw/wD/w8Pzw8PA88PPAAPwAH/wD/4P8AAAYAAAAYACQYZD8ADDAIGBgAGEA8PH48DDw8MDw8GBgMADAYPGZ8PHx+YDxmPDxmfmNmPGA8ZjwYPBg2Zhh+PgI+AH4APHw8PjwwPmY8DGYMY2Y8fD5gPBw6GDZmPn4eGHAAKsPw8P8PD/AP/jx/PDwADzw88AADAAP/AP/A/wAAGAAAAAAAAAAAAwAAAAAACAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAGAABsAAAAAABgBgAAAAAAAAAGAAAAAABU//Dw/w8P8A//PP88PAAPPDzwAAMAAf8A/4D/AAA/AAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAADwAADgAAAAAAGAHAAAAAAAAADwAAAAAAAD//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wY=';
  var CHAR_ROM_CRC32 = 0x5297c109;
  var CHAR_ROM_LEN = 2048;

  // --- the screen: 128 x 32 cells, one window page ---------------------------
  var COLS = 128, ROWS = 32;
  var CELL_W = 8, CELL_H = 10;
  var FRAME = COLS * ROWS;                 // 4096
  var VISIBLE_ROWS = 24;                   // rows 24-31 are never shown

  // The viewport -- what the machine actually puts on the glass.  The buffer is
  // 128 x 32; the *window* onto it is 52, 80 or 104 columns of 24 rows, and the
  // three widths are the same physical screen with narrower dots (SCREEN-PAC).
  var VIEWPORT_WIDTHS = [52, 80, 104];
  var VIEWPORT_ROWS = 24;

  // --- the frame's trailer ---------------------------------------------------
  var MAGIC = 'O1NEXT';
  var TRAILER_AT = FRAME - 8;              // 0FF8h -- 4088
  var ATTR_BRIGHT = 0xFF, ATTR_DIM = 0x7F;

  // --- the animation container ----------------------------------------------
  var ANIM_MAGIC = 'O1SPLASH';
  var ANIM_HEADER = 32;
  var ANIM_VERSION = 1;

  // The header's flags byte is two *independent* bits, because they answer two
  // different questions and a reader can test either one alone:
  //
  //     bit 0  LOOP      does it repeat at all?
  //     bit 1  PINGPONG  does it reverse at the ends instead of jumping?
  //
  // so all four combinations are a mode, and all four are offered:
  //
  //     flags 0   once            1 2 3        stop
  //     flags 1   loop            1 2 3 1 2 3  ... repeating
  //     flags 2   pingpong-once   1 2 3 2 1    stop
  //     flags 3   pingpong        1 2 3 2 1 2 3 2 ... repeating
  //
  // The two ping-pongs differ in exactly one frame, and it is the one that matters:
  // a bounce *ends* where it started, so the one-shot plays the return to frame 1
  // and stops there, while the repeating one leaves that return to the wrap into the
  // next cycle and stops nowhere.
  var ANIM_LOOP = 0x01;
  var ANIM_PINGPONG = 0x02;

  // --- the graphics set, reached by the ROM's own `sui 65` ------------------
  var GRAPHICS_FIRST = 0x41, GRAPHICS_LAST = 0x61;
  var ART_OFFSET = 65;
  var BLANK = 0x20;                        // the blank cell, reached as 'a'
  var HATCH_CODE = 0x7F;                   // the 0x7F hatch, reached as U+00C0
  var HATCH_CHAR = 0xC0;

  // --- crc32 ----------------------------------------------------------------
  var CRC_TABLE = (function () {
    var t = new Uint32Array(256), c, i, k;
    for (i = 0; i < 256; i++) {
      c = i;
      for (k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      t[i] = c >>> 0;
    }
    return t;
  })();

  function crc32(bytes) {
    var c = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++)
      c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  // --- base64 ---------------------------------------------------------------
  function b64ToBytes(s) {
    if (typeof Buffer !== 'undefined')
      return new Uint8Array(Buffer.from(s, 'base64'));
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  var ROM = b64ToBytes(CHAR_ROM_B64);

  function romCrc32() { return crc32(ROM); }
  function romOk() { return ROM.length === CHAR_ROM_LEN && romCrc32() === CHAR_ROM_CRC32; }

  function hex(n, width) {
    var s = (n >>> 0).toString(16).toUpperCase();
    while (s.length < (width || 4)) s = '0' + s;
    return s;
  }

  // One dot of one glyph.  `code` is a glyph code, not a character.
  function glyphDot(code, row, col) {
    return (ROM[row * 128 + (code & 0x7F)] >> (7 - col)) & 1;
  }

  function glyphBits(code) {
    var out = new Uint8Array(CELL_W * CELL_H), i = 0;
    for (var r = 0; r < CELL_H; r++)
      for (var c = 0; c < CELL_W; c++) out[i++] = glyphDot(code, r, c);
    return out;
  }

  // The graphics palette, in the order the art sheet draws it: A..Z, [ \ ] ^ _ `,
  // a (the blank), then the 0x7F hatch -- 34 cells, glyph = character - 65.
  var GRAPHICS_KEYS = (function () {
    var keys = [];
    for (var c = GRAPHICS_FIRST; c <= GRAPHICS_LAST; c++)
      keys.push({ glyph: c - ART_OFFSET, key: String.fromCharCode(c), code: c });
    keys.push({ glyph: HATCH_CODE, key: '\u00C0', code: HATCH_CHAR });
    return keys;
  })();

  // --- the `sui 65` mapping, both ways --------------------------------------
  //
  // This is the ROM's own arithmetic, and it is what makes the app's output the
  // machine's rather than an approximation.  The cost is documented and real: a
  // capital letter IS a glyph index, so `A`-`Z`, `[ \ ] ^ _ \`` and `a` cannot be
  // typed as text -- they select graphics.  That is why ROM 2.0's captions are
  // lowercase (research/boot-screen/README.md).

  function glyphForArtChar(o) {
    if (o >= GRAPHICS_FIRST && o <= GRAPHICS_LAST) return o - ART_OFFSET;
    if (o === HATCH_CHAR) return HATCH_CODE;
    if (o >= 0x20 && o <= 0x7E) return o;
    return null;
  }

  function artCharForGlyph(g) {
    g &= 0x7F;
    if (g <= BLANK) return String.fromCharCode(g + ART_OFFSET);
    if (g === HATCH_CODE) return '\u00C0';
    return String.fromCharCode(g);
  }

  // The glyphs a pen mode works in.  The palette shows *this*, so it shows what the
  // mode can actually place and nothing else:
  //
  //   standard characters  -- everything a key can type, 0x20-0x7E (95 glyphs)
  //   graphical characters -- the 32 block glyphs, the blank, and the 0x7F hatch
  //                           (34 glyphs: exactly the cells tools/romfont.py's art
  //                           sheet draws, and exactly the `sui 65` range)
  //
  // Between them they cover all 128 of the character ROM.  0x20 is in both, because
  // the space bar types the blank in either mode.
  function paletteSet(mode) {
    var out = [], g;
    if (mode === 'sui65') {
      for (g = 0; g <= BLANK; g++) out.push(g);
      out.push(HATCH_CODE);
      return out;
    }
    for (g = 0x20; g <= 0x7E; g++) out.push(g);
    return out;
  }

  // Which glyph a keystroke places.  Two modes, and the difference between them is
  // only 0x41-0x61:
  //
  //   'direct'  the key's own code *is* the glyph: 'A' draws a capital A, 'p' draws
  //             a p, space draws the blank.  This is what the machine's hardware
  //             does -- a cell is a glyph code and the chargen is indexed with
  //             `chr & 0x7f` -- and it is the default, because this tool writes
  //             frames directly.  There is no assembler in the path.
  //
  //   'sui65'   the ROM's *art loader* arithmetic: 0x41-0x61 becomes glyphs
  //             0x00-0x20, everything else printable is itself.  It exists for one
  //             reason -- art text (research/boot-screen/README.md) is read by
  //             `sui 65`, so a screen authored in this mode is one whose .txt
  //             export `rom2strokes.py` can read back.  The cost is that a capital
  //             cannot be typed as a letter in this mode, which is precisely the
  //             limitation the *frame* never had.
  //
  // Both modes are total over the printable range, so neither one refuses a key.
  // The 32 block glyphs (0x00-0x1F) and the 0x7F hatch have no printable key in
  // either mode and are picked from the palette, which is why that palette shows
  // the whole ROM rather than a sample of it.
  function glyphForKey(code, mode) {
    if (mode === 'sui65') {
      if (code >= GRAPHICS_FIRST && code <= GRAPHICS_LAST) return code - ART_OFFSET;
      if (code === HATCH_CHAR) return HATCH_CODE;
    }
    if (code >= 0x20 && code <= 0x7E) return code;
    return null;
  }

  // The key that *reaches* a glyph, for labelling the palette -- or null when no
  // key does.  Note the asymmetry with `artCharForGlyph`: that one says what art
  // text *writes* for a glyph, and for 0x41-0x61 it writes a character that reads
  // back as a *different* glyph.  This one says what actually gets you there, and
  // in `sui 65` mode the answer for 0x41-0x61 is nothing at all.
  function keyForGlyph(g, mode) {
    g &= 0x7F;
    if (mode === 'sui65') {
      if (g <= BLANK) return String.fromCharCode(g + ART_OFFSET);
      if (g === HATCH_CODE) return '\u00C0';
      if (g >= GRAPHICS_FIRST && g <= GRAPHICS_LAST) return null;
    }
    if (g >= 0x20 && g <= 0x7E) return String.fromCharCode(g);
    return null;
  }

  function isGraphicsGlyph(g) { g &= 0x7F; return g <= BLANK || g === HATCH_CODE; }

  // --- blank cells and the attribute plane ---------------------------------
  function blankCells() {
    var c = new Uint8Array(FRAME);
    c.fill(BLANK);
    return c;
  }

  function brightAttrs() {
    var a = new Uint8Array(FRAME);
    a.fill(1);
    return a;
  }

  // Row 31, columns 120-127 are the trailer's eight cells -- off-screen, and the
  // one part of the buffer the designer must not paint.
  function isReserved(index) {
    var r = Math.floor(index / COLS), c = index % COLS;
    return r === ROWS - 1 && c >= COLS - 8;
  }

  // --- the frame ------------------------------------------------------------
  function seal(body) {
    if (body.length !== TRAILER_AT)
      throw new Error('a half is ' + TRAILER_AT + ' bytes of body, got ' + body.length);
    var out = new Uint8Array(FRAME);
    out.set(body, 0);
    for (var i = 0; i < MAGIC.length; i++) out[TRAILER_AT + i] = MAGIC.charCodeAt(i);
    var s = 0;
    for (var j = 0; j < TRAILER_AT; j++) s = (s + body[j]) & 0xFFFF;
    out[FRAME - 2] = s & 0xFF;
    out[FRAME - 1] = s >>> 8;
    return out;
  }

  function checkHalf(half) {
    if (half.length !== FRAME)
      return { ok: false, why: 'a half is ' + FRAME + ' bytes, got ' + half.length };
    for (var i = 0; i < MAGIC.length; i++)
      if (half[TRAILER_AT + i] !== MAGIC.charCodeAt(i))
        return { ok: false, why: 'no ' + MAGIC + ' magic at 0FF8h' };
    var s = 0;
    for (var j = 0; j < TRAILER_AT; j++) s = (s + half[j]) & 0xFFFF;
    var want = half[FRAME - 2] | (half[FRAME - 1] << 8);
    if (s !== want)
      return { ok: false, why: 'the trailer says ' + hex(want) +
                              ', the body sums to ' + hex(s) };
    return { ok: true, sum: s };
  }

  function buildFrame(cells, attrs) {
    var ch = new Uint8Array(TRAILER_AT), at = new Uint8Array(TRAILER_AT);
    for (var i = 0; i < TRAILER_AT; i++) {
      ch[i] = cells[i] & 0x7F;
      at[i] = attrs[i] ? ATTR_BRIGHT : ATTR_DIM;
    }
    var out = new Uint8Array(FRAME * 2);
    out.set(seal(ch), 0);
    out.set(seal(at), FRAME);
    return out;
  }

  // `(ok, message)` -- the monitor's own test, and nothing more (section 6: a
  // missing frame, an erased frame and a corrupt one are the same case).
  function checkFrame(bytes) {
    if (bytes.length !== FRAME * 2)
      return { ok: false, why: 'a frame is ' + (FRAME * 2) + ' bytes, got ' + bytes.length };
    var chars = checkHalf(bytes.subarray(0, FRAME));
    var attrs = checkHalf(bytes.subarray(FRAME, FRAME * 2));
    if (!chars.ok) return { ok: false, why: 'character half: ' + chars.why };
    if (!attrs.ok) return { ok: false, why: 'attribute half: ' + attrs.why };
    return { ok: true, chars: chars.sum, attrs: attrs.sum };
  }

  function parseFrame(bytes) {
    var res = checkFrame(bytes);
    var cells = new Uint8Array(FRAME), attrs = new Uint8Array(FRAME);
    for (var i = 0; i < TRAILER_AT; i++) {
      cells[i] = bytes[i] & 0x7F;
      attrs[i] = (bytes[FRAME + i] & 0x80) ? 1 : 0;
    }
    // The trailer's own eight cells are not the designer's; keep them blank and
    // bright in the editor, since buildFrame re-writes them on the way out.
    for (var j = TRAILER_AT; j < FRAME; j++) { cells[j] = BLANK; attrs[j] = 1; }
    return { ok: res.ok, why: res.why, cells: cells, attrs: attrs };
  }

  // --- the animation container ----------------------------------------------
  //
  //   offset  bytes  what
  //     0       8    'O1SPLASH'
  //     8       1    version (1)
  //     9       1    flags -- bit 0 = loop, bit 1 = ping-pong
  //    10       2    width   (u16 LE, 128)
  //    12       2    height  (u16 LE, 32)
  //    14       2    fps     (u16 LE)
  //    16       4    frames  (u32 LE)
  //    20       4    body    (u32 LE = frames * 8192)
  //    24       2    header sum (u16 LE over bytes 0..23)
  //    26       6    reserved, zero
  //    32       N*8192   the frames, back to back, each already sealed
  //
  // The frames are not re-sealed and not re-ordered: a frame is byte-identical to
  // the 8192 bytes the machine's own trailer test accepts, whatever wrote it.

  function u16(bytes, at, v) { bytes[at] = v & 0xFF; bytes[at + 1] = (v >>> 8) & 0xFF; }
  function u32(bytes, at, v) {
    bytes[at] = v & 0xFF; bytes[at + 1] = (v >>> 8) & 0xFF;
    bytes[at + 2] = (v >>> 16) & 0xFF; bytes[at + 3] = (v >>> 24) & 0xFF;
  }
  function r16(bytes, at) { return bytes[at] | (bytes[at + 1] << 8); }
  function r32(bytes, at) {
    return (bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) |
            (bytes[at + 3] << 24)) >>> 0;
  }

  function headerSum(bytes) {
    var s = 0;
    for (var i = 0; i < 24; i++) s = (s + bytes[i]) & 0xFFFF;
    return s;
  }

  // --- the playback mode -----------------------------------------------------
  //
  // A mode is one of four words, and this is the only place the words and the two
  // bits are tied together.  A boolean is still accepted, because that is what this
  // container had before ping-pong existed and it costs one line to keep every older
  // caller working: `true` is 'loop'.
  var MODES = ['once', 'loop', 'pingpong-once', 'pingpong'];

  function playbackMode(mode) {
    if (mode === true) return 'loop';
    if (mode === false || mode === undefined || mode === null) return 'once';
    return MODES.indexOf(mode) >= 0 ? mode : 'once';
  }

  // Does it go round again?  This is bit 0, and it is the one question the preview
  // timer, the GIF's loop flag and the diff all have to ask -- and the answer is not
  // "is the mode 'once'", because a one-shot bounce also stops.
  function modeRepeats(mode) {
    mode = playbackMode(mode);
    return mode === 'loop' || mode === 'pingpong';
  }

  function modeFlags(mode) {
    mode = playbackMode(mode);
    if (mode === 'loop') return ANIM_LOOP;
    if (mode === 'pingpong') return ANIM_LOOP | ANIM_PINGPONG;
    if (mode === 'pingpong-once') return ANIM_PINGPONG;
    return 0;
  }

  function modeFromFlags(flags) {
    if (flags & ANIM_PINGPONG)
      return (flags & ANIM_LOOP) ? 'pingpong' : 'pingpong-once';
    return (flags & ANIM_LOOP) ? 'loop' : 'once';
  }

  // The frames a mode plays, in order, as indices into the animation -- everything it
  // shows, whether it repeats or not.  'once' and 'loop' are the animation itself;
  // a bounce is the animation and then the way back, and the ends appear once each
  // rather than twice, because the frames a bounce *turns on* are the ones it plays,
  // not the ones it reverses from.
  //
  // The two ping-pongs differ in one entry, and it is the difference between
  // "1 2 3 2 1, stop" and "1 2 3 2, round again": the one-shot comes back to the
  // first frame and stops there, and the repeating one hands that return to the wrap
  // into the next cycle.  Two frames are 0,1,0 and 0,1; one frame is 0 either way.
  //
  // The preview, the GIF and the diff all read the order from here, so the tool
  // cannot disagree with itself about what a mode plays.
  function playbackOrder(count, mode) {
    mode = playbackMode(mode);
    var out = [], i;
    if (count <= 0) return out;
    for (i = 0; i < count; i++) out.push(i);
    if (mode === 'pingpong-once')
      for (i = count - 2; i >= 0; i--) out.push(i);
    else if (mode === 'pingpong')
      for (i = count - 2; i >= 1; i--) out.push(i);
    return out;
  }

  function buildAnimation(frames, fps, mode) {
    var n = frames.length;
    if (!n) throw new Error('an animation needs at least one frame');
    var out = new Uint8Array(ANIM_HEADER + n * FRAME * 2);
    for (var i = 0; i < ANIM_MAGIC.length; i++) out[i] = ANIM_MAGIC.charCodeAt(i);
    out[8] = ANIM_VERSION;
    out[9] = modeFlags(mode);
    u16(out, 10, COLS);
    u16(out, 12, ROWS);
    u16(out, 14, fps);
    u32(out, 16, n);
    u32(out, 20, n * FRAME * 2);
    u16(out, 24, headerSum(out));
    for (var k = 0; k < n; k++) out.set(frames[k], ANIM_HEADER + k * FRAME * 2);
    return out;
  }

  function parseAnimation(bytes) {
    if (bytes.length < ANIM_HEADER)
      return { ok: false, why: 'shorter than the ' + ANIM_HEADER + '-byte header' };
    for (var i = 0; i < ANIM_MAGIC.length; i++)
      if (bytes[i] !== ANIM_MAGIC.charCodeAt(i))
        return { ok: false, why: 'no ' + ANIM_MAGIC + ' magic' };
    if (bytes[8] !== ANIM_VERSION)
      return { ok: false, why: 'container version ' + bytes[8] + ', this tool reads ' +
                               ANIM_VERSION };
    var want = r16(bytes, 24), got = headerSum(bytes);
    if (want !== got)
      return { ok: false, why: 'the header says ' + hex(want) +
                               ', it sums to ' + hex(got) };
    var w = r16(bytes, 10), h = r16(bytes, 12);
    if (w !== COLS || h !== ROWS)
      return { ok: false, why: 'the header says ' + w + 'x' + h + ', this tool is ' +
                               COLS + 'x' + ROWS };
    var n = r32(bytes, 16), body = r32(bytes, 20);
    if (body !== n * FRAME * 2)
      return { ok: false, why: 'the body is ' + body + ' bytes, ' + n + ' frames is ' +
                               (n * FRAME * 2) };
    if (bytes.length !== ANIM_HEADER + body)
      return { ok: false, why: 'the file is ' + bytes.length + ' bytes, the header says ' +
                               (ANIM_HEADER + body) };
    var frames = [];
    for (var k = 0; k < n; k++) {
      var off = ANIM_HEADER + k * FRAME * 2;
      frames.push(bytes.subarray(off, off + FRAME * 2));
    }
    return { ok: true, version: bytes[8], flags: bytes[9],
             mode: modeFromFlags(bytes[9]),
             loop: !!(bytes[9] & ANIM_LOOP),
             pingpong: !!(bytes[9] & ANIM_PINGPONG),
             fps: r16(bytes, 14), frames: frames };
  }

  // --- the art text form ----------------------------------------------------
  //
  // One character per cell, in the repo's own authoring convention
  // (research/boot-screen/o1next-art.txt): A-a is graphics, everything else
  // printable is itself.  Written as latin-1, which is how `rom2strokes.py`'s
  // load_art reads it -- a UTF-8 U+00C0 would arrive as two bytes and be dropped.

  function artText(cells) {
    var lines = [];
    for (var r = 0; r < ROWS; r++) {
      var line = '';
      for (var c = 0; c < COLS; c++) line += artCharForGlyph(cells[r * COLS + c]);
      lines.push(line);
    }
    return lines.join('\n') + '\n';
  }

  function artTextBytes(cells) {
    var text = artText(cells);
    var out = new Uint8Array(text.length);
    for (var i = 0; i < text.length; i++) out[i] = text.charCodeAt(i) & 0xFF;
    return out;
  }

  // Art text is one character per cell with no escape, and 0x41-0x61 *is* the
  // graphics range -- so a cell holding the glyph code 0x41..0x61 cannot be
  // written as art and read back.  Only a foreign .bin can put one there (the
  // app's own pens refuse those keys), so the exporter asks this and says so
  // rather than silently exporting something that will not return.
  function artTextLossy(cells) {
    var bad = [];
    for (var i = 0; i < FRAME; i++) {
      var g = cells[i] & 0x7F;
      if (g >= GRAPHICS_FIRST && g <= GRAPHICS_LAST) bad.push(i);
    }
    return bad;
  }

  function parseArtText(text) {
    var lines = text.split(/\r?\n/).filter(function (l) { return l.length > 0; });
    var cells = blankCells();
    var unknown = {}, rows = 0;
    for (var r = 0; r < Math.min(lines.length, ROWS); r++) {
      rows = r + 1;
      var line = lines[r];
      for (var c = 0; c < Math.min(line.length, COLS); c++) {
        var g = glyphForArtChar(line.charCodeAt(c));
        if (g === null) { unknown[line[c]] = 1; continue; }
        if (!isReserved(r * COLS + c)) cells[r * COLS + c] = g;
      }
    }
    return { cells: cells, rows: rows, sourceLines: lines.length,
             unknown: Object.keys(unknown), truncated: lines.length > ROWS ||
                      lines.some(function (l) { return l.length > COLS; }) };
  }

  // --- moving a rectangle of cells, and what a diff costs -------------------
  //
  // The tool is not the device: it has no blitter budget and no reason to move a
  // picture a little at a time.  So `blitShifted` moves a whole rectangle by any
  // offset at all, and `frameDiff` only *counts* what a frame-to-frame diff would
  // have to touch -- the diffing itself is the firmware's job (#247), and this is
  // how the designer can see the size of it.
  //
  // The semantics of the shift, stated once because they are the whole contract:
  //
  //   * `dx`, `dy` are applied to the **content's position**.  `dx = +4` moves the
  //     picture four cells right; `dy = -2` moves it two rows up.
  //   * the destination rectangle is the *same rectangle* as the source, and it is
  //     **cleared first**, so content that moves away leaves a blank cell rather
  //     than a smear of what used to be there.
  //   * content shifted outside the rectangle is **clipped**, not wrapped.  (The
  //     hardware's video RAM *is* a ring buffer, but wrapping a picture is a
  //     different operation from moving one, and moving one is what this is for.)
  //   * the trailer's eight cells are never read and never written.

  function blitShifted(srcCells, srcAttrs, dstCells, dstAttrs, box, dx, dy) {
    // Snapshot the source rectangle first, so the caller may pass the same frame
    // for both if it ever wants to -- the clear below would otherwise eat it.
    var sc = new Uint8Array(box.cols * box.rows);
    var sa = new Uint8Array(box.cols * box.rows);
    var r, c, i;
    for (r = 0; r < box.rows; r++) {
      var sr = box.row0 + r;
      for (c = 0; c < box.cols; c++) {
        var scc = box.col0 + c;
        i = r * box.cols + c;
        if (sr < 0 || sr >= ROWS || scc < 0 || scc >= COLS) continue;
        var si = sr * COLS + scc;
        if (isReserved(si)) continue;
        sc[i] = srcCells[si];
        sa[i] = srcAttrs[si] ? 1 : 0;
      }
    }
    // Clear the destination rectangle.
    for (r = 0; r < box.rows; r++) {
      var dr = box.row0 + r;
      if (dr < 0 || dr >= ROWS) continue;
      for (c = 0; c < box.cols; c++) {
        var dcc = box.col0 + c;
        if (dcc < 0 || dcc >= COLS) continue;
        var di = dr * COLS + dcc;
        if (isReserved(di)) continue;
        dstCells[di] = BLANK;
        dstAttrs[di] = 1;
      }
    }
    // Blit it back, shifted and clipped.
    var moved = 0;
    for (r = 0; r < box.rows; r++) {
      var syr = box.row0 + r, dyr = syr + dy;
      if (dyr < 0 || dyr >= ROWS) continue;
      for (c = 0; c < box.cols; c++) {
        var sxc = box.col0 + c, dxc = sxc + dx;
        if (dxc < 0 || dxc >= COLS) continue;
        var sii = syr * COLS + sxc, dii = dyr * COLS + dxc;
        if (isReserved(sii) || isReserved(dii)) continue;
        var k = r * box.cols + c;
        dstCells[dii] = sc[k];
        dstAttrs[dii] = sa[k];
        moved++;
      }
    }
    return moved;
  }

  // What a frame-to-frame diff would have to touch.  `rows` is there because a
  // row-granular blit is the obvious cheap implementation: a change in one cell
  // costs a whole 128-byte row if that is how you move it.
  function frameDiff(aCells, aAttrs, bCells, bAttrs) {
    var cells = 0, rows = 0, touched = new Uint8Array(ROWS);
    for (var i = 0; i < FRAME; i++) {
      if (isReserved(i)) continue;
      if (aCells[i] !== bCells[i] ||
          (aAttrs[i] ? 1 : 0) !== (bAttrs[i] ? 1 : 0)) {
        cells++;
        touched[Math.floor(i / COLS)] = 1;
      }
    }
    for (var r = 0; r < ROWS; r++) rows += touched[r];
    return { cells: cells, rows: rows, of: FRAME - 8 };
  }

  // The whole animation's cost, if every transition is blitted.
  //
  // The mode matters, and this is the number that made it matter: a loop has to blit
  // the transition it wraps with (last -> first), and a bounce has to blit the way
  // back as well, which is the same transitions in reverse and therefore exactly
  // twice the forward cost.  A designer reading "3 cells over 2 transitions" while
  // the machine plays a six-step bounce is reading the wrong number, so the readout
  // takes the mode and counts what is really played.
  //
  // Both ping-pongs cost the same, and that is worth knowing: the one-shot's last
  // blit is the return to frame 1, and the repeating one's is the wrap into the next
  // cycle -- the same transition, taken once either way.
  function animationDiff(frames, mode) {
    mode = playbackMode(mode);
    var n = frames.length, i;
    if (n < 2) return { cells: 0, worst: 0, transitions: 0, of: FRAME - 8 };
    var steps = [];
    for (i = 0; i + 1 < n; i++) steps.push([i, i + 1]);          // forward
    if (mode === 'loop') steps.push([n - 1, 0]);                 // the wrap
    else if (mode === 'pingpong' || mode === 'pingpong-once')
      for (i = n - 1; i > 0; i--) steps.push([i, i - 1]);        // the way back, to 0
    var cells = 0, worst = 0;
    for (i = 0; i < steps.length; i++) {
      var d = frameDiff(frames[steps[i][0]].cells, frames[steps[i][0]].attrs,
                        frames[steps[i][1]].cells, frames[steps[i][1]].attrs);
      cells += d.cells;
      if (d.cells > worst) worst = d.cells;
    }
    return { cells: cells, worst: worst, transitions: steps.length, of: FRAME - 8 };
  }

  // --- the clipboard, and flipping the ninth bit ----------------------------
  //
  // A selection is a rectangle of cells *and* their attribute bits, so a copy takes
  // both planes and a paste puts both back.  Deliberately not art text: art text is
  // the *file* format and cannot carry glyphs 0x41-0x61 or the ninth bit at all,
  // which is exactly what a clipboard must not lose.  (`.txt` export/import is the
  // way to move a selection between tools; this is the way to move one within the
  // tool, exactly.)

  function copyRegion(cells, attrs, box) {
    var out = { cols: box.cols, rows: box.rows,
                cells: new Uint8Array(box.cols * box.rows),
                attrs: new Uint8Array(box.cols * box.rows) };
    for (var r = 0; r < box.rows; r++) {
      for (var c = 0; c < box.cols; c++) {
        var i = r * box.cols + c;
        out.cells[i] = BLANK;
        out.attrs[i] = 1;
        var sr = box.row0 + r, sc = box.col0 + c;
        if (sr < 0 || sr >= ROWS || sc < 0 || sc >= COLS) continue;
        var si = sr * COLS + sc;
        if (isReserved(si)) continue;
        out.cells[i] = cells[si];
        out.attrs[i] = attrs[si] ? 1 : 0;
      }
    }
    return out;
  }

  // Puts a clipboard down with its top-left corner at (col0, row0), clipped to the
  // screen.  Returns how many cells it wrote.
  function pasteRegion(clip, cells, attrs, col0, row0) {
    var wrote = 0;
    for (var r = 0; r < clip.rows; r++) {
      var dr = row0 + r;
      if (dr < 0 || dr >= ROWS) continue;
      for (var c = 0; c < clip.cols; c++) {
        var dc = col0 + c;
        if (dc < 0 || dc >= COLS) continue;
        var di = dr * COLS + dc;
        if (isReserved(di)) continue;
        var i = r * clip.cols + c;
        cells[di] = clip.cells[i];
        attrs[di] = clip.attrs[i];
        wrote++;
      }
    }
    return wrote;
  }

  // Flip the ninth bit over a rectangle.  This is the operation that should never
  // have needed the character re-entered: the glyph is already there, and the
  // attribute plane is a separate bit.  Returns how many cells it flipped.
  function invertAttrs(attrs, box) {
    var n = 0;
    for (var r = 0; r < box.rows; r++) {
      var rr = box.row0 + r;
      if (rr < 0 || rr >= ROWS) continue;
      for (var c = 0; c < box.cols; c++) {
        var cc = box.col0 + c;
        if (cc < 0 || cc >= COLS) continue;
        var i = rr * COLS + cc;
        if (isReserved(i)) continue;
        attrs[i] = attrs[i] ? 0 : 1;
        n++;
      }
    }
    return n;
  }

  // --- the monitor, and the renderer ---------------------------------------
  //
  // Rendering is *indexed*: 0 paper, 1 ink, 2 dim ink, 3 spare.  One geometry,
  // used by the editor canvas, the preview, the PNG and the GIF -- so what you
  // look at is what the file holds.  Dim is a visibly different ink on purpose:
  // the whole point of the attribute plane is that a dim cell looks dim.

  var MONITORS = {
    white: { label: 'white on black',  paper: [0, 0, 0],     ink: [255, 255, 255] },
    amber: { label: 'amber on black',  paper: [14, 8, 0],    ink: [255, 176, 0] },
    green: { label: 'green on black',  paper: [0, 12, 0],    ink: [80, 255, 120] },
    panel: { label: 'blue-grey on cream', paper: [216, 208, 192], ink: [40, 48, 64] }
  };

  function mix(a, b, t) {
    return [Math.round(a[0] + (b[0] - a[0]) * t),
            Math.round(a[1] + (b[1] - a[1]) * t),
            Math.round(a[2] + (b[2] - a[2]) * t)];
  }

  // Four entries, always: paper, ink, dim ink, spare.  A GIF needs a global
  // colour table and a PNG needs a PLTE, and both want indices, not RGB.
  function paletteFor(name) {
    var m = MONITORS[name] || MONITORS.white;
    return [m.paper, m.ink, mix(m.ink, m.paper, 0.45), m.paper];
  }

  // opt: { columns (52|80|104), scale, col0, row0, cols, rows }
  //
  // `columns` is the SCREEN-PAC width, and it sets the dot width: 52 columns is
  // the machine's own 8-dot cell, 80 is 65% and 104 is 50%.  The physical screen
  // does not change width -- the type narrows -- so a viewport of N columns is
  // always the same number of pixels across.
  function renderIndexed(cells, attrs, opt) {
    opt = opt || {};
    var scale = opt.scale || 1;
    var columns = opt.columns || 52;
    var cellWf = CELL_W * (52 / columns) * scale;
    var cellH = CELL_H * scale;
    var col0 = opt.col0 === undefined ? 0 : opt.col0;
    var row0 = opt.row0 === undefined ? 0 : opt.row0;
    var cols = opt.cols === undefined ? COLS : opt.cols;
    var rows = opt.rows === undefined ? ROWS : opt.rows;
    var W = Math.max(1, Math.round(cols * cellWf));
    var H = Math.max(1, rows * cellH);
    var idx = new Uint8Array(W * H);

    for (var r = 0; r < rows; r++) {
      var srcR = row0 + r;
      if (srcR < 0 || srcR >= ROWS) continue;
      var y0 = r * cellH;
      for (var c = 0; c < cols; c++) {
        var srcC = col0 + c;
        if (srcC < 0 || srcC >= COLS) continue;
        var x0 = Math.round(c * cellWf), x1 = Math.round((c + 1) * cellWf);
        if (x1 <= x0) x1 = x0 + 1;
        var i = srcR * COLS + srcC;
        var code = cells[i] & 0x7F;
        var v = (attrs ? attrs[i] : 1) ? 1 : 2;
        for (var py = 0; py < CELL_H; py++) {
          var bits = ROM[py * 128 + code];
          var yA = y0 + py * scale, yB = yA + scale;
          for (var y = yA; y < yB; y++) {
            var off = y * W;
            for (var x = x0; x < x1; x++) {
              var dx = Math.floor(((x - x0) + 0.5) * CELL_W / (x1 - x0));
              if (dx > 7) dx = 7;
              if ((bits >> (7 - dx)) & 1) idx[off + x] = v;
            }
          }
        }
      }
    }
    return { w: W, h: H, idx: idx };
  }

  function indicesToRGBA(img, palette) {
    var out = new Uint8ClampedArray(img.w * img.h * 4);
    for (var i = 0; i < img.idx.length; i++) {
      var p = palette[img.idx[i]] || palette[0];
      out[i * 4] = p[0]; out[i * 4 + 1] = p[1];
      out[i * 4 + 2] = p[2]; out[i * 4 + 3] = 255;
    }
    return out;
  }

  // The two planes out of a whole 8192-byte frame.
  function framePlanes(bytes) {
    var f = parseFrame(bytes);
    return { ok: f.ok, why: f.why, cells: f.cells, attrs: f.attrs };
  }

  // --- deflate, for the PNG -------------------------------------------------
  //
  // A zlib stream (RFC 1950) of stored blocks: no compression, but synchronous
  // and valid everywhere.  The browser passes `deflateAuto` instead, which uses
  // CompressionStream when it has one -- same zlib format, real compression.

  function deflateStored(bytes) {
    var n = bytes.length;
    var blocks = Math.max(1, Math.ceil(n / 65535));
    var out = new Uint8Array(2 + blocks * 5 + n + 4);
    var p = 0;
    out[p++] = 0x78; out[p++] = 0x01;              // zlib header, no preset dict
    var off = 0;
    for (var b = 0; b < blocks; b++) {
      var len = Math.min(65535, n - off);
      out[p++] = (b === blocks - 1) ? 1 : 0;       // BFINAL, BTYPE=00 (stored)
      out[p++] = len & 0xFF; out[p++] = (len >>> 8) & 0xFF;
      out[p++] = (~len) & 0xFF; out[p++] = ((~len) >>> 8) & 0xFF;
      out.set(bytes.subarray(off, off + len), p);
      p += len; off += len;
    }
    var a = 1, c = 0;                              // adler32
    for (var i = 0; i < n; i++) {
      a = (a + bytes[i]) % 65521;
      c = (c + a) % 65521;
    }
    out[p++] = (c >>> 8) & 0xFF; out[p++] = c & 0xFF;
    out[p++] = (a >>> 8) & 0xFF; out[p++] = a & 0xFF;
    return out.subarray(0, p);
  }

  function deflateAuto(bytes) {
    if (typeof CompressionStream === 'undefined') return deflateStored(bytes);
    try {
      var cs = new CompressionStream('deflate');
      var w = cs.writable.getWriter();
      w.write(bytes); w.close();
      return new Response(cs.readable).arrayBuffer().then(function (b) {
        return new Uint8Array(b);
      });
    } catch (e) {
      return deflateStored(bytes);
    }
  }

  // --- GIF ------------------------------------------------------------------
  //
  // LZW with a minimum code size of 2 (four colours).  The one subtle thing in
  // GIF's LZW is when the code width grows, and it is subtle because the
  // encoder's table runs one entry ahead of the decoder's: the decoder grows when
  // its own `next` reaches 1<<codeSize *after* adding -- omggif's reader:
  //
  //     if (next_code >= code_mask+1 && cur_code_size < 12) ++cur_code_size;
  //
  // -- so the encoder, which has already added one more, must grow on
  // `next > 1<<codeSize`.  `selftest.js` does not take that on trust: it checks
  // the output against macOS's own GIF decoder as well as a decoder written to
  // the reader's rule.

  function lzwEncode(pixels, minCodeSize) {
    var clearCode = 1 << minCodeSize;
    var eoiCode = clearCode + 1;
    var out = [];
    var bitBuf = 0, bitCnt = 0, codeSize = minCodeSize + 1;
    var dict = new Map(), next = eoiCode + 1;

    function emit(code) {
      bitBuf |= code << bitCnt;
      bitCnt += codeSize;
      while (bitCnt >= 8) { out.push(bitBuf & 0xFF); bitBuf >>>= 8; bitCnt -= 8; }
    }
    function reset() {
      // The dictionary holds *strings*, keyed by (prefix code, next pixel).  The
      // single-pixel codes 0..clearCode-1 are deliberately NOT seeded into it:
      // seeding them puts key k (the pixel) in the same space as the composite
      // key (prefix 0, pixel k), which is also k -- and the encoder then swallows
      // the second pixel of every run.  That was this function's first bug, and
      // the GIF check in selftest.js is what caught it.
      dict.clear();
      next = eoiCode + 1;
      codeSize = minCodeSize + 1;
    }

    reset();
    emit(clearCode);
    if (pixels.length === 0) {
      emit(eoiCode);
    } else {
      var prefix = pixels[0];
      for (var i = 1; i < pixels.length; i++) {
        var k = pixels[i];
        var key = prefix * 4096 + k;
        var found = dict.get(key);
        if (found !== undefined) { prefix = found; continue; }
        emit(prefix);
        if (next < 4096) {
          dict.set(key, next);
          next++;
          if (next > (1 << codeSize) && codeSize < 12) codeSize++;
        } else {
          emit(clearCode);
          reset();
        }
        prefix = k;
      }
      emit(prefix);
      emit(eoiCode);
    }
    if (bitCnt > 0) out.push(bitBuf & 0xFF);
    return out;
  }

  function encodeGIF(frames, palette, delayCs, loop) {
    var w = frames[0].w, h = frames[0].h;
    var out = [], i, k;
    function push16(v) { out.push(v & 0xFF, (v >>> 8) & 0xFF); }

    out.push(0x47, 0x49, 0x46, 0x38, 0x39, 0x61);        // GIF89a
    push16(w); push16(h);
    out.push(0x80 | 0x70 | 1);                            // GCT, 4 entries
    out.push(0);                                          // background index
    out.push(0);                                          // pixel aspect
    for (i = 0; i < 4; i++) {
      var p = palette[i] || palette[0];
      out.push(p[0], p[1], p[2]);
    }
    if (loop) {                                           // NETSCAPE2.0, forever
      out.push(0x21, 0xFF, 0x0B);
      out.push(0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30);
      out.push(0x03, 0x01, 0x00, 0x00, 0x00);
    }
    for (i = 0; i < frames.length; i++) {
      var img = frames[i];
      out.push(0x21, 0xF9, 0x04, 0x04,                   // GCE: disposal 1, opaque
               delayCs & 0xFF, (delayCs >>> 8) & 0xFF, 0x00, 0x00);
      out.push(0x2C);
      push16(0); push16(0); push16(img.w); push16(img.h);
      out.push(0x00);                                     // no local table
      var lzw = lzwEncode(img.idx, 2);
      out.push(2);                                        // minimum code size
      for (k = 0; k < lzw.length; k += 255) {
        var n = Math.min(255, lzw.length - k);
        out.push(n);
        for (var q = 0; q < n; q++) out.push(lzw[k + q]);
      }
      out.push(0x00);                                     // block terminator
    }
    out.push(0x3B);                                       // trailer
    return new Uint8Array(out);
  }

  // --- PNG ------------------------------------------------------------------
  //
  // Colour type 3 (palette), bit depth 2 -- one index per pixel, four entries,
  // filter 0 on every row.  That keeps the decoder trivial (which is what the
  // self-test needs) and the file small, because the art is flat.

  function u32be(bytes, at, v) {
    bytes[at] = (v >>> 24) & 0xFF; bytes[at + 1] = (v >>> 16) & 0xFF;
    bytes[at + 2] = (v >>> 8) & 0xFF; bytes[at + 3] = v & 0xFF;
  }

  function pngChunk(type, data) {
    var out = new Uint8Array(12 + data.length);
    u32be(out, 0, data.length);
    for (var i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
    out.set(data, 8);
    u32be(out, 8 + data.length, crc32(out.subarray(4, 8 + data.length)));
    return out;
  }

  // Returns a Promise of the PNG bytes.
  function encodePNG(img, palette, deflate) {
    var w = img.w, h = img.h;
    var rowBytes = Math.ceil(w / 4);
    var raw = new Uint8Array((rowBytes + 1) * h);
    for (var y = 0; y < h; y++) {
      var o = y * (rowBytes + 1);
      raw[o] = 0;                                   // filter: none
      for (var x = 0; x < w; x++)
        raw[o + 1 + (x >> 2)] |= (img.idx[y * w + x] & 3) << (6 - 2 * (x & 3));
    }
    var plte = new Uint8Array(palette.length * 3);
    for (var i = 0; i < palette.length; i++) {
      plte[i * 3] = palette[i][0];
      plte[i * 3 + 1] = palette[i][1];
      plte[i * 3 + 2] = palette[i][2];
    }
    var ihdr = new Uint8Array(13);
    u32be(ihdr, 0, w); u32be(ihdr, 4, h);
    ihdr[8] = 2;                                    // bit depth
    ihdr[9] = 3;                                    // colour type: palette
    return Promise.resolve(deflate(raw)).then(function (idat) {
      var chunks = [pngChunk('IHDR', ihdr), pngChunk('PLTE', plte),
                    pngChunk('IDAT', idat), pngChunk('IEND', new Uint8Array(0))];
      var total = 8, k;
      for (k = 0; k < chunks.length; k++) total += chunks[k].length;
      var out = new Uint8Array(total);
      var sig = [137, 80, 78, 71, 13, 10, 26, 10];
      for (k = 0; k < 8; k++) out[k] = sig[k];
      var p = 8;
      for (k = 0; k < chunks.length; k++) { out.set(chunks[k], p); p += chunks[k].length; }
      return out;
    });
  }

  // --- what this module offers ----------------------------------------------
  var API = {
    COLS: COLS, ROWS: ROWS, CELL_W: CELL_W, CELL_H: CELL_H,
    FRAME: FRAME, VISIBLE_ROWS: VISIBLE_ROWS, TRAILER_AT: TRAILER_AT,
    VIEWPORT_WIDTHS: VIEWPORT_WIDTHS, VIEWPORT_ROWS: VIEWPORT_ROWS,
    MAGIC: MAGIC, ATTR_BRIGHT: ATTR_BRIGHT, ATTR_DIM: ATTR_DIM,
    ANIM_MAGIC: ANIM_MAGIC, ANIM_HEADER: ANIM_HEADER, ANIM_VERSION: ANIM_VERSION,
    ANIM_LOOP: ANIM_LOOP, ANIM_PINGPONG: ANIM_PINGPONG, MODES: MODES,
    GRAPHICS_FIRST: GRAPHICS_FIRST, GRAPHICS_LAST: GRAPHICS_LAST,
    ART_OFFSET: ART_OFFSET, BLANK: BLANK,
    HATCH_CODE: HATCH_CODE, HATCH_CHAR: HATCH_CHAR,
    GRAPHICS_KEYS: GRAPHICS_KEYS, MONITORS: MONITORS,
    CHAR_ROM_CRC32: CHAR_ROM_CRC32, CHAR_ROM_LEN: CHAR_ROM_LEN,

    crc32: crc32, hex: hex, romCrc32: romCrc32, romOk: romOk,
    glyphDot: glyphDot, glyphBits: glyphBits,
    glyphForArtChar: glyphForArtChar, artCharForGlyph: artCharForGlyph,
    glyphForKey: glyphForKey, keyForGlyph: keyForGlyph, paletteSet: paletteSet,
    isGraphicsGlyph: isGraphicsGlyph, isReserved: isReserved,
    blankCells: blankCells, brightAttrs: brightAttrs,
    seal: seal, checkHalf: checkHalf, checkFrame: checkFrame,
    buildFrame: buildFrame, parseFrame: parseFrame, framePlanes: framePlanes,
    buildAnimation: buildAnimation, parseAnimation: parseAnimation,
    playbackMode: playbackMode, modeFlags: modeFlags, modeFromFlags: modeFromFlags,
    modeRepeats: modeRepeats, playbackOrder: playbackOrder,
    artText: artText, artTextBytes: artTextBytes, artTextLossy: artTextLossy,
    parseArtText: parseArtText,
    paletteFor: paletteFor, renderIndexed: renderIndexed,
    indicesToRGBA: indicesToRGBA,
    blitShifted: blitShifted, frameDiff: frameDiff, animationDiff: animationDiff,
    copyRegion: copyRegion, pasteRegion: pasteRegion, invertAttrs: invertAttrs,
    deflateStored: deflateStored, deflateAuto: deflateAuto, encodePNG: encodePNG,
    lzwEncode: lzwEncode, encodeGIF: encodeGIF
  };

  root.O1Splash = API;
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
}(typeof globalThis !== 'undefined' ? globalThis : this));
