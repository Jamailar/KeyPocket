# 贡献指南 / Contributing

欢迎提交小而明确的改进。界面保持紧凑，新增依赖或功能前请说明必要性。中文和英文 Issue / PR 均可。

## 本地开发

要求 Apple Silicon、macOS 14+ 与 Xcode Command Line Tools：

```sh
bash build.sh
.build/KeyPocket.app/Contents/MacOS/KeyPocket --self-test
open -n .build/KeyPocket.app --args --preview
```

UI 调试优先使用 `--preview` 的虚拟数据。涉及解析、数据迁移、钥匙串或 CLI/MCP 契约的修改应增加对应自检；纯文案或布局调整完成构建和 UI 验证即可。

## Pull Request

- 一个 PR 聚焦一个问题，说明变化、原因与验证结果。
- 保持已保存数据的兼容性；更改数据格式时说明迁移和回退行为。
- `mcp` 模式的 stdout 只能输出协议消息。
- 更新受影响的中文与英文 README。
- 不提交 `.build`、真实 `.env`、密钥、私有服务地址或本机 Agent 配置。样例统一使用 `example.com` 和明确的虚拟 Key。
- 安全漏洞请按 [SECURITY.md](SECURITY.md) 私下报告。

## English

Keep changes focused and the UI compact. Explain the problem, implementation, and validation in your PR. Build and visually verify UI changes using fake data in `--preview`. Add self-tests for meaningful changes to parsing, persistence, migration, or the CLI/MCP contract. Preserve stored-data compatibility and keep MCP stdout protocol-only. Update both READMEs when behavior changes.

Never commit real credentials, private endpoints, generated apps, local agent configuration, or personal dotenv files. Use `example.com` and clearly fake values in examples. Your contributions are distributed under the repository's MIT license.
