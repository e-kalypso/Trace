/* Generates PWA PNG icons (no image libs) — a coral "trace" stroke on
   deep slate, matching the favicon. Run: node scripts/make-icons.mjs */
import { writeFileSync, mkdirSync } from "node:fs";
import zlib from "node:zlib";

const SLATE = [20, 27, 35];
const CORAL = [232, 102, 60];
const GREEN = [87, 201, 138];
const WHITE = [231, 236, 240];

// CRC32
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}
function encodePng(width, height, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  // raw scanlines each prefixed with filter byte 0
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([
    sig,
    chunk("IHDR", ihdr),
    chunk("IDAT", idat),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// distance from point p to segment ab
function distToSeg(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy || 1;
  let t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const cx = ax + t * dx;
  const cy = ay + t * dy;
  return Math.hypot(px - cx, py - cy);
}

function makeIcon(size, markScale = 1) {
  const rgba = Buffer.alloc(size * size * 4);
  // control points (0..1) — a little mountain zig-zag, scaled toward center
  const c = 0.5;
  const path = [
    [0.16, 0.66],
    [0.36, 0.34],
    [0.5, 0.6],
    [0.68, 0.3],
    [0.86, 0.42],
  ].map(([x, y]) => [
    (c + (x - c) * markScale) * size,
    (c + (y - c) * markScale) * size,
  ]);
  const stroke = size * 0.055 * markScale;
  const dotR = size * 0.05 * markScale;

  const set = (x, y, [r, g, b], a = 255) => {
    const i = (y * size + x) * 4;
    // simple alpha over
    const ia = a / 255;
    rgba[i] = Math.round(r * ia + rgba[i] * (1 - ia));
    rgba[i + 1] = Math.round(g * ia + rgba[i + 1] * (1 - ia));
    rgba[i + 2] = Math.round(b * ia + rgba[i + 2] * (1 - ia));
    rgba[i + 3] = 255;
  };

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      set(x, y, SLATE);
      // coral stroke
      let d = Infinity;
      for (let s = 0; s < path.length - 1; s++) {
        d = Math.min(
          d,
          distToSeg(x, y, path[s][0], path[s][1], path[s + 1][0], path[s + 1][1]),
        );
      }
      const edge = stroke - d;
      if (edge > -1) set(x, y, CORAL, Math.max(0, Math.min(1, edge)) * 255);
      // end dots
      const dStart = Math.hypot(x - path[0][0], y - path[0][1]);
      if (dStart < dotR) set(x, y, GREEN);
      const dEnd = Math.hypot(x - path[path.length - 1][0], y - path[path.length - 1][1]);
      if (dEnd < dotR) set(x, y, WHITE);
    }
  }
  return encodePng(size, size, rgba);
}

mkdirSync("public/icons", { recursive: true });
for (const size of [192, 512]) {
  writeFileSync(`public/icons/icon-${size}.png`, makeIcon(size));
}
writeFileSync("public/icons/apple-touch-icon.png", makeIcon(180));
writeFileSync("public/icons/maskable-512.png", makeIcon(512));
console.log("Wrote PWA icons to public/icons/");

// Source images for @capacitor/assets (native iOS icon + splash).
mkdirSync("resources", { recursive: true });
writeFileSync("resources/icon.png", makeIcon(1024));
writeFileSync("resources/splash.png", makeIcon(2732, 0.4));
writeFileSync("resources/splash-dark.png", makeIcon(2732, 0.4));
console.log("Wrote native source images to resources/");
