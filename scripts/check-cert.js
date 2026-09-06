'use strict';
// 诊断用：检查 captive TLS 证书是否存在、能否加载、是否在有效期内
// 用法: node check-cert.js <certs目录>
// 退出码: 0=正常 1=有问题 2=用法错误
const path = require('path');
const fs = require('fs');
const forge = require('./vendor/node-forge');

const certDir = process.argv[2];
if (!certDir) { console.error('用法: node check-cert.js <certs目录>'); process.exit(2); }
const certPath = path.join(certDir, 'cert.pem');
const keyPath = path.join(certDir, 'key.pem');

const hasCert = fs.existsSync(certPath);
const hasKey = fs.existsSync(keyPath);
let ok = true;

console.log('   文件: cert.pem ' + (hasCert ? '存在' : '缺失') + ' | key.pem ' + (hasKey ? '存在' : '缺失'));
if (!hasCert || !hasKey) {
  console.log('   [失败] 证书不完整。处理: 删除 apps\\captive\\certs 目录后重跑 5-captive热点劫持-启动.bat 自动生成');
  process.exit(1);
}

try {
  const certPem = fs.readFileSync(certPath, 'utf8');
  const keyPem = fs.readFileSync(keyPath, 'utf8');
  const cert = forge.pki.certificateFromPem(certPem);
  forge.pki.privateKeyFromPem(keyPem);

  // 主体 CN 与 SAN 域名
  let cn = '(无)';
  try { cn = cert.subject.getField('CN') ? cert.subject.getField('CN').value : '(无)'; } catch (e) {}
  let altNames = '(无)';
  try {
    const sans = cert.getExtension('subjectAltName');
    altNames = sans ? sans.altNames.map(a => a.value).join(', ') : '(无)';
  } catch (e) {}

  const fmt = (d) => d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0');
  const now = Date.now();
  const before = cert.validity.notBefore.getTime();
  const after = cert.validity.notAfter.getTime();
  const days = Math.ceil((after - now) / 86400000);

  console.log('   证书 CN: ' + cn);
  console.log('   覆盖域名(SAN): ' + altNames);
  console.log('   有效期: ' + fmt(cert.validity.notBefore) + ' ~ ' + fmt(cert.validity.notAfter) + '（剩余 ' + days + ' 天）');
  if (now < before) {
    console.log('   [失败] 证书尚未生效（系统时间可能被改错）。处理: 校正系统时间后重新生成证书');
    ok = false;
  } else if (now > after) {
    console.log('   [失败] 证书已过期。处理: 删除 apps\\captive\\certs 目录后重跑 5-captive热点劫持-启动.bat 自动重生成');
    ok = false;
  } else {
    console.log('   [OK] 证书可正常加载，私钥匹配');
  }
} catch (e) {
  console.log('   [失败] 证书解析出错或私钥不匹配: ' + e.message);
  console.log('          处理: 删除 apps\\captive\\certs 目录后重跑 5-captive热点劫持-启动.bat 重新生成');
  ok = false;
}
process.exit(ok ? 0 : 1);
