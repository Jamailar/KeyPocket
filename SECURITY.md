# 安全政策 / Security policy

KeyPocket 处于早期开发阶段，尚未经过独立安全审计。安全修复优先针对默认分支上的最新版本，不承诺旧版本长期维护。

## 私下报告

请使用 GitHub 的 [Report a vulnerability](https://github.com/Jamailar/KeyPocket/security/advisories/new) 私下报告漏洞，不要先创建公开 Issue。提供受影响版本、影响范围、最小复现步骤和虚拟数据；不要附上真实 API Key、钥匙串内容或访问令牌。

如果凭据已公开，请先在原服务提供商处撤销或轮换。删除公开内容无法保证收回已泄露的值。

## 当前边界

- 系统钥匙串保护静态存储，应用本身没有独立主密码或细粒度授权。
- MCP 客户端可读取整个配置库；`get` / `get_connection` 会将真实密钥返回给调用方。
- 配置名称、备注和 URL 路径属于元数据，列表会返回这些内容，勿在其中放入密钥。
- Developer 视图直接显示真实值；剪贴板自动清除无法删除其他软件已保存的历史。
- 不是同一用户下恶意进程的隔离边界；没有团队权限、云同步、备份恢复或独立审计日志。
- 当前没有跨进程写入协调，请避免同时在多个实例中编辑配置。

## English

This is an early project without an independent security audit. Security fixes target the latest default-branch version; older versions have no long-term support guarantee.

Use GitHub's private [vulnerability report](https://github.com/Jamailar/KeyPocket/security/advisories/new), not a public issue. Include the affected version, impact, and minimal reproduction with fake data. Never attach real credentials or vault contents. Revoke or rotate exposed credentials at their provider before reporting.

Keychain protects storage, but KeyPocket has no separate master password or per-agent/per-service permissions. An attached MCP client can read all configurations, and credential reads return plaintext to that client. Metadata includes names, notes, and URL paths. Developer mode displays plaintext; clearing the clipboard cannot revoke external clipboard history. The app does not isolate secrets from malicious same-user processes and has no cloud sync, recovery, audit log, or cross-process write coordination.
