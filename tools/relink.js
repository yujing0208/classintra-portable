// ClassIntra 绿色版 - 依赖链接修复器（v3）
//
// node_modules 是 pnpm 链接结构：顶层包与 .pnpm 内的依赖都是目录 junction，
// 指向 node_modules\.pnpm\ 下的真实文件。整包拷贝/移动/解压到别的电脑后，
// 链接可能变成指向"旧电脑路径"的死链，或被拷贝工具物化成普通文件夹，
// 或缺失。这都会导致启动报 Cannot find module 'xxx'。
//
// 本工具按 tools\node_modules-manifest.json（打包时记录：哪个位置应是指向哪个
// .pnpm 包的链接）把每个"应是链接"的位置修复为指向【本机当前 .pnpm】的 junction：
//   - 已是正确链接（指向本机 .pnpm）→ 跳过，不动
//   - 缺失             → 直接创建
//   - 死链/指向他处     → 删除后重建
//   - 被物化成普通目录  → 整棵删除后重建（目录内容只是副本，.pnpm 里才是真源）
// 无需网络、无需管理员权限。
//
// 用法：runtime\node\node.exe tools\relink.js
'use strict';
const fs = require('fs');
const path = require('path');

const SERVER_DIR = path.resolve(__dirname, '..', 'server');
const NM = path.join(SERVER_DIR, 'node_modules');
const MANIFEST = path.join(__dirname, 'node_modules-manifest.json');

if (!fs.existsSync(path.join(NM, '.pnpm'))) {
  console.log('[relink] 未找到 server\\node_modules\\.pnpm —— 拷贝不完整，请重新拷贝整个文件夹。');
  process.exit(1);
}
if (!fs.existsSync(MANIFEST)) {
  console.log('[relink] 未找到 tools\\node_modules-manifest.json —— 请重新拷贝整个文件夹。');
  process.exit(1);
}

const mf = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
// rel 统一用 / 分隔；key = 相对 node_modules 的 posix 路径
const want = new Map();          // relPosix -> relTargetPosix
for (const [rp, rt] of mf.links) want.set(rp.replace(/\\/g, '/'), rt.replace(/\\/g, '/'));

let created = 0, rebuilt = 0, removedStale = 0, skipped = 0, fail = 0;

function norm(p) { return p.split(path.sep).join('/'); }
function relOf(abs) { return norm(path.relative(NM, abs)); }

function isReparse(p) {
  try { return fs.lstatSync(p).isSymbolicLink(); }
  catch (e) { return false; }
}
function readTarget(p) {
  try { return fs.readlinkSync(p).replace(/^\\\\\?\\/, ''); }
  catch (e) { return null; }
}
function exists(p) {
  try { fs.lstatSync(p); return true; }
  catch (e) { return false; }
}

// 修复一个"应是链接"的位置
function fixOne(relPosix, relTgtPosix) {
  const link = path.join(NM, relPosix.split('/').join(path.sep));
  const target = path.join(NM, relTgtPosix.split('/').join(path.sep));
  const relLink = relPosix.slice(0, 80);

  if (!exists(target)) {
    console.log('  [错误] 目标缺失: ' + relTgtPosix + '（.pnpm 不完整？）');
    fail++;
    return;
  }
  // 已是正确链接（指向本机当前 .pnpm 的目标）→ 跳过
  const stExists = exists(link);
  if (stExists && isReparse(link)) {
    const cur = readTarget(link);
    if (cur && path.resolve(cur) === path.resolve(target)) { skipped++; return; }
    // 死链/指向他处：删除旧链接
    try {
      fs.rmdirSync(link);
    } catch (e) {
      try { fs.rmSync(link, { recursive: false, force: true }); }
      catch (e2) { console.log('  [错误] 删除旧链接失败 ' + relLink + ' : ' + e2.message); fail++; return; }
    }
    rebuilt++;
  } else if (stExists) {
    // 被物化成的普通目录/文件：整棵删除（.pnpm 里才是真源）
    try {
      fs.rmSync(link, { recursive: true, force: true });
      rebuilt++;
    } catch (e) {
      console.log('  [错误] 删除物化目录失败 ' + relLink + ' : ' + e.message);
      fail++;
      return;
    }
  } else {
    created++;
  }
  try {
    fs.mkdirSync(path.dirname(link), { recursive: true });
    fs.symlinkSync(target, link, 'junction');
  } catch (e) {
    console.log('  [错误] 创建链接失败 ' + relLink + ' : ' + e.message);
    fail++;
  }
}

// 深度优先遍历：进入目录时先处理其中的链接位（目录分组顺序，避免 Windows 句柄问题）
function walkDir(dirAbs) {
  let ents;
  try { ents = fs.readdirSync(dirAbs, { withFileTypes: true }); }
  catch (e) { return; }
  const dirs = [];
  for (const ent of ents) {
    const p = path.join(dirAbs, ent.name);
    const rel = relOf(p);
    if (want.has(rel)) {
      fixOne(rel, want.get(rel));       // 先修该位置的链接
      continue;
    }
    if (ent.isDirectory() && !isReparse(p)) dirs.push(p);
  }
  for (const d of dirs) walkDir(d);     // 再深入子目录
}

console.log('[relink] 开始修复依赖链接（清单 ' + want.size + ' 项）...');

// 清单驱动：把 571 项按【父目录】分组排序后逐项修复。
// 分组使同一父目录下的链接连续处理，规避 Windows 对 junction 的目录句柄问题；
// 同时"缺失的链接位"也能被清单枚举到（不依赖目录遍历）。
const items = [...want.entries()];
function parentOf(rel) {
  const i = rel.lastIndexOf('/');
  return i > 0 ? rel.slice(0, i) : '';
}
items.sort((a, b) => {
  const pa = parentOf(a[0]), pb = parentOf(b[0]);
  if (pa !== pb) return pa < pb ? -1 : 1;
  return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
});
for (const [relp, relTgt] of items) fixOne(relp, relTgt);

// 清理清单里 stale 的历史残留链接
for (const s of mf.stale || []) {
  const p = path.join(NM, s.split('/').join(path.sep));
  if (exists(p) && isReparse(p)) {
    try { fs.rmdirSync(p); removedStale++; }
    catch (e) { console.log('  [警告] 清理残留失败 ' + s + ' : ' + e.message); }
  }
}

console.log('[relink] 完成：新建 ' + created + '，重建 ' + rebuilt + '，已正确跳过 ' + skipped + '，清理残留 ' + removedStale + '，失败 ' + fail);
if (fail > 0) {
  console.log('[relink] 有失败项：若提示 .pnpm 缺失请重新拷贝；否则重跑一次。');
  process.exit(2);
}
console.log('[relink] 依赖链接已就绪。');
