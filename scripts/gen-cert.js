// ClassIntraPortable 便携版：自动生成 captive 自签名 TLS 证书
// 用法: node gen-cert.js <输出目录> [额外域名...]
// 输出: <输出目录>/cert.pem  <输出目录>/key.pem
// 无第三方 OpenSSL 依赖（纯 Node + node-forge，forge 已 vendor 于 scripts/vendor/）
'use strict';
var fs = require('fs');
var path = require('path');
var forge = require('./vendor/node-forge');

var outDir = process.argv[2];
if (!outDir) { console.error('用法: node gen-cert.js <输出目录> [额外域名...]'); process.exit(1); }
fs.mkdirSync(outDir, { recursive: true });

// 默认与 captive 默认拦截域名一致
var dnsNames = ['spark.changyan.com', 'ai.changyan.com', 'www.wjx.cn', 'zhixue.com', 'www.zhixue.com'];
// 常见子域泛匹配
var wildcards = ['*.changyan.com', '*.wjx.cn', '*.zhixue.com'];
for (var i = 3; i < process.argv.length; i++) {
  var extra = process.argv[i];
  if (dnsNames.indexOf(extra) === -1) dnsNames.push(extra);
}

console.log('[gen-cert] 生成自签名证书，覆盖域名:');
dnsNames.concat(wildcards).forEach(function (d) { console.log('  - ' + d); });

var keys = forge.pki.rsa.generateKeyPair(2048);
var cert = forge.pki.createCertificate();
cert.publicKey = keys.publicKey;
cert.serialNumber = '01' + Date.now().toString(16);

var now = new Date();
var notAfter = new Date(now.getTime() + 1825 * 24 * 3600 * 1000); // 5 年
cert.validity.notBefore = now;
cert.validity.notAfter = notAfter;

var attrs = [{ name: 'commonName', value: dnsNames[0] }];
cert.setSubject(attrs);
cert.setIssuer(attrs);

var altNames = [];
dnsNames.forEach(function (d) { altNames.push({ type: 2, value: d }); });
wildcards.forEach(function (d) { altNames.push({ type: 2, value: d }); });
cert.setExtensions([
  { name: 'basicConstraints', cA: false },
  { name: 'keyUsage', digitalSignature: true, keyEncipherment: true },
  { name: 'extKeyUsage', serverAuth: true },
  { name: 'subjectAltName', altNames: altNames }
]);

cert.sign(keys.privateKey, forge.md.sha256.create());

var certPem = forge.pki.certificateToPem(cert);
var keyPem = forge.pki.privateKeyToPem(keys.privateKey);

fs.writeFileSync(path.join(outDir, 'cert.pem'), certPem);
fs.writeFileSync(path.join(outDir, 'key.pem'), keyPem);
console.log('[gen-cert] 完成: ' + path.join(outDir, 'cert.pem') + ' / key.pem');
