# 贡献指南

欢迎贡献代码！以下是参与方式。

## 开发环境

1. 克隆仓库
2. 安装 Node.js >= 18
3. 运行 `npm install`
4. 生成 TLS 证书（见 README）
5. 以管理员身份运行 `node hotspot-redirect.js`

## 开发规范

- 核心代理（`hotspot-redirect.js`）保持简洁，不引入第三方依赖
- 在 Windows 10 和 11 上测试
- 脚本应同时支持交互模式和静默模式
- 记录重要事件，避免过多输出
- 遵循现有代码风格（JS 无分号，2 空格缩进）

## 提交 PR

1. Fork 仓库
2. 创建功能分支（`git checkout -b feature/your-feature`）
3. 提交更改（`git commit -am '添加某功能'`）
4. 推送分支（`git push origin feature/your-feature`）
5. 发起 Pull Request

## 提交 Issue

- 使用 Issue 追踪器报告 Bug 和功能请求
- 请附上 Windows 版本和 Node.js 版本
- 提供 `logs/service.log` 或 `logs/watchdog.log` 中的相关日志

## 许可

提交贡献即表示你同意将贡献内容以 [MIT 许可证](LICENSE) 授权。
