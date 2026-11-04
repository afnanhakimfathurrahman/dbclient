import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

function createPng(width, height, drawFn) {
  // RGBA buffer: height rows, each with 1 byte filter (0) + width * 4 bytes RGBA
  const rowSize = 1 + width * 4;
  const rawData = Buffer.alloc(rowSize * height);

  for (let y = 0; y < height; y++) {
    const rowOffset = y * rowSize;
    rawData[rowOffset] = 0; // Filter type: None
    for (let x = 0; x < width; x++) {
      const pixelOffset = rowOffset + 1 + x * 4;
      const [r, g, b, a] = drawFn(x, y, width, height);
      rawData[pixelOffset] = r;
      rawData[pixelOffset + 1] = g;
      rawData[pixelOffset + 2] = b;
      rawData[pixelOffset + 3] = a;
    }
  }

  const compressed = zlib.deflateSync(rawData);

  function makeChunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const typeBuf = Buffer.from(type, 'ascii');
    const crcBuf = Buffer.alloc(4);

    // CRC32 calculation
    const toCrc = Buffer.concat([typeBuf, data]);
    let c = 0xffffffff;
    for (let i = 0; i < toCrc.length; i++) {
      c ^= toCrc[i];
      for (let k = 0; k < 8; k++) {
        c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
      }
    }
    c ^= 0xffffffff;
    crcBuf.writeInt32BE(c, 0);

    return Buffer.concat([len, typeBuf, data, crcBuf]);
  }

  // IHDR
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type 6: RGBA
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace

  const header = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdrChunk = makeChunk('IHDR', ihdr);
  const idatChunk = makeChunk('IDAT', compressed);
  const iendChunk = makeChunk('IEND', Buffer.alloc(0));

  return Buffer.concat([header, ihdrChunk, idatChunk, iendChunk]);
}

// Draw DBeaver-style database icon
function iconDraw(x, y, w, h) {
  const nx = x / w;
  const ny = y / h;

  // Background rounded squircle / gradient
  const cx = 0.5;
  const cy = 0.5;
  const dx = Math.abs(nx - cx);
  const dy = Math.abs(ny - cy);
  const distSq = dx * dx + dy * dy;

  // Base background (dark slate/cyan gradient)
  let r = 15;
  let g = 23;
  let b = 42;
  let a = 255;

  // Outer border / glow
  if (distSq < 0.22) {
    // Database stack representation: 3 disks
    // Center disk positions
    const inCylinder = (diskY, diskH) => {
      const dyRel = (ny - diskY) / diskH;
      const dxRel = (nx - 0.5) / 0.32;
      return (dxRel * dxRel + dyRel * dyRel) <= 1.0;
    };

    // Cylinder 1 (top)
    const isTopDisk = inCylinder(0.32, 0.08);
    // Cylinder 2 (mid)
    const isMidDisk = inCylinder(0.50, 0.08);
    // Cylinder 3 (bot)
    const isBotDisk = inCylinder(0.68, 0.08);
    // Cylinder body 1
    const inBody1 = Math.abs(nx - 0.5) <= 0.32 && ny >= 0.32 && ny <= 0.50;
    // Cylinder body 2
    const inBody2 = Math.abs(nx - 0.5) <= 0.32 && ny >= 0.50 && ny <= 0.68;

    if (isTopDisk) {
      r = 56; g = 189; b = 248; // cyan-400
    } else if (inBody1) {
      r = 14; g = 116; b = 144; // cyan-700
      if (Math.abs(nx - 0.7) < 0.08) { r = 34; g = 197; b = 94; } // accent highlight
    } else if (isMidDisk) {
      r = 14; g = 165; b = 233; // sky-500
    } else if (inBody2) {
      r = 3; g = 105; b = 161; // sky-700
    } else if (isBotDisk) {
      r = 2; g = 132; b = 199; // sky-600
    } else {
      // Subtle grid background
      r = Math.floor(15 + nx * 20);
      g = Math.floor(23 + ny * 25);
      b = 42;
    }
  }

  return [r, g, b, a];
}

const publicDir = path.resolve('public');
if (!fs.existsSync(publicDir)) {
  fs.mkdirSync(publicDir, { recursive: true });
}

// Write PNGs
const sizes = [
  { file: 'pwa-192x192.png', size: 192 },
  { file: 'pwa-512x512.png', size: 512 },
  { file: 'pwa-maskable-512x512.png', size: 512 },
  { file: 'apple-touch-icon.png', size: 180 },
  { file: 'favicon.ico', size: 64 },
];

for (const { file, size } of sizes) {
  const pngBuf = createPng(size, size, iconDraw);
  fs.writeFileSync(path.join(publicDir, file), pngBuf);
  console.log(`Generated ${file} (${size}x${size})`);
}

// Generate icon.svg
const svgContent = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="none">
  <rect width="512" height="512" rx="112" fill="#0f172a"/>
  <rect x="24" y="24" width="464" height="464" rx="96" stroke="#38bdf8" stroke-opacity="0.3" stroke-width="8"/>
  <g transform="translate(64, 76)">
    <!-- Top Cylinder -->
    <ellipse cx="192" cy="60" rx="140" ry="42" fill="#38bdf8"/>
    <ellipse cx="192" cy="60" rx="140" ry="42" stroke="#bae6fd" stroke-width="6"/>
    
    <!-- Mid Cylinder Layer -->
    <path d="M 52 60 V 160 C 52 202, 332 202, 332 160 V 60" fill="#0284c7" opacity="0.9"/>
    <ellipse cx="192" cy="160" rx="140" ry="42" fill="#0ea5e9"/>
    <ellipse cx="192" cy="160" rx="140" ry="42" stroke="#7dd3fc" stroke-width="4"/>
    
    <!-- Bot Cylinder Layer -->
    <path d="M 52 160 V 260 C 52 302, 332 302, 332 160 V 160" fill="#0369a1" opacity="0.9"/>
    <ellipse cx="192" cy="260" rx="140" ry="42" fill="#0284c7"/>
    <ellipse cx="192" cy="260" rx="140" ry="42" stroke="#38bdf8" stroke-width="4"/>
    
    <!-- DBeaver Lightning / Query Spark -->
    <path d="M 230 110 L 170 230 L 220 230 L 160 350 L 270 200 L 210 200 Z" fill="#fbbf24" stroke="#f59e0b" stroke-width="6" stroke-linejoin="round"/>
  </g>
</svg>`;
fs.writeFileSync(path.join(publicDir, 'icon.svg'), svgContent, 'utf-8');
console.log('Generated icon.svg');
