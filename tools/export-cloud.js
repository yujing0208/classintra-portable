// ClassIntra 绿色版 - 云盘文件一键导出器
// ---------------------------------------------------------------
// 把 Resources\cloud 里所有用户上传的文件（图片 / 音频 / 视频）按
// 「原始文件名 + 归属用户」导出到一个独立文件夹，可用来备份、迁移、
// 或者离线翻看（比如把班里传的照片一次性拷走）。
//
// 为什么要读数据库：云盘的物理文件是「内容寻址」的 ——
//   Resources\cloud\shared\<哈希前2位>\<sha256>.<扩展名>
// 光看磁盘只能拿到一串哈希，拿不到真实文件名、上传者、分组。这些
// 全在 server\database\classintra.db 里，所以要连库一起读。
//
// 用法：
//   runtime\node\node.exe tools\export-cloud.js [选项]
//   或直接双击包根目录的  提取云盘文件.bat
//
// 选项：
//   --root <dir>       绿色版根目录（默认脚本的上一级）
//   --out  <dir>       导出目录（默认 <root>\云盘导出_<时间戳>）
//   --db   <file>      指定数据库文件（默认自动查找）
//   --mode byuser|flat|both   导出布局，默认 byuser
//                        byuser = 按用户分文件夹（含分组层级）
//                        flat   = 所有文件平铺一份，清单里标注归属
//                        both   = 两种都要（文件会复制两份）
//   --no-trash         不导出回收站（.trash）
//   --no-legacy        不导出旧版 <用户ID>\photos 目录
//   --with-tmp         连 .tmp（正在上传、尚未处理完的临时文件）一起导出
//   --move             移动而不是复制（危险：文件会从云盘消失，默认关闭）
//   --dry-run          只扫描并出清单，不实际复制
//   --no-open          结束后不自动打开导出文件夹
// ---------------------------------------------------------------
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync, spawn } = require('child_process');

const LOG = [];
function log(s) { LOG.push(String(s)); console.log(s); }
function die(s) { log(s); flushLog(); process.exit(1); }

let OUT_DIR = '';
function flushLog() {
  try {
    if (OUT_DIR && fs.existsSync(OUT_DIR)) {
      fs.writeFileSync(path.join(OUT_DIR, '导出日志.txt'), LOG.join('\r\n') + '\r\n', 'utf8');
    }
  } catch (e) { /* ignore */ }
}

// ---------------------------------------------------------------- 参数
const argv = process.argv.slice(2);
const opts = {
  root: '', out: '', db: '', mode: 'byuser',
  trash: true, legacy: true, tmp: false,
  move: false, open: true, dryRun: false,
};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--root') opts.root = argv[++i] || '';
  else if (a === '--out') opts.out = argv[++i] || '';
  else if (a === '--db') opts.db = argv[++i] || '';
  else if (a === '--mode') opts.mode = String(argv[++i] || '').toLowerCase();
  else if (a === '--no-trash') opts.trash = false;
  else if (a === '--no-legacy') opts.legacy = false;
  else if (a === '--with-tmp') opts.tmp = true;
  else if (a === '--move') opts.move = true;
  else if (a === '--dry-run') opts.dryRun = true;
  else if (a === '--no-open') opts.open = false;
  else if (a === '-h' || a === '--help') { printHelp(); process.exit(0); }
}
if (['flat', 'byuser', 'both'].indexOf(opts.mode) === -1) opts.mode = 'byuser';

function printHelp() {
  console.log('用法: runtime\\node\\node.exe tools\\export-cloud.js [选项]');
  console.log('  --mode byuser|flat|both   导出布局（默认 byuser）');
  console.log('  --out <dir>               指定导出目录');
  console.log('  --no-trash                不导出回收站');
  console.log('  --no-legacy               不导出旧版 photos 目录');
  console.log('  --with-tmp                连上传中的临时文件一起导出');
  console.log('  --move                    移动而非复制（危险）');
  console.log('  --dry-run                 只出清单，不复制');
}

// ---------------------------------------------------------------- 路径
const ROOT = path.resolve(opts.root || path.join(__dirname, '..'));
const RES_DIR = process.env.RESOURCES_DIR ? path.resolve(process.env.RESOURCES_DIR) : path.join(ROOT, 'Resources');
const CLOUD = path.join(RES_DIR, 'cloud');
const SHARED = path.join(CLOUD, 'shared');
const TRASH = path.join(CLOUD, '.trash');
const TMPDIR = path.join(CLOUD, '.tmp');

const stamp = (() => {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '_' + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
})();
OUT_DIR = path.resolve(opts.out || path.join(ROOT, '云盘导出_' + stamp));

log('====================================================');
log(' ClassIntra 云盘文件导出');
log('====================================================');
log('绿色版根目录 : ' + ROOT);
log('云盘目录     : ' + CLOUD);
log('导出到       : ' + OUT_DIR);
log('导出布局     : ' + opts.mode);
log('导出方式     : ' + (opts.dryRun ? '仅扫描（dry-run）' : (opts.move ? '移动（原文件会被移除）' : '复制（原文件保留）')));
log('');

if (!fs.existsSync(CLOUD)) {
  die('[错误] 找不到云盘目录：' + CLOUD + '\n       请确认 --root 指向绿色版根目录（里面有 runtime / server / Resources）。');
}
if (opts.move) {
  log('[警告] 启用 --move：导出成功后文件会从云盘移走，正在运行的服务可能报“文件不存在”。');
  log('');
}

// ------------------------------------------------------------ 数据库
function findDb() {
  if (opts.db) return path.resolve(opts.db);
  const dir = path.join(ROOT, 'server', 'database');
  if (!fs.existsSync(dir)) return '';
  const cands = fs.readdirSync(dir).filter(f => /\.db$/i.test(f) && !/-wal$|-shm$/i.test(f));
  if (!cands.length) return '';
  // 优先 classintra.db
  const main = cands.find(f => /^classintra\.db$/i.test(f));
  return path.join(dir, main || cands[0]);
}

const meta = {
  dbReady: false,
  dbPath: findDb(),
  files: new Map(),   // hash -> { owner_user_id, original_name, size, mime_type, storage_path, deleted }
  refs: new Map(),    // user_id -> [ { file_hash, display_name, folder } ]
  users: new Map(),   // user_id -> { net_name, real_name }
  folders: new Map(), // user_id + '\u0000' + name -> hidden(bool)
};

(function loadDb() {
  if (!meta.dbPath || !fs.existsSync(meta.dbPath)) {
    log('[提示] 没找到数据库文件，将退化为「按哈希文件名」导出（拿不到真实文件名和归属）。');
    log('');
    return;
  }
  let db = null;
  try {
    // 优先用绿色版自带的 better-sqlite3（已按内置 Node 编译好）；
    // 找不到就退回普通 require（走 NODE_PATH / 全局模块）
    let Database = null;
    const modPath = path.join(ROOT, 'server', 'node_modules', 'better-sqlite3');
    try {
      Database = require(modPath);
    } catch (e1) {
      Database = require('better-sqlite3');
    }
    try {
      db = new Database(meta.dbPath, { readonly: true, fileMustExist: true });
    } catch (e) {
      log('[提示] 只读方式打开数据库失败（' + e.message + '），改用普通方式打开。');
      db = new Database(meta.dbPath, { fileMustExist: true });
    }
  } catch (e) {
    log('[提示] 无法加载 SQLite 驱动（' + e.message + '），退化为按哈希导出。');
    log('       这不影响文件能否导出，只是文件名会是哈希、没有归属信息。');
    log('');
    return;
  }

  try {
    for (const r of db.prepare('SELECT hash, owner_user_id, original_name, size, mime_type, storage_path, deleted FROM cloud_files').all()) {
      meta.files.set(String(r.hash).toLowerCase(), r);
    }
    for (const r of db.prepare('SELECT user_id, file_hash, display_name, folder FROM cloud_user_files').all()) {
      const k = String(r.user_id);
      if (!meta.refs.has(k)) meta.refs.set(k, []);
      meta.refs.get(k).push({ file_hash: String(r.file_hash).toLowerCase(), display_name: r.display_name, folder: r.folder || '' });
    }
    try {
      for (const r of db.prepare('SELECT user_id, net_name, real_name FROM users').all()) {
        meta.users.set(String(r.user_id), { net_name: r.net_name, real_name: r.real_name });
      }
    } catch (e) { /* 用户表结构差异，忽略 */ }
    try {
      for (const r of db.prepare('SELECT user_id, name, hide_from_all FROM cloud_folders').all()) {
        meta.folders.set(String(r.user_id) + '\u0000' + String(r.name), !!r.hide_from_all);
      }
    } catch (e) { /* 忽略 */ }
    meta.dbReady = true;
  } catch (e) {
    log('[提示] 读取数据库失败（' + e.message + '），退化为按哈希导出。');
  } finally {
    try { db.close(); } catch (e) { /* ignore */ }
  }

  if (meta.dbReady) {
    log('数据库     : ' + meta.dbPath);
    log('  文件记录      : ' + meta.files.size);
    let refCount = 0;
    for (const [, arr] of meta.refs) refCount += arr.length;
    log('  用户文件引用  : ' + refCount);
    log('  用户数        : ' + meta.users.size);
    log('');
  }
})();

// ------------------------------------------------------------ 工具函数
function safeSeg(name, fallback) {
  let n = String(name == null ? '' : name).replace(/[\x00-\x1f]/g, '');
  n = n.replace(/[\\/:*?"<>|]/g, '_');
  n = n.replace(/^[\s.]+/, '');
  n = n.replace(/[\s.]+$/, '');
  if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$/i.test(n)) n = '_' + n;
  if (n.length > 100) {
    const ext = path.extname(n).slice(0, 16);
    n = n.slice(0, 100 - ext.length) + ext;
  }
  if (!n) n = fallback || '未命名';
  return n;
}

// 已规划的目标路径（规划阶段文件还没落盘，光看磁盘会把同名的算成同一个路径）
const RESERVED = new Set();

function uniqueTarget(dir, name) {
  const tryOne = (n) => {
    const t = path.join(dir, n);
    const key = t.toLowerCase();
    if (fs.existsSync(t) || RESERVED.has(key)) return '';
    RESERVED.add(key);
    return t;
  };
  let t = tryOne(name);
  if (t) return t;
  const ext = path.extname(name);
  const base = name.slice(0, name.length - ext.length);
  for (let i = 2; i < 10000; i++) {
    t = tryOne(base + ' (' + i + ')' + ext);
    if (t) return t;
  }
  return path.join(dir, base + '_' + Date.now() + ext);
}

function hashFromFileName(name) {
  const base = name.replace(/\.[^.\\/]+$/, '');
  const m = base.match(/[a-fA-F0-9]{64}/);
  return m ? m[0].toLowerCase() : '';
}

function human(bytes) {
  if (!bytes && bytes !== 0) return '-';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0, v = Number(bytes);
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(v >= 100 ? 0 : 1)) + ' ' + u[i];
}

// 递归列出文件
function listFiles(dir, depth) {
  const out = [];
  if (depth > 8) return out;
  let ents = [];
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return out; }
  for (const ent of ents) {
    const abs = path.join(dir, ent.name);
    try {
      if (ent.isDirectory()) out.push(...listFiles(abs, depth + 1));
      else if (ent.isFile()) out.push(abs);
      else if (ent.isSymbolicLink()) {
        const st = fs.statSync(abs);
        if (st.isFile()) out.push(abs);
      }
    } catch (e) { /* 跳过读不了的 */ }
  }
  return out;
}

// ------------------------------------------------------------ 扫描磁盘
log('正在扫描云盘文件 ...');
const diskByHash = new Map();   // hash -> { abs, size, name }
const diskUnhashed = [];        // 名字里没哈希的（可能是旧格式）
let diskBytes = 0;

if (fs.existsSync(SHARED)) {
  for (const abs of listFiles(SHARED, 0)) {
    let size = 0;
    try { size = fs.statSync(abs).size; } catch (e) { continue; }
    diskBytes += size;
    const name = path.basename(abs);
    const hash = hashFromFileName(name);
    if (hash) {
      if (!diskByHash.has(hash)) diskByHash.set(hash, { abs, size, name });
    } else {
      diskUnhashed.push({ abs, size, name });
    }
  }
}
log('云端实际文件 : ' + (diskByHash.size + diskUnhashed.length) + ' 个（' + human(diskBytes) + '）');
log('');

// ------------------------------------------------------------ 规划
const plan = [];          // { src, dst, hash, name, user_id, user_name, folder, kind, status }
const missing = [];       // 数据库有记录但磁盘没有

// 被至少一个用户引用过的哈希 —— 「未归属」就是判定这个
// 统一转小写：磁盘文件名提取出来的是小写，而库里的 file_hash 理论上都是小写，
// 但一旦有大写混进来，Set.has() 就会永远匹配不上，把有引用的文件误判成未归属。
const referencedHashes = new Set();
for (const [, arr] of meta.refs) {
  for (const r of arr) referencedHashes.add(String(r.file_hash).toLowerCase());
}

function userName(uid) {
  const u = meta.users.get(String(uid));
  if (!u) return '';
  return u.net_name || u.real_name || '';
}
function userFolder(uid) {
  const uidStr = String(uid);
  const nm = userName(uidStr);
  return safeSeg(nm ? nm + '_' + uidStr : uidStr, uidStr);
}
function srcOf(hash) {
  const f = meta.files.get(hash);
  if (f && f.storage_path) {
    const p = path.join(SHARED, String(f.storage_path).split('/').join(path.sep));
    if (fs.existsSync(p)) return p;
  }
  const d = diskByHash.get(hash);
  return d ? d.abs : '';
}
function realName(hash, fallbackName) {
  const f = meta.files.get(hash);
  if (f && f.original_name) return f.original_name;
  const d = diskByHash.get(hash);
  if (d) {
    // 哈希.ext -> 保留扩展名
    const ext = path.extname(d.name);
    return '未署名文件_' + hash.slice(0, 8) + ext;
  }
  return fallbackName || hash;
}

// 按用户导出时，优先用「用户自己云盘里显示的名字」—— 他在自己云盘看到的就是这个
function userVisibleName(hash, refDisplayName) {
  if (refDisplayName) return refDisplayName;
  return realName(hash);
}

// 1) 按用户导出
if (opts.mode === 'byuser' || opts.mode === 'both') {
  for (const [uid, refList] of meta.refs) {
    for (const ref of refList) {
      const hash = ref.file_hash;
      const src = srcOf(hash);
      const dispName = userVisibleName(hash, ref.display_name);
      if (!src) {
        missing.push({ hash, name: dispName, user_id: uid, folder: ref.folder });
        continue;
      }
      const parts = ['按用户', userFolder(uid)];
      if (ref.folder) parts.push(safeSeg(ref.folder, '未命名分组'));
      const dst = uniqueTarget(path.join(OUT_DIR, ...parts), safeSeg(dispName, hash));
      plan.push({
        src, dst, hash, name: dispName, user_id: uid, user_name: userName(uid),
        folder: ref.folder || '', kind: '用户文件', status: '正常',
      });
    }
  }
}

// 2) 平铺导出（每个物理文件一份）
//    是否「未归属」只看有没有用户引用（referencedHashes），跟平铺无关
const flatSeen = new Set();
if (opts.mode === 'flat' || opts.mode === 'both') {
  for (const [hash, d] of diskByHash) {
    if (flatSeen.has(hash)) continue;
    flatSeen.add(hash);
    const f = meta.files.get(hash);
    const owner = f ? String(f.owner_user_id) : '';
    const nm = realName(hash, d.name);
    const dst = uniqueTarget(path.join(OUT_DIR, '文件'), safeSeg(nm, hash));
    plan.push({
      src: d.abs, dst, hash, name: nm, user_id: owner, user_name: userName(owner),
      folder: '', kind: '平铺', status: f && f.deleted === 1 ? '已标记删除' : '正常',
    });
  }
}

// 3) 未归属 / 未入库（磁盘上有，但没有任何用户的云盘引用它）
//
//    ⚠️ 「未归属」的准确含义是「没有人的云盘里挂着它」，**不等于**「不知道谁传的」。
//    cloud_files.owner_user_id 里通常就是原上传者本人。
//    这里进一步判定"为什么会变成无引用"，并把结论写进子目录名和清单，
//    免得只看到「未归属」三个字一头雾水。
const trashHashes = new Set();
if (fs.existsSync(TRASH)) {
  for (const abs of listFiles(TRASH, 0)) {
    const h = hashFromFileName(path.basename(abs));
    if (h) trashHashes.add(h);
  }
}

function classifyOrphan(hash, f) {
  if (!f) {
    return {
      reason: '未入库', status: '未入库',
      why: '数据库里没有这条记录：上传处理中途被打断（文件已经落盘、还没登记入库），或是从别的机器同步进来后尚未补登记。',
    };
  }
  const owner = String(f.owner_user_id || '');
  if (owner === '__sync__') {
    return { reason: '跨端同步', status: '无用户引用', why: '通过中继从其它机器同步进来的文件，本地没有人引用它。' };
  }
  if (owner === '__system__') {
    return { reason: '系统资源', status: '无用户引用', why: '从系统资源或相册导入的文件，归属被标记为系统。' };
  }
  if (f.deleted === 1) {
    if (trashHashes.has(hash)) {
      return {
        reason: '重复删除残留', status: '已标记删除（未清理）',
        why: '这个文件被删过不止一次 —— 回收站里还留着更早那份副本（而回收站从不清理）。'
          + '最后一次删除时要把文件搬进回收站，搬运却失败了，失败被静默忽略，文件就留在 shared 里。',
      };
    }
    return {
      reason: '软删未搬走', status: '已标记删除（未清理）',
      why: '已被标记删除、用户引用也清空了，但物理文件没有搬进回收站 —— 搬运失败被静默忽略。'
        + '最常见的原因是删除的瞬间有人正在预览或下载这张文件，Windows 会锁住它，rename 就失败了。',
    };
  }
  return {
    reason: '引用丢失', status: '无用户引用',
    why: '文件本身没被标记删除，但所有用户的云盘引用都被清掉了。最常见的原因是：'
      + '上传者删除自己的文件时被当成「非本人」处理，于是只删掉引用、没删物理文件。',
  };
}

const orphans = [];
for (const [hash, d] of diskByHash) {
  if (referencedHashes.has(hash)) continue;
  const f = meta.files.get(hash);
  const owner = f ? String(f.owner_user_id) : '';
  const cls = classifyOrphan(hash, f);
  const segs = ['未归属', cls.reason];
  // 原上传者是真实用户时再多分一层，一眼看出"这是谁传的"
  if (owner && owner !== '__sync__' && owner !== '__system__') {
    segs.push('原上传者_' + userFolder(owner));
  }
  const nm = realName(hash, d.name);
  const dst = uniqueTarget(path.join(OUT_DIR, ...segs.map(s => safeSeg(s, '未知'))), safeSeg(nm, hash));
  orphans.push({
    src: d.abs, dst, hash, name: nm, user_id: owner, user_name: userName(owner),
    folder: '', kind: '未归属', status: cls.status,
    reason: cls.reason, why: cls.why,
  });
}
plan.push(...orphans);

// 4) 数据库里有记录、但磁盘上根本没有的文件（含没有任何用户引用的）
for (const [hash, f] of meta.files) {
  if (diskByHash.has(hash)) continue;
  if (missing.some(m => m.hash === hash)) continue;
  // shared 里找不到，但文件可能躺在回收站里 —— 那就不算真的丢了
  let mstat = '磁盘上找不到文件';
  if (trashHashes.has(hash)) mstat = '已删除（文件在回收站）';
  else if (f.deleted === 1) mstat = '已标记删除（无物理文件）';
  missing.push({
    hash, name: f.original_name || hash, user_id: String(f.owner_user_id || ''),
    folder: '', size: f.size, deleted: f.deleted, status: mstat,
  });
}

// 5) 没有哈希的文件名（极老版本残留）
for (const d of diskUnhashed) {
  const dst = uniqueTarget(path.join(OUT_DIR, '未归属', '无哈希文件名'), safeSeg(d.name, '未命名'));
  plan.push({
    src: d.abs, dst, hash: '', name: d.name, user_id: '', user_name: '',
    folder: '', kind: '未归属', status: '旧格式',
  });
}

// 6) 回收站
if (opts.trash && fs.existsSync(TRASH)) {
  for (const abs of listFiles(TRASH, 0)) {
    let size = 0;
    try { size = fs.statSync(abs).size; } catch (e) { continue; }
    const hash = hashFromFileName(path.basename(abs));
    const f = hash ? meta.files.get(hash) : null;
    const nm = f && f.original_name ? f.original_name : path.basename(abs);
    const dst = uniqueTarget(path.join(OUT_DIR, '回收站'), safeSeg(nm, '未命名'));
    plan.push({
      src: abs, dst, hash, name: nm,
      user_id: f ? String(f.owner_user_id) : '', user_name: f ? userName(f.owner_user_id) : '',
      folder: '', kind: '回收站', status: '已删除',
    });
  }
}

// 7) 旧版 <用户ID>\photos 目录
if (opts.legacy && fs.existsSync(CLOUD)) {
  let dirs = [];
  try { dirs = fs.readdirSync(CLOUD, { withFileTypes: true }); } catch (e) { /* ignore */ }
  for (const ent of dirs) {
    if (!ent.isDirectory()) continue;
    if (ent.name === 'shared' || ent.name === '.trash' || ent.name === '.tmp' || ent.name.startsWith('.')) continue;
    const legacyRoot = path.join(CLOUD, ent.name);
    for (const abs of listFiles(legacyRoot, 0)) {
      const rel = path.relative(legacyRoot, abs);
      const segs = ['旧版数据', safeSeg(ent.name, '未知')].concat(
        rel.split(path.sep).slice(0, -1).map(s => safeSeg(s, '数据'))
      );
      const dst = uniqueTarget(path.join(OUT_DIR, ...segs), safeSeg(path.basename(abs), '未命名'));
      plan.push({
        src: abs, dst, hash: hashFromFileName(path.basename(abs)), name: path.basename(abs),
        user_id: ent.name, user_name: userName(ent.name), folder: '', kind: '旧版数据', status: '旧版',
      });
    }
  }
}

// 8) 临时目录（默认跳过）
let tmpSkipped = 0;
if (fs.existsSync(TMPDIR)) {
  const tmpFiles = listFiles(TMPDIR, 0);
  if (opts.tmp) {
    for (const abs of tmpFiles) {
      const dst = uniqueTarget(path.join(OUT_DIR, '上传临时区'), safeSeg(path.basename(abs), '未命名'));
      plan.push({ src: abs, dst, hash: '', name: path.basename(abs), user_id: '', user_name: '', folder: '', kind: '暂存', status: '上传中/未完成' });
    }
  } else {
    tmpSkipped = tmpFiles.length;
  }
}

// ------------------------------------------------------------ 汇总
let planBytes = 0;
for (const p of plan) { try { planBytes += fs.statSync(p.src).size; } catch (e) { /* ignore */ } }

log('----------------------------------------------------');
log('导出计划');
log('----------------------------------------------------');
log('待导出文件   : ' + plan.length + ' 个（' + human(planBytes) + '）');
const byKind = {};
for (const p of plan) byKind[p.kind] = (byKind[p.kind] || 0) + 1;
for (const k of Object.keys(byKind)) log('  ' + k + ' : ' + byKind[k]);
if (missing.length) log('数据库有记录但磁盘缺失 : ' + missing.length + ' 个');
if (tmpSkipped) log('跳过上传临时区文件     : ' + tmpSkipped + ' 个（要一起导出加 --with-tmp）');
if (orphans.length) {
  log('');
  log('未归属 ' + orphans.length + ' 个（文件都在磁盘上，只是没有任何用户的云盘引用它）：');
  const od = new Map();
  for (const o of orphans) od.set(o.reason, (od.get(o.reason) || 0) + 1);
  for (const [r, n] of [...od.entries()].sort((a, b) => b[1] - a[1])) {
    log('  ' + r + ' : ' + n + ' 个');
  }
  log('  每个文件的原因说明见 清单.csv 的「原因」「原因说明」两列');
}
log('');

if (opts.dryRun) {
  log('[dry-run] 未复制任何文件。去掉 --dry-run 即可真正导出。');
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
  writeManifest();
  flushLog();
  log('清单已写入 : ' + path.join(OUT_DIR, '清单.csv'));
  process.exit(0);
}

// ------------------------------------------------------------ 执行
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

let done = 0, failed = 0;
const failures = [];
const t0 = Date.now();
// 移动模式下，同一份物理文件可能被多个用户引用：
// 第一次真的移动，后续从「已导出的那份」复制，避免第二个用户扑空
const moveCache = new Map();

for (const p of plan) {
  try {
    fs.mkdirSync(path.dirname(p.dst), { recursive: true });
    // 路径过长保护（Windows MAX_PATH 260）
    let dst = p.dst;
    if (dst.length > 250) {
      const dir = path.dirname(dst);
      const ext = path.extname(dst).slice(0, 12);
      dst = path.join(dir, '长名文件_' + String(p.hash || '').slice(0, 8) + ext);
      dst = uniqueTarget(dir, path.basename(dst));
    }
    if (opts.move) {
      const cached = p.hash ? moveCache.get(p.hash) : '';
      if (cached && fs.existsSync(cached)) {
        fs.copyFileSync(cached, dst);
      } else {
        try { fs.renameSync(p.src, dst); }
        catch (e) { fs.copyFileSync(p.src, dst); fs.unlinkSync(p.src); }
        if (p.hash) moveCache.set(p.hash, dst);
      }
    } else {
      fs.copyFileSync(p.src, dst);
    }
    p.dst = dst;
    p.exported = path.relative(OUT_DIR, dst);
    done++;
  } catch (e) {
    failed++;
    p.exported = '';
    p.status = '导出失败: ' + e.message;
    failures.push(p.src + ' -> ' + e.message);
  }
  if (done % 100 === 0 && done > 0) log('  ...已导出 ' + done + ' / ' + plan.length);
}

const secs = ((Date.now() - t0) / 1000).toFixed(1);

// ------------------------------------------------------------ 清单
function csvEsc(v) {
  const s = v == null ? '' : String(v);
  return '"' + s.replace(/"/g, '""') + '"';
}

function writeManifest() {
  const head = ['序号', '文件哈希', '原始文件名', '大小(字节)', '大小', '类型', '归属用户ID', '归属用户名', '分组', '类别', '状态', '原因', '原因说明', '源文件路径', '导出相对路径'];
  const rows = [head.map(csvEsc).join(',')];
  let i = 0;
  for (const p of plan) {
    i++;
    let sz = '';
    try { sz = fs.statSync(opts.move ? p.src : p.src).size; } catch (e) { sz = ''; }
    rows.push([
      i, p.hash, p.name, sz, human(sz === '' ? 0 : sz),
      (meta.files.get(p.hash) || {}).mime_type || '',
      p.user_id, p.user_name, p.folder, p.kind, p.status,
      p.reason || '', p.why || '',
      p.src, p.exported || '',
    ].map(csvEsc).join(','));
  }
  if (missing.length) {
    rows.push('');
    rows.push(csvEsc('--- 数据库有记录，但磁盘上找不到文件 ---'));
    for (const m of missing) {
      rows.push(['', m.hash, m.name, (m.size || ''), human(m.size || 0), '', m.user_id, userName(m.user_id), m.folder || '', '缺失', m.status || '磁盘上找不到文件', '磁盘缺失', '数据库里有这条记录，但 shared 目录里没有对应的物理文件；如果它出现在回收站目录里，说明是删除后没清理干净。', '', ''].map(csvEsc).join(','));
    }
  }
  // 带 BOM，Excel 打开中文才不乱码
  fs.writeFileSync(path.join(OUT_DIR, '清单.csv'), '\ufeff' + rows.join('\r\n') + '\r\n', 'utf8');
}

writeManifest();

// ------------------------------------------------------------ 说明
const readme = [];
readme.push('ClassIntra 云盘导出说明');
readme.push('='.repeat(46));
readme.push('');
readme.push('导出时间   : ' + new Date().toLocaleString('zh-CN'));
readme.push('绿色版根目录: ' + ROOT);
readme.push('导出布局   : ' + opts.mode);
readme.push('导出方式   : ' + (opts.move ? '移动（原云盘文件已移除）' : '复制（原云盘文件保留）'));
readme.push('');
readme.push('目录结构');
readme.push('-'.repeat(46));
if (opts.mode === 'byuser' || opts.mode === 'both') {
  readme.push('按用户/                每个用户一个文件夹，文件名 = 真实上传名');
  readme.push('                       里面按用户在云盘里建的分组再分一层');
  readme.push('                       同一个文件被多人转存时，会在多人的文件夹里各出现一份');
}
if (opts.mode === 'flat' || opts.mode === 'both') {
  readme.push('文件/                  所有物理文件各一份，重名自动加序号');
}
readme.push('未归属/                磁盘上有、但没有任何用户的云盘引用它的文件');
readme.push('                       ⚠ 这不等于「不知道谁传的」—— 原上传者就写在');
readme.push('                       清单.csv 的「归属用户名」列里。子目录按原因分：');
readme.push('                         重复删除残留/  删过又重传又删，回收站的旧副本挡住了搬运');
readme.push('                         软删未搬走/    标记为已删除，但物理文件没搬进回收站');
readme.push('                         引用丢失/      文件没被标记删除，用户引用却被清空了');
readme.push('                         跨端同步/      通过中继从别的机器同步进来的');
readme.push('                         系统资源/      从系统资源或相册导入的');
readme.push('                         未入库/        数据库里没有这条记录');
readme.push('                       原上传者若是本班同学，会在原因下再分一层');
readme.push('                       「原上传者_姓名_学号」');
readme.push('                       这些文件内容都是完整的，直接就能用。');
readme.push('回收站/                已删除但还没被清理的文件');
readme.push('旧版数据/              早期版本 <用户ID>\\photos 里的文件');
if (opts.tmp) readme.push('上传临时区/            导出时正在上传、尚未处理完的文件');
readme.push('清单.csv               全部文件的明细（Excel 直接打开）');
readme.push('导出日志.txt           本次运行的完整日志');
readme.push('');
readme.push('统计');
readme.push('-'.repeat(46));
readme.push('导出文件数 : ' + done + ' 个');
readme.push('导出总量   : ' + human(planBytes));
readme.push('失败       : ' + failed + ' 个');
if (orphans.length) {
  readme.push('未归属     : ' + orphans.length + ' 个（文件在磁盘上、但没有任何用户引用它）');
  const dist = new Map();
  for (const o of orphans) dist.set(o.reason, (dist.get(o.reason) || 0) + 1);
  for (const [r, n] of [...dist.entries()].sort((a, b) => b[1] - a[1])) {
    readme.push('             · ' + r + ' : ' + n + ' 个');
  }
}
if (missing.length) readme.push('记录缺失   : ' + missing.length + ' 个（数据库有记录，磁盘找不到文件）');
if (tmpSkipped) readme.push('已跳过     : 上传临时区 ' + tmpSkipped + ' 个文件');
readme.push('');
readme.push('几点说明');
readme.push('-'.repeat(46));
readme.push('1. 云盘的物理文件是「按内容哈希」存的，磁盘上只有一串名字，');
readme.push('   真实文件名 / 上传者 / 分组都记在 server\\database\\classintra.db 里。');
readme.push('   所以本脚本是「读数据库 + 拷文件」两件事一起做。');
readme.push('2. 服务运行中导出是安全的：数据库以只读方式打开，不影响正在跑的服务。');
readme.push('3. 文件和记录对不上时会分别处理：');
readme.push('   磁盘有、库里没有  -> 进「未归属\\未入库」');
readme.push('   磁盘有、库里有人  -> 但所有用户引用都没了，按具体原因归进「未归属」下的子目录');
readme.push('                        （详见清单.csv 的「原因」「原因说明」两列）');
readme.push('   库里有、磁盘没有  -> 只记进清单；若它在回收站里会标注「已删除（文件在回收站）」');
readme.push('4. 默认跳过上传临时区（.tmp），那里是正在上传、还没处理完的文件。');
readme.push('5. 导出的是全部文件，包含所有人上传的内容。请自己注意隐私，别乱发。');
fs.writeFileSync(path.join(OUT_DIR, '说明.txt'), '\ufeff' + readme.join('\r\n') + '\r\n', 'utf8');

// ------------------------------------------------------------ 收尾
log('');
log('----------------------------------------------------');
log('导出完成');
log('----------------------------------------------------');
log('成功 : ' + done + ' 个（' + human(planBytes) + '）');
log('失败 : ' + failed + ' 个');
if (failures.length) {
  log('失败明细（最多 20 条）:');
  for (const f of failures.slice(0, 20)) log('  ' + f);
}
log('耗时 : ' + secs + ' 秒');
log('位置 : ' + OUT_DIR);
log('');
flushLog();

if (opts.open) {
  try {
    spawn('explorer.exe', [OUT_DIR], { detached: true, stdio: 'ignore' }).unref();
  } catch (e) { /* ignore */ }
}

if (failed) process.exit(2);
