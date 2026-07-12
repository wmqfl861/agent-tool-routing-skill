# Changelog / 更新日志

All notable user-visible changes are recorded here. The project follows
[Semantic Versioning](https://semver.org/) while it remains pre-1.0.

此文件记录所有用户可见的重要变更。项目在 1.0 之前同样遵循
[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.5] - 2026-07-12

### Fixed / 修复

- Create a private POSIX temporary directory and download the bootstrap as
  `install.ps1`, avoiding extensionless `mktemp` files that some `pwsh -File`
  environments reject.
- POSIX wrapper 改为创建私有临时目录，并把 bootstrap 下载为 `install.ps1`，避免
  部分 `pwsh -File` 环境拒绝无扩展名的 `mktemp` 文件。

## [0.1.4] - 2026-07-12

### Added / 新增

- Add nine copy-ready, single-command installers for every Windows, Linux, and
  macOS combination with Codex, Claude Code, and zcode.
- Add a release-pinned remote bootstrap and deterministic payload manifest.
  The bootstrap verifies the manifest digest, exact payload allowlist, file
  sizes, SHA-256 digests, and release version before invoking the existing
  transactional installer.
- Bound remote downloads by elapsed time and response-buffer size, reject HTTP
  redirects inside the bootstrap, and retry only a finite number of times.
- Disable user curl configuration in every outer wrapper so local `.curlrc`
  settings cannot weaken TLS or alter transfer and retry behavior.
- Add a deterministic manifest generator and five Pester regression tests for
  verified installation, target forwarding, `-WhatIf`, payload tampering, and
  manifest tampering.
- 新增九条可直接复制的一行安装命令，覆盖 Windows、Linux、macOS 与 Codex、
  Claude Code、zcode 的全部组合。
- 新增固定 Release 版本的远程 bootstrap 和确定性 payload manifest。bootstrap
  会在调用现有事务安装器前校验 manifest 摘要、精确 payload 白名单、文件大小、
  SHA-256 摘要和 Release 版本。
- 远程下载同时限制总耗时和响应缓冲区大小，bootstrap 内拒绝 HTTP 重定向，并只进行
  有限次数重试。
- 所有外层 wrapper 都禁用用户 curl 配置，避免本地 `.curlrc` 削弱 TLS 或改变传输、
  重试行为。
- 新增确定性 manifest 生成器，以及五项 Pester 回归测试，覆盖校验安装、目标转发、
  `-WhatIf`、payload 篡改和 manifest 篡改。

### Changed / 变更

- Replace the Quick Start clone-and-change-directory flow with platform-native
  PowerShell, Bash, and zsh wrappers. Every wrapper downloads to a private
  temporary file and verifies the bootstrap before execution; none pipe
  unverified network content into a shell.
- Keep onboarding as the default one-command behavior and leave runtime routing
  opt-in through the reviewed local-install path.
- Define the Windows one-command baseline as Windows 10 1803+, Windows Server
  2019+, or another supported release with `curl.exe`.
- Extend repository validation and CI contracts to keep all nine commands,
  release hashes, detailed install guides, manifest content, and the exact
  43-test Pester count synchronized.
- Require LF-only release payloads so generated digests match GitHub raw content
  regardless of the maintainer's operating system or Git checkout settings.
- 用适合平台的 PowerShell、Bash 和 zsh wrapper 替换快速开始中的克隆、切换目录
  流程。每条命令先下载到私有临时文件并校验 bootstrap，再执行；不会把未经校验的
  网络内容直接传给 shell。
- 一行安装默认只启用 onboarding；runtime 路由继续通过经过审阅的本地安装方式
  显式开启。
- 将 Windows 一行安装基线明确为 Windows 10 1803+、Windows Server 2019+，或
  其他提供 `curl.exe` 的受支持 Windows 版本。
- 扩展仓库 validator 和 CI 契约，确保九条命令、Release 哈希、详细安装文档、
  manifest 内容和严格的 43 项 Pester 测试数量保持同步。
- 要求 Release payload 只使用 LF 换行，确保生成的摘要不受维护者操作系统或 Git
  checkout 配置影响，并与 GitHub raw 内容一致。

## [0.1.3] - 2026-07-12

### Changed / 变更

- Add copy-ready Windows, Linux, and macOS installation paths to both README
  files, including repository cloning and the correct shell for each platform.
- Distinguish Windows PowerShell 5.1 from PowerShell 7 commands and replace
  POSIX examples that depended on PowerShell-only continuation or path syntax.
- Document platform-specific install and custom-root commands in the Codex,
  Claude Code, and zcode installation guides.
- Tighten repository validation for release badges, current-version notices,
  Changelog release links, and the three-platform quick-start contract.
- 在中英文 README 中加入可直接复制的 Windows、Linux 和 macOS 完整安装流程，
  包括仓库克隆步骤和各平台对应的 shell。
- 区分 Windows PowerShell 5.1 与 PowerShell 7 命令，并替换依赖 PowerShell
  续行符或路径语法的 POSIX 示例。
- 在 Codex、Claude Code 和 zcode 安装文档中补充各平台安装命令和自定义目录示例。
- 加强版本徽章、当前版本、Changelog Release 链接和三平台快速开始的仓库校验。

## [0.1.2] - 2026-07-11

### Fixed / 修复

- Detect dangling symbolic links on Linux and macOS during read-only preflight,
  before creating a backup snapshot or changing an installation target.
- Require resolved POSIX symbolic-link targets to exist instead of allowing a
  broken link to fall through as an ordinary not-yet-created path.
- Upgrade GitHub Actions checkout steps to the Node.js 24-based v5 runtime.
- Avoid duplicate release builds by running push CI for branches, while pull
  requests continue to run independently.
- Linux 和 macOS 现在会在只读预检阶段识别悬空符号链接，并在创建备份快照或
  修改安装目标之前拒绝该路径。
- POSIX 符号链接解析后的最终目标必须存在，不再把悬空链接误判为尚未创建的
  普通路径。
- GitHub Actions checkout step 升级到基于 Node.js 24 的 v5 runtime。
- push CI 仅由分支更新触发，pull request 仍独立运行，避免发布标签产生重复构建。

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

[0.1.5]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.5
[0.1.4]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.4
[0.1.3]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.3
[0.1.2]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.2
[0.1.1]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.1
[0.1.0]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.0
