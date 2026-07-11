# Changelog / 更新日志

All notable user-visible changes are recorded here. The project follows
[Semantic Versioning](https://semver.org/) while it remains pre-1.0.

此文件记录所有用户可见的重要变更。项目在 1.0 之前同样遵循
[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.1] - 2026-07-11

### Fixed / 修复

- Replaced unsupported `matrix.shell` expressions with explicit Windows
  PowerShell 5.1 and PowerShell 7 jobs.
- Added actionlint to CI and the repository contract so GitHub Actions context
  errors are caught before release.
- Made every CI Pester job require exactly 38 passing tests, preventing silent
  test-discovery regressions.
- 用独立的 Windows PowerShell 5.1 和 PowerShell 7 job 替换 GitHub Actions
  不支持的 `matrix.shell` 表达式。
- 在 CI 和仓库契约中加入 actionlint，在发布前发现 GitHub Actions context 错误。
- 所有 CI Pester job 必须准确通过 38 项测试，防止测试发现数量静默下降。

## [0.1.0] - 2026-07-11

Initial versioned release. / 首个正式版本化发布。

### Added / 新增

- Layer 0/1/2 routing architecture with explicit auto-discovery and
  strict-progressive runtime modes.
- Tool lifecycle, authorization, remote-skill provenance, authoring, adapter,
  and route-test references.
- Separate onboarding and runtime global-rule switches with a compatibility
  alias for legacy installs.
- Independent Codex, Claude Code, and zcode configuration-root resolution.
- Repository validator, Markdown lint configuration, Pester regression suite,
  actionlint, and Windows/Linux/macOS GitHub Actions coverage.
- Full English and Simplified Chinese repository documentation.
- Layer 0/1/2 路由架构，并明确区分自动发现与 strict-progressive runtime 模式。
- 工具生命周期、授权、远程 Skill 来源、编写、适配和路由测试 references。
- 独立的 onboarding/runtime 全局规则开关，以及旧安装方式的兼容别名。
- Codex、Claude Code、zcode 各自独立的配置根目录解析。
- 仓库 validator、Markdown lint、Pester 回归测试、actionlint，以及
  Windows/Linux/macOS CI。
- 完整英文和简体中文仓库说明。

### Security and reliability / 安全与可靠性

- Complete read-only preflight before backup creation or target mutation.
- Unique snapshots, generated rollback, and automatic rollback after a later
  target fails.
- Source, backup, and mutation-target overlap protection.
- Windows native final-path handling and POSIX component-level symbolic-link
  canonicalization.
- Recursive reparse/symbolic-link rejection for copied source and skill trees.
- Encoding, BOM, newline, and supported Unix-mode preservation.
- Marker-aware Markdown updates that reject ambiguous fenced/container content.
- Rollback-wide backup preflight and same-parent staged restore before live
  target displacement.
- 在创建备份或修改目标前完成全部只读预检。
- 唯一快照、自动生成 rollback，以及后续目标失败时自动恢复。
- 源码、备份和修改目标的路径重叠保护。
- Windows 原生 final-path 处理和 POSIX 按组件解析符号链接。
- 递归复制的源码树和 Skill 树拒绝 reparse point/符号链接。
- 保留编码、BOM、换行风格和受支持的 Unix mode。
- 感知 marker 的 Markdown 更新，并拒绝有歧义的 fence/container 内容。
- rollback 全量备份预检，并在移开 live target 前完成同级 staging。

### Compatibility / 兼容性

- Windows PowerShell 5.1 and PowerShell 7 on Windows.
- PowerShell 7.2 or later on Linux and macOS.
- Codex compatibility conversion from `tool-routing-architecture` to
  `tool-use-architecture` in installed metadata and managed global rules.
- Windows 支持 Windows PowerShell 5.1 和 PowerShell 7。
- Linux、macOS 支持 PowerShell 7.2 或更高版本。
- Codex 安装时会把 `tool-routing-architecture` 兼容转换为
  `tool-use-architecture`，覆盖已安装元数据和 managed global rules。

[0.1.1]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.1
[0.1.0]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.0
