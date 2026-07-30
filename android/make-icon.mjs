// Generates the launcher icon as a real PNG, locally.
// Deliberately generated rather than committed as a binary blob: this project has
// already corrupted a PNG by round-tripping its bytes through a text channel, so the
// icon is produced by running this script instead.
//
//   node android/make-icon.mjs android/res/mipmap-xxxhdpi/ic_launcher.png 192
//
// Draws a dark rounded field with a parametric-EQ response curve: a boost bell and a
// cut bell, which is what the app is.

import fs from "node:fs";
import zlib from "node:zlib";

const out = process.argv[2];
const S = Number(process.argv[3] || 192);
if (!out) { console.error("usage: make-icon.mjs OUT.png [size]"); process.exit(2); }

const BG = [0x0b, 0x0e, 0x12];
const PANEL = [0x14, 0x19, 0x22];
const GRID = [0x23, 0x2b, 0x36];
const CURVE = [0xe5, 0xa0, 0x0d]; // amber, the band-node colour used in the app
const ZERO = [0x3d, 0x4a, 0x5c];

const px = Buffer.alloc(S * S * 4);
const set = (x, y, c, a = 255) => {
  if (x < 0 || y < 0 || x >= S || y >= S) return;
  const i = (y * S + x) * 4;
  const sa = a / 255, da = 1 - sa;
  px[i] = Math.round(px[i] * da + c[0] * sa);
  px[i + 1] = Math.round(px[i + 1] * da + c[1] * sa);
  px[i + 2] = Math.round(px[i + 2] * da + c[2] * sa);
  px[i + 3] = 255;
};

const r = Math.round(S * 0.18);          // corner radius
const inside = (x, y) => {
  const cx = Math.min(Math.max(x, r), S - 1 - r);
  const cy = Math.min(Math.max(y, r), S - 1 - r);
  const dx = x - cx, dy = y - cy;
  return dx * dx + dy * dy <= r * r;
};

for (let y = 0; y < S; y++) {
  for (let x = 0; x < S; x++) {
    if (!inside(x, y)) { const i = (y * S + x) * 4; px[i + 3] = 0; continue; }
    set(x, y, y < S * 0.5 ? PANEL : BG);
  }
}

// grid
for (let g = 1; g < 4; g++) {
  const gy = Math.round((S * g) / 4);
  for (let x = 0; x < S; x++) if (inside(x, gy)) set(x, gy, GRID, 150);
  const gx = Math.round((S * g) / 4);
  for (let y = 0; y < S; y++) if (inside(gx, y)) set(gx, y, GRID, 150);
}

// 0 dB line
const mid = Math.round(S / 2);
for (let x = 0; x < S; x++) if (inside(x, mid)) set(x, mid, ZERO, 220);

// response curve: +bell then -bell
const bell = (x, c, w, a) => a * Math.exp(-((x - c) ** 2) / (2 * w * w));
const yOf = (x) => {
  const db = bell(x, S * 0.32, S * 0.10, S * 0.20) - bell(x, S * 0.70, S * 0.09, S * 0.16);
  return mid - db;
};
const th = Math.max(2, Math.round(S / 48));
let prev = yOf(0);
for (let x = 0; x < S; x++) {
  const y = yOf(x);
  const lo = Math.min(prev, y), hi = Math.max(prev, y);
  for (let yy = Math.floor(lo) - th; yy <= Math.ceil(hi) + th; yy++) {
    const d = Math.abs(yy - y);
    if (d <= th) set(x, yy, CURVE, d < th - 1 ? 255 : 130);
  }
  prev = y;
}

// band handles
for (const cx of [S * 0.32, S * 0.70]) {
  const cy = yOf(cx), rr = Math.max(3, Math.round(S / 26));
  for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr; dx <= rr; dx++) {
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d <= rr) set(Math.round(cx + dx), Math.round(cy + dy), CURVE, d > rr - 1 ? 120 : 255);
  }
}

// PNG encode (RGBA, filter 0)
const raw = Buffer.alloc((S * 4 + 1) * S);
for (let y = 0; y < S; y++) {
  raw[y * (S * 4 + 1)] = 0;
  px.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
}
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
  return Buffer.concat([len, td, crc]);
};
let TBL = null;
function crc32(buf) {
  if (!TBL) { TBL = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; TBL[n] = c >>> 0; } }
  let c = 0xffffffff;
  for (const b of buf) c = TBL[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4);
ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);
fs.writeFileSync(out, png);
console.log("wrote " + out + " (" + png.length + " bytes, " + S + "x" + S + ")");
