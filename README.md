<p align="center">
  <img src="apps/ClassIntra/Banner.png" alt="ClassIntra 便携版" width="100%">
</p>

<h1 align="center">ClassIntra 便携版</h1>
<p align="center"><strong>校园内网 WebOS · U 盘即插即用</strong> — 无需外网、无需安装，双击即运行</p>

<div align="center">

[![上游 ClassIntra](https://img.shields.io/badge/upstream-ClassIntra%2FClassIntra-blue?style=for-the-badge)](https://github.com/ClassIntra/ClassIntra)
[![上游 captive](https://img.shields.io/badge/upstream-ClassIntra%2Fcaptive-blue?style=for-the-badge)](https://github.com/ClassIntra/captive)
[![开源许可](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)

</div>

---

## 这是什么

把 **ClassIntra**（校园内网 WebOS，MIT）与其官方 **captive** 热点劫持组件（MIT）打包成一个**绿色便携工程**：

- 自带依赖安装/修复逻辑，拷贝到任何 Windows 10/11（64 位）电脑即可运行
- 支持“U 盘即插即用”：学校电脑没网、没开发环境也能用
- 内置 captive 集成：教师机开热点，学生平板访问智学网 / 畅言 / 问卷星等域名时自动转到本机 ClassIntra

本仓库是**完整可复现的源码工程**：`apps/` 下是两个上游的干净源码快照，根目录是便携化封装脚本与文档。克隆后按下方步骤即可自行构建出一份便携包。

## 目录结构

```
classintra-portable/
├─ 1-安装初始化.bat            首次使用：装依赖 + 生成配置 + 构建前端
├─ 2-启动ClassIntra.bat        前台启动服务器并打开浏览器
├─ 3-停止ClassIntra.bat        停止前台服务器
├─ 4-更新代码.bat              在线更新源码（需本机装 git）
├─ 5-captive热点劫持-启动.bat  热点劫持前台调试（管理员）
├─ 5.2-captive守护安装.bat     热点劫持无窗口守护（装/卸，推荐）
├─ 5.5-captive诊断.bat         服务失败时一键查原因（管理员）
├─ 6-停止Captive.bat           停止热点劫持
├─ 7-安装守护与开机自启.bat     ClassIntra 守护 + 开机自动恢复
├─ 8-查看状态与日志.bat         PM2 状态与日志
├─ 8-卸载守护.bat               卸载守护与开机自启
├─ 9-安全退出.bat               停止所有服务，U 盘弹出前必做
├─ apps/
│  ├─ ClassIntra/              上游 ClassIntra 源码（MIT，含 .npmrc 国内镜像增强）
│  └─ captive/                 上游 captive 源码（MIT，含智学网域名增强）
├─ scripts/                     自研辅助脚本（证书生成/检查、开机自启）
├─ docs/
│  ├─ 便携版使用说明.txt        便携版完整操作说明（首次使用/守护/U盘）
│  └─ captive-说明.txt          captive 热点劫持完整说明
└─ LICENSE                      MIT（含上游版权声明）
```

## 快速开始（从源码构建便携包）

> 便携包 = 本仓库 + 一个内置 Node 运行时目录 `runtime\`。运行时体积大不入库，
> 首次构建时按下面方法放入即可（一次性）。

**前置：Windows 10/11（64 位）电脑，能联网（仅首次构建需要）。**

1. 克隆本仓库到目标文件夹（如 `D:\ClassIntraPortable`）
2. 放入内置 Node 运行时：
   - 下载 [Node.js LTS Windows x64 zip](https://nodejs.org/dist/)（如 `node-v20.x-win-x64.zip`）
   - 解压后把 `node.exe` 所在目录放为 `runtime\node\`（即存在 `runtime\node\node.exe`）
   - 使 `runtime\node\` 内可用 `pnpm`：将 `node.exe` 同级放一份 `pnpm.cjs`，或在 `node_modules\pnpm\bin\pnpm.cjs`；脚本已按此约定查找
3. 双击 `1-安装初始化.bat`，自动完成：安装依赖（国内镜像）→ 生成 `server\.env` → 初始化数据库 → 构建前端
4. 双击 `2-启动ClassIntra.bat` → 浏览器自动打开 `http://localhost:9001`

之后整个文件夹可随意拷贝/移动（U 盘也行），到新电脑双击 `2-启动` 即可，无需重装。

## 教室上课场景（captive 热点劫持）

1. 部署：`1-安装初始化` → `7-安装守护与开机自启`（ClassIntra 常驻）
2. 本机开 Windows“移动热点”，学生平板连上
3. 右键 `5.2-captive守护安装.bat` → 以管理员身份运行 → 选 1（无窗口守护）
4. 学生访问 `ai.changyan.com` / `www.wjx.cn` / `zhixue.com` 等域名 → 自动跳转到本机 ClassIntra（DNS+HTTPS 劫持，学生设备零配置）
5. 下课：`9-安全退出.bat` 再关热点

详细原理、排障、证书安装到平板的说明见 `docs/captive-说明.txt`。

## captive 证书说明

captive 的 HTTPS 反代使用**自签名证书**，由 `scripts/gen-cert.js` 首次运行自动生成到
`apps/captive/certs/`（纯 Node 实现，无需 OpenSSL；覆盖拦截域名含智学网）。

⚠️ 证书私钥 `key.pem` 只在运行时生成，**从不入库**（已在 .gitignore 排除）。

## 常见问题

- **启动提示“找不到 runtime\node\node.exe”** → 未放入内置 Node 运行时，见“快速开始”第 2 步。
- **依赖修复失败** → 用 `1-安装初始化.bat` 重跑；便携包移动后脚本会自动修复 pnpm 链接。
- **端口被占用** → 编辑 `apps\ClassIntra\server\.env` 的 `PORT / WS_PORT / RELAY_PORT`。
- **想清空数据重来** → 停止服务后删除 `apps\ClassIntra\server\database\classintra.db`，再启动自动重建。
- **cmd 窗口中文乱码？** → 本仓库 `.bat` 采用 GBK（ANSI）编码以兼容 Windows 命令行为准；在 GitHub 网页或某些编辑器中预览乱码属正常现象，**不影响实际运行**。`.md`/`.txt`/`.js` 均为 UTF-8。

## 与上游的关系 / 本地增强

| 目录 | 上游 | 本仓库相对上游的改动 |
|---|---|---|
| `apps/ClassIntra` | [ClassIntra/ClassIntra](https://github.com/ClassIntra/ClassIntra) `5c93e6a` | `.npmrc` 增加国内镜像（registry/better-sqlite3 预编译镜像）与便携注释 |
| `apps/captive` | [ClassIntra/captive](https://github.com/ClassIntra/captive) `559b37d` | `hotspot-redirect.js` 拦截域名加入 `zhixue.com`；`start-hotspot-redirect.bat` 增加便携 node PATH 适配 |

上游更新可用 `4-更新代码.bat`（在 `apps\ClassIntra` 内 `git pull`）同步。

## License

MIT。上游版权归各自作者所有（见 [LICENSE](LICENSE) 与 `apps/*/LICENSE`）。
