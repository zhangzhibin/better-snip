/**
 * 生成一张带字母的 512x512 图标 PNG，用于 Tauri 应用图标。
 * 用法: node scripts/generate-icon.js [字母]  默认字母为 S (Screenshot)
 * 依赖: npm install canvas --save-dev
 */

import { createCanvas } from 'canvas';
import { writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const letter = (process.argv[2] || 'S').toUpperCase().slice(0, 1);
const size = 512;
const outDir = join(__dirname, '../src-tauri/icons');
const outPath = join(outDir, 'icon-512.png');

const canvas = createCanvas(size, size);
const ctx = canvas.getContext('2d');

// 背景：蓝色矩形
ctx.fillStyle = '#2563eb';
ctx.fillRect(0, 0, size, size);

// 白色粗体字母居中
ctx.fillStyle = '#ffffff';
ctx.font = `bold ${size * 0.5}px "Helvetica Neue", Helvetica, Arial, sans-serif`;
ctx.textAlign = 'center';
ctx.textBaseline = 'middle';
ctx.fillText(letter, size / 2, size / 2);

mkdirSync(outDir, { recursive: true });
const buf = canvas.toBuffer('image/png');
writeFileSync(outPath, buf);
console.log(`Generated ${outPath} (letter "${letter}")`);
console.log('Then run: npx tauri icon src-tauri/icons/icon-512.png');
