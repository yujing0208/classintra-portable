// ClassIntra 绿色版 - .env 生成工具
// 若 server\.env 不存在，从 .env.example 复制并写入随机 JWT_SECRET
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SERVER = path.resolve(__dirname, '..', 'server');
const envF = path.join(SERVER, '.env');
const exF = path.join(SERVER, '.env.example');

if (fs.existsSync(envF)) {
  console.log('[make-env] .env 已存在，跳过。');
  process.exit(0);
}
if (!fs.existsSync(exF)) {
  console.log('[make-env] 未找到 .env.example，跳过。');
  process.exit(0);
}
let txt = fs.readFileSync(exF, 'utf8');
txt = txt
  .split(/\r?\n/)
  .map((l) =>
    l.startsWith('JWT_SECRET=') ? 'JWT_SECRET=' + crypto.randomBytes(48).toString('hex') : l
  )
  .join('\r\n');
fs.writeFileSync(envF, txt);
console.log('[make-env] 已生成 .env（含随机 JWT_SECRET）。');
