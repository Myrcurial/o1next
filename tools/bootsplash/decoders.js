/* decoders.js -- PNG, GIF and BMP readers, for the checks only.
 *
 * These exist so the *encoders* in core.js can be wrong and be caught: they are
 * written to the specs (and, for the GIF, to the reader rule quoted in core.js)
 * rather than to whatever the encoders happen to emit.  Nothing in the browser
 * tool loads this file.
 *
 * `tools/bootsplash/selftest.js` uses all three.  `tools/bootsplash/ui-test.js`
 * uses them too, so that what the page's download buttons produce is checked
 * with the same eyes.
 */
'use strict';

const zlib = require('zlib');
const S = require('./core.js');

function decodePNG(buf) {
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < 8; i++) if (buf[i] !== sig[i]) throw new Error('not a PNG');
  let p = 8, w = 0, h = 0, depth = 0, colour = 0, palette = null;
  const idat = [];
  while (p + 12 <= buf.length) {
    const len = buf.readUInt32BE(p);
    const type = buf.toString('latin1', p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    const crc = buf.readUInt32BE(p + 8 + len);
    if (S.crc32(buf.subarray(p + 4, p + 8 + len)) !== crc)
      throw new Error('bad CRC32 on the ' + type + ' chunk');
    if (type === 'IHDR') {
      w = data.readUInt32BE(0); h = data.readUInt32BE(4);
      depth = data[8]; colour = data[9];
      if (data[10] || data[11] || data[12])
        throw new Error('unexpected compression/filter/interlace');
    } else if (type === 'PLTE') {
      palette = [];
      for (let i = 0; i < data.length; i += 3)
        palette.push([data[i], data[i + 1], data[i + 2]]);
    } else if (type === 'IDAT') { idat.push(data); }
    else if (type === 'IEND') break;
    p += 12 + len;
  }
  if (depth !== 2 || colour !== 3)
    throw new Error('expected 2-bit palette, got depth ' + depth + ' colour ' + colour);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const rowBytes = Math.ceil(w / 4);
  const idx = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    const o = y * (rowBytes + 1);
    if (raw[o] !== 0) throw new Error('unexpected filter ' + raw[o] + ' on row ' + y);
    for (let x = 0; x < w; x++)
      idx[y * w + x] = (raw[o + 1 + (x >> 2)] >> (6 - 2 * (x & 3))) & 3;
  }
  return { w, h, palette, idx };
}

// The reader rule: the decoder grows the code width when its own `next` reaches
// 1 << codeSize *after* adding an entry -- see the comment in core.js.
function lzwDecode(data, minCodeSize) {
  const clear = 1 << minCodeSize, eoi = clear + 1;
  let codeSize = minCodeSize + 1, next = eoi + 1, table = [];
  const reset = () => {
    table = [];
    for (let i = 0; i < clear; i++) table[i] = [i];
    table[clear] = null; table[eoi] = null;
    next = eoi + 1;
    codeSize = minCodeSize + 1;
  };
  reset();
  const out = [];
  let bit = 0, prev = null;
  const readCode = () => {
    let v = 0;
    for (let i = 0; i < codeSize; i++) {
      v |= ((data[bit >> 3] >> (bit & 7)) & 1) << i;
      bit++;
    }
    return v;
  };
  for (;;) {
    const code = readCode();
    if (code === clear) { reset(); prev = null; continue; }
    if (code === eoi) break;
    let entry;
    if (code < next && table[code]) entry = table[code];
    else if (prev !== null) entry = table[prev].concat([table[prev][0]]);
    else throw new Error('code ' + code + ' with no previous entry');
    for (let i = 0; i < entry.length; i++) out.push(entry[i]);
    if (prev !== null && next < 4096) {
      table[next++] = table[prev].concat([entry[0]]);
      if (next >= (1 << codeSize) && codeSize < 12) codeSize++;
    }
    prev = code;
  }
  return out;
}

function decodeGIF(buf) {
  if (buf.toString('latin1', 0, 6) !== 'GIF89a') throw new Error('not GIF89a');
  let p = 6;
  const w = buf.readUInt16LE(p), h = buf.readUInt16LE(p + 2);
  const packed = buf[p + 4];
  p += 7;
  let gct = null;
  if (packed & 0x80) {
    const n = 1 << ((packed & 7) + 1);
    gct = [];
    for (let i = 0; i < n; i++) { gct.push([buf[p], buf[p + 1], buf[p + 2]]); p += 3; }
  }
  const subBlocks = () => {
    const parts = [];
    for (;;) {
      const n = buf[p++];
      if (n === 0) break;
      parts.push(buf.subarray(p, p + n));
      p += n;
    }
    return Buffer.concat(parts);
  };
  const frames = [];
  let delay = 0, loopCount = null;
  for (;;) {
    const b = buf[p++];
    if (b === 0x3B) break;
    if (b === 0x21) {
      const label = buf[p++];
      if (label === 0xF9) {
        const n = buf[p++];
        delay = buf.readUInt16LE(p + 1);
        p += n;
        p++;                                   // block terminator
      } else if (label === 0xFF) {
        const n = buf[p++];
        const app = buf.toString('latin1', p, p + n);
        p += n;
        const data = subBlocks();
        if (app === 'NETSCAPE2.0') loopCount = data.readUInt16LE(1);
      } else { subBlocks(); }
      continue;
    }
    if (b === 0x2C) {
      const iw = buf.readUInt16LE(p + 4), ih = buf.readUInt16LE(p + 6);
      const ip = buf[p + 8];
      p += 9;
      let lct = null;
      if (ip & 0x80) {
        const n = 1 << ((ip & 7) + 1);
        lct = [];
        for (let i = 0; i < n; i++) { lct.push([buf[p], buf[p + 1], buf[p + 2]]); p += 3; }
      }
      const minCode = buf[p++];
      const idx = lzwDecode(subBlocks(), minCode);
      frames.push({ w: iw, h: ih, delay, idx, palette: lct || gct });
      continue;
    }
    throw new Error('unexpected block 0x' + b.toString(16) + ' at ' + (p - 1));
  }
  return { w, h, frames, loopCount };
}

// BMP, only so that `sips` can be asked to decode our GIF for us.
function decodeBMP(buf) {
  if (buf.toString('latin1', 0, 2) !== 'BM') throw new Error('not a BMP');
  const off = buf.readUInt32LE(10);
  let w = buf.readInt32LE(18), h = buf.readInt32LE(22);
  const bpp = buf.readUInt16LE(28);
  const bottomUp = h > 0;
  h = Math.abs(h);
  const stride = Math.floor((bpp * w + 31) / 32) * 4;
  const bytes = bpp / 8;
  const px = (x, y) => {
    const row = bottomUp ? h - 1 - y : y;
    const o = off + row * stride + x * bytes;
    return [buf[o + 2], buf[o + 1], buf[o]];
  };
  return { w, h, bpp, px };
}

module.exports = { decodePNG, decodeGIF, lzwDecode, decodeBMP };
