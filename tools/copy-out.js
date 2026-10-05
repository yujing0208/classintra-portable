// ClassIntra 绿色版 - 拷贝导出器
// 把本绿色版文件夹整体复制到目标位置（U盘/其他目录），保留依赖链接结构。
// 拷贝后到目标电脑上先跑 tools\relink.js（或直接双击启动脚本，会自动修复链接）。
// 用法：runtime\node\node.exe tools\copy-out.js <目标目录>
'use strict';
const fs = require('fs');
const path = require('path');

const SRC_ROOT = path.resolve(__dirname, '..'); // 绿色版根
const DIRS = ['server', 'client/dist', 'apps', 'market-apps', 'Resources', 'runtime', 'tools', 'captive'];
const FILES = ['启动ClassIntra.bat', '停止ClassIntra.bat', '使用说明.txt', '0-拷到U盘.bat', 'captive-启动.bat', 'captive-停止.bat', 'captive-使用说明.txt'];

const dstRoot = process.argv[2];
if (!dstRoot) {
  console.log('用法: runtime\\node\\node.exe tools\\copy-out.js <目标目录>');
  process.exit(1);
}

let total = 0, links = 0, errors = 0;
function report(force) {
  if (force || total % 500 === 0) {
    console.log(`  ...已复制 ${total} 个文件/链接${links ? '（含链接 ' + links + '）' : ''}`);
  }
}

function copyTree(src, dst) {
  let st;
  try { st = fs.lstatSync(src); } catch (e) { return; }
  if (st.isSymbolicLink()) {
    // 链接：复制为链接（目标位置保留，之后由 relink.js 按清单重定向）
    try {
      const tgt = fs.readlinkSync(src);
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.symlinkSync(tgt, dst, 'junction');
      links++; total++;
    } catch (e) {
      console.log('  [错误] 链接 ' + src + ' : ' + e.message); errors++;
    }
    return;
  }
  if (st.isDirectory()) {
    fs.mkdirSync(dst, { recursive: true });
    for (const ent of fs.readdirSync(src)) {
      copyTree(path.join(src, ent), path.join(dst, ent));
    }
    return;
  }
  // 普通文件
  try {
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
    total++;
  } catch (e) {
    console.log('  [错误] ' + src + ' : ' + e.message); errors++;
  }
  if (total % 500 === 0) report();
}

console.log('目标: ' + dstRoot);
for (const rel of DIRS) {
  const src = path.join(SRC_ROOT, rel);
  if (!fs.existsSync(src)) { console.log('  [跳过] 不存在: ' + rel); continue; }
  console.log('复制 ' + rel + ' ...');
  copyTree(src, path.join(dstRoot, rel));
}
for (const f of FILES) {
  const src = path.join(SRC_ROOT, f);
  if (fs.existsSync(src)) {
    try {
      fs.mkdirSync(dstRoot, { recursive: true });
      fs.copyFileSync(src, path.join(dstRoot, f)); total++;
    } catch (e) { console.log('  [错误] ' + f + ' : ' + e.message); errors++; }
  }
}
report(true);
console.log('复制完成：' + total + ' 项（含链接 ' + links + '），错误 ' + errors);
if (errors) process.exit(2);
