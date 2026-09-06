# Captive

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18.0.0-brightgreen.svg)](https://nodejs.org/)
[![Windows](https://img.shields.io/badge/Platform-Windows_10%2F11-0078d4.svg)](https://www.microsoft.com/)

> 校园热点 Captive Portal — 拦截 DNS 将学生设备透明重定向到 ClassIntra，支持开机自启与自动恢复

[ClassIntra](https://github.com/ClassIntra/ClassIntra) | [文档](https://classintra.github.io) | [QQ 群](http://qm.qq.com/cgi-bin/qm/qr?_wv=1027&k=y_6ndZUGpNu6dTuvpI4U3NQDs5FtIzIx&authKey=Tb2h7C6Ppe2r2WPKpvqLw1xnzjET5sfWBE45XjSvKOSJagX2WkkTx1Pat2EbqshZ&noverify=0&group_code=1074276021)

## 简介

Captive 是 [ClassIntra](https://github.com/ClassIntra/ClassIntra) 的配套工具，适用于校园热点场景。当学生设备连接到超脑的移动热点后，无需任何客户端配置，即可在 DNS 层自动将指定教育平台域名重定向到 ClassIntra 服务。

**典型使用场景：** 教师在课堂上开启电脑热点，学生平板连接后，访问学科网、畅言智慧课堂等平台时自动跳转到 ClassIntra 内网平台。

## 工作原理

```
学生设备（平板/手机）
  │
  ├─ DNS 查询："spark.changyan.com 的 IP 是什么？"
  │  └─ Captive 拦截 → 返回 192.168.137.1（教师电脑热点 IP）
  │
  └─ HTTPS 请求发往 192.168.137.1:443
     └─ Captive 终止 TLS → 转发明文 HTTP 到 localhost:9001（ClassIntra）
```

教师电脑上运行两个服务：

- **DNS 服务器**（UDP 53）— 拦截配置的域名，返回热点 IP（`192.168.137.1`），其他查询正常转发到上游 DNS
- **HTTPS 反向代理**（TCP 443）— 使用自签名证书终止 TLS，将请求透明转发到本地 ClassIntra 后端

## 功能特性

- DNS 层域名拦截 — 学生设备零配置
- HTTPS 反向代理 + TLS 终止
- WebSocket 代理支持
- 开机自动启动（Windows 计划任务）
- 看门狗自动崩溃恢复
- 热点状态监控（断线自动重启）
- 静默后台运行（无弹窗）
- 卸载时完整清理

## 环境要求

- **系统：** Windows 10 / 11
- **运行时：** [Node.js](https://nodejs.org/) >= 18.0.0
- **权限：** 管理员（绑定 53 和 443 端口需要）
- **后端：** ClassIntra 或其他本地服务运行在 `localhost:9001`

## 快速开始

### 1. 安装依赖

```bash
git clone https://github.com/ClassIntra/captive.git
cd captive
npm install
```

### 2. 生成 TLS 证书

```bash
# 方式一：PowerShell（管理员）
New-SelfSignedCertificate -DnsName "spark.changyan.com","ai.changyan.com","www.wjx.cn" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(5)

# 方式二：OpenSSL
openssl req -x509 -newkey rsa:2048 -keyout certs/key.pem -out certs/cert.pem -days 1825 -nodes -subj "/CN=spark.changyan.com"
```

### 3. 启动

```bash
# 交互模式（可见控制台窗口）
start-hotspot-redirect.bat

# 或直接用 Node.js（需要管理员权限）
node hotspot-redirect.js
```

### 4. 连接测试

1. 开启电脑移动热点（或让脚本自动开启）
2. 学生设备连接热点
3. 浏览器访问 `https://spark.changyan.com`
4. 接受自签名证书警告
5. 请求被转发到本地 ClassIntra（端口 9001）

## 开机自启动（推荐）

```bash
# 右键 → 以管理员身份运行
install-auto-start.bat
```

会创建两个 Windows 计划任务：

- **IR_Hotspot_Redirect** — 开机 30 秒后触发，静默模式运行
主任务本身配置了无限运行时间和任务级失败恢复，不再创建第二个周期恢复任务，避免多个看门狗同时运行。

### 卸载自启动

```bash
# 右键 → 以管理员身份运行
uninstall-auto-start.bat
```

## 配置说明

编辑 `hotspot-redirect.js` 中的 `CONFIG` 对象：

```javascript
const CONFIG = {
  interceptDomains: ['spark.changyan.com', 'ai.changyan.com', 'www.wjx.cn'],
  hotspotIP: '192.168.137.1',   // Windows 热点默认 IP
  dnsPort: 53,
  httpsPort: 443,
  upstreamDNS: '223.5.5.5',     // 阿里 DNS
  targetHost: 'localhost',
  targetPort: 9001,             // ClassIntra 后端端口
  certDir: path.join(__dirname, 'certs'),
};
```

### 添加拦截域名

在 `interceptDomains` 数组中添加，子域名自动匹配：

```javascript
interceptDomains: [
  'spark.changyan.com',    // 畅言智慧课堂
  'ai.changyan.com',       // 畅言 AI
  'www.wjx.cn',            // 问卷星
  'example.com',           // 自定义域名（同时匹配 *.example.com）
],
```

## 项目结构

```
captive/
├── hotspot-redirect.js          # 核心：DNS 服务器 + HTTPS 反向代理
├── watchdog.ps1                 # 健康监控（每 15 秒检查）
├── watchdog-loop.bat            # 外层包装：看门狗崩溃时自动重启
├── start-hotspot-redirect.bat   # 主启动脚本（交互 & 静默）
├── stop-hotspot-redirect.bat    # 优雅停止
├── start-hotspot.ps1            # WinRT API 启动移动热点
├── install-auto-start.bat       # 安装开机自启动
├── uninstall-auto-start.bat     # 卸载自启动
├── configure-task-recovery.ps1  # 配置任务无限制运行时间
├── launch-silent.vbs            # 计划任务静默启动器
├── debug-start.bat              # 调试用简化启动
├── certs/                       # TLS 证书（已 gitignore）
├── logs/                        # 运行日志（已 gitignore）
└── package.json
```

## 常见问题

### 端口 53 被占用

Windows 可能有 DNS 服务（SharedAccess/ICS）绑定到 53 端口：

1. **必须以管理员身份运行** — 绑定 53 和 443 端口需要管理员权限
2. **检查占用者：**

```powershell
Get-NetUDPEndpoint -LocalPort 53 | Select-Object OwningProcess, @{N='Process';E={(Get-Process $_.OwningProcess).ProcessName}}
```

### 热点频繁断开

看门狗会监控热点状态并在断线时自动重启。检查热点服务：

```powershell
Get-Service -Name SharedAccess
```

### 客户端证书警告

预期行为。代理使用自签名证书，客户端必须接受警告才能继续。

### 后端不可用（502）

ClassIntra 或其他后端服务必须在 `localhost:9001` 上运行。请先启动 ClassIntra 再启动 Captive。

## 相关项目

- [ClassIntra](https://github.com/ClassIntra/ClassIntra) — 校园内网 WebOS 平台
- [ClassIntra 文档](https://classintra.github.io) — 完整使用与部署指南

## 许可证

[MIT](LICENSE)
