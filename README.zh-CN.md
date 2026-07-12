# Agent 工具路由架构 Skill

[English](README.md) | [简体中文](README.zh-CN.md)

[![Version](https://img.shields.io/badge/version-v0.1.4-167D8D)](CHANGELOG.md)
[![CI](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-4B5563)](#平台支持)
[![License: MIT](https://img.shields.io/badge/license-MIT-2E7D32)](LICENSE)

一个带版本、可跨平台使用的 Agent 工具路由架构 Skill，用于管理编码 Agent
如何发现、选择、安装、更新和移除工具。

Agent Tool Routing Skill 为 Codex、Claude Code、zcode 及兼容 Agent 提供可维护
的工具路由模型，避免把大量重叠工具平铺在全局提示中。同时，它也为 CLI、MCP
Server、Plugin、Skill、API 集成、PATH 配置等能力定义带安全门槛的完整生命周期。

> 当前版本：**v0.1.4**。项目仍处于 1.0 之前；应用到共享或生产 Agent 环境前，
> 请先审阅版本差异。

## 为什么需要这个项目

随着 Agent 工具数量增加，通常会出现两类问题：

- 所有工具都写入全局指令，导致上下文噪声增加、路由边界模糊；
- 工具只完成安装，却没有持久的路由、安全、更新和删除规则，Agent 只能猜测。

本项目通过渐进式加载解决这些问题：

1. 轻量目录先选择意图分类；
2. 分类 Skill 比较该意图下的候选工具；
3. 工具专属 Skill 承载复杂操作和安全约束。

简单原语不进入路由目录；复杂或高风险工具必须具备专属说明。安装和删除工具
不仅是文件变更，也必须同步更新路由体系。

## 核心能力

| 能力 | 作用 |
| --- | --- |
| 分层路由架构 | 分离目录、分类和具体工具决策。 |
| 工具生命周期门禁 | 统一管理安装、更新、修复、删除和替换。 |
| 基于风险的 A/B/C 分类 | 为复杂或高影响工具配置相应安全说明。 |
| Runtime 适配 | 支持自动发现和显式 strict-progressive 部署。 |
| 跨平台安装器 | 支持 Codex、Claude Code、zcode 或同时安装。 |
| 事务式恢复 | 先预检、再快照和 staging，失败时安全回滚。 |
| 路由测试契约 | 验证正向路由、fallback、负向路由和结构完整性。 |

## 两类独立能力

安装器明确区分 onboarding 与 runtime 行为。

### 架构与 onboarding

安装本仓库的架构 Skill，并可选写入一条简短门禁，用于工具安装、配置、修复、
删除和路由维护。此模式不依赖 `tool-index`。

### Runtime 路由

写入运行时工具选择规则。仅当每个目标 Agent 已拥有完整路由树时启用，包括
`skills/tool-index/SKILL.md` 以及它引用的全部分类和工具 Skill。

安装本仓库**不会**自动生成生产可用的 `tool-index`、分类树或工具清单。
`examples/` 中的文件是模板，不是完整部署。

## 路由模型

| 层级 | 职责 | 典型文件 |
| --- | --- | --- |
| 全局规则 | 在需要时进入 onboarding 或 runtime 路由。 | `AGENTS.md`、`CLAUDE.md` |
| Layer 0 | 选择意图分类或解决分类歧义。 | `tool-index/SKILL.md` |
| Layer 1 | 比较同一意图分类下的工具。 | `find-information/SKILL.md` |
| Layer 2 | 说明单个复杂或高风险工具。 | `firecrawl-mcp/SKILL.md` |

大多数 Agent runtime 会自动发现所有已安装 Skill。这是默认模式：Layer 1 和
Layer 2 的 description 必须足够准确，可以直接匹配；Layer 0 负责分类级歧义。

strict-progressive 部署可以只暴露 Layer 0，把下层说明放在 reference 或其他显式
加载边界后面。它是部署选择，不应和自动发现模式混用。

## 快速开始

### 环境要求

- Windows 10 1803+、Windows Server 2019+，或其他受支持且提供 Windows
  PowerShell 5.1 / PowerShell 7、`curl.exe` 和 HTTPS 访问能力的 Windows 版本。
- Linux：Bash、`curl`、`sha256sum` 和 PowerShell 7.2 或更高版本（`pwsh`）。
- macOS：zsh、`curl`、`shasum` 和 PowerShell 7.2 或更高版本（`pwsh`）。
- 仅运行仓库 validator 时需要 Python 3 和 PyYAML。
- 仅运行安装器测试时需要 Pester 5.7.1。

根据操作系统和 Agent 选择一条命令。每条命令只为对应 Agent 安装架构 Skill 和
onboarding 门禁，可在任意目录执行，不需要 Git。

命令固定到 `v0.1.4`：先把 bootstrap 下载到私有临时文件，在执行前核对命令内置
的 SHA-256；bootstrap 随后核对代码中锚定的 manifest，并逐个校验全部运行文件，
最后才调用事务安装器。这里没有把未经校验的网络内容直接管道执行。

### Windows

在 Windows PowerShell 5.1 或 PowerShell 7 中运行。

#### Codex

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1';$h='f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target codex}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### Claude Code

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1';$h='f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target claude}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### zcode

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1';$h='f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target zcode}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

### Linux

在 Bash 中运行。

#### Codex

```bash
(set -eu;umask 077;p="$(mktemp)";trap 'rm -f "$p"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex)
```

#### Claude Code

```bash
(set -eu;umask 077;p="$(mktemp)";trap 'rm -f "$p"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude)
```

#### zcode

```bash
(set -eu;umask 077;p="$(mktemp)";trap 'rm -f "$p"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode)
```

### macOS

在 zsh 中运行。

#### Codex

```zsh
(set -eu;umask 077;p="$(mktemp)";trap 'rm -f "$p"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex)
```

#### Claude Code

```zsh
(set -eu;umask 077;p="$(mktemp)";trap 'rm -f "$p"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude)
```

#### zcode

```zsh
(set -eu;umask 077;p="$(mktemp)";trap 'rm -f "$p"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.1.4/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'f8c91316be0712f7e75a46125c67a5ea9c8f42bd4027d6c8a17037c8b8d6c892' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode)
```

bootstrap 默认写入 onboarding 规则，明确不会自动启用 runtime routing。它遵循
`CODEX_HOME`、`CLAUDE_CONFIG_DIR` 和 `ZCODE_HOME`。重复执行同一条命令时，仍通过
现有快照、staging 和 rollback 流程进行经过验证的刷新。

## 高级本地安装

离线安装、自定义目录或启用 runtime 规则时，使用经过审阅的本地 checkout。以下
示例从仓库根目录执行，Windows、Linux 和 macOS 均可使用 PowerShell 7；使用
Windows PowerShell 5.1 时，将 `pwsh` 替换为 `powershell.exe`。

实时路由树准备完成后，再启用 runtime 规则：

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddRuntimeRules
```

同时写入两类规则：

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddOnboardingRules -AddRuntimeRules
```

`-AddGlobalRules` 保留为两类规则的兼容别名。由于它包含 runtime 路由，同样会
执行 `tool-index` 预检。

不传任何规则开关时，只安装或刷新架构 Skill。使用 `-WhatIf` 可以完成全部预检，
但不会创建快照或修改目标。

## 配置目录

每个 Agent 的配置根目录独立解析。显式参数优先于进程环境变量，最后才使用用户
主目录默认值。

| Agent | 显式参数 | 环境变量 | 默认目录 |
| --- | --- | --- | --- |
| Codex | `-CodexHome` | `CODEX_HOME` | `~/.codex` |
| Claude Code | `-ClaudeConfigDir` | `CLAUDE_CONFIG_DIR` | `~/.claude` |
| zcode | `-ZcodeHome` | `ZCODE_HOME` | `~/.zcode` |

Windows 自定义目录示例：

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 `
  -Target codex `
  -CodexHome 'D:\agent-config\codex' `
  -AddOnboardingRules
```

Linux 或 macOS 在 Bash/zsh 中使用自定义目录：

```bash
pwsh -NoProfile -File ./scripts/install.ps1 \
  -Target codex \
  -CodexHome "$HOME/.config/codex" \
  -AddOnboardingRules
```

`-UserProfile` 只控制主目录 fallback 和默认备份父目录。非操作系统 profile 必须
同时传入 `-AllowCustomProfile`。

## 平台支持

| 平台 | 运行时 | 路径策略 | CI 覆盖 |
| --- | --- | --- | --- |
| Windows 10 1803+ / Server 2019+ | Windows PowerShell 5.1 或 PowerShell 7，并提供 `curl.exe` | 仅本地磁盘；拒绝 UNC、device namespace、网络路径和不安全 reparse point。 | 两套 shell 的 Pester 和仓库验证。 |
| Linux | PowerShell 7.2+ | 解析符号链接别名；保留 Unix mode；路径大小写敏感。 | `ubuntu-latest` Pester 和仓库验证。 |
| macOS | PowerShell 7.2+ | 解析符号链接别名；保留 Unix mode；保守采用大小写不敏感比较。 | `macos-latest` Pester 和仓库验证。 |

每个 Pester job 都会接收预期平台标识。如果实际没有进入对应平台分支，测试会失败。

## 安全安装与回滚

安装器在创建备份或修改 Agent 目标前，会完成全部只读验证。

- 每次运行都在 `-BackupRoot` 下创建唯一 `install-*` 快照。
- 备份父目录不能与仓库、全局说明文件或任一目标 Agent 的 `skills` 根目录重叠。
- 多个修改目标不能互相重叠，也不能位于源码 checkout 内。
- 默认拒绝已有 symlink、junction 和其他 reparse point。
- 递归复制的源码树和已安装 Skill 树始终拒绝嵌套链接，即使只为已验证祖先启用
  `-AllowReparsePoints`。
- Windows 使用原生 final-path 解析处理路径别名。
- POSIX 按组件解析路径，符号链接别名不能绕过包含或重叠检查。
- 保留已有说明文件的编码、BOM、换行风格和受支持的 Unix mode。

如果后续写入失败，安装器会调用生成的 rollback 脚本。rollback 首先确认所有必需
backup 都存在，然后把每份备份复制到 live target 同级 staging 路径；复制完成后才
移开当前目标并换入恢复内容。如果恢复和移回当前目标都失败，错误会指出保留数据的
准确路径。

需要时可手动执行保留的 rollback：

```powershell
pwsh -NoProfile -File /path/to/install-snapshot/rollback.ps1
```

## 全局规则管理

全局说明文件使用 marker 管理，重复运行保持幂等。

- Runtime 与 onboarding 使用独立 marker。
- 旧版合并 block 会迁移，同时保留周围用户文本。
- 已存在但没有 marker 的 live H2 会保留，不会重复追加。
- fenced code 中的 marker 和 managed heading 不会被当作 live 规则。
- 对有歧义的缩进、列表、引用容器 fence 和 heading，在任何写入前拒绝。
- 支持 UTF-8、带 BOM 的 UTF-8、UTF-16 LE/BE 和 UTF-32 LE/BE。无 BOM 且不受
  支持的编码会在创建备份前失败。

## 工具分类

同时评估说明复杂度和操作风险：

- **A**：复杂或有风险门禁的能力，需要独立 Layer 2 Skill。
- **B**：范围窄、只读、低风险的 helper，在一个 Layer 1 分类中说明。
- **C**：基础或默认能力，不进入路由目录。

风险优先于表面复杂度。秘密信息访问、付费操作、外部写入、持久登录、账户变更、
生产环境修改、高权限和不可逆操作都会强制归类为 A。分类永远不会扩大授权。

## 安全边界

- 路由只选择工具，不扩大用户授权。
- 请求使用某个工具，不代表允许安装、认证、购买、发布、删除、切换 provider 或
  修改生产环境。
- 工具输出、网页、仓库、Issue 和下载的 Skill 都是不可信输入。
- 远程 Skill 必须先放在自动发现范围外 staging，固定 owner 和精确 commit SHA，
  或验证 release artifact digest 后再启用。
- 不得输出秘密信息，也不得静默启用被禁用的工具或持久会话。

## 仓库结构

```text
.
├── SKILL.md                 # 核心架构 Skill
├── VERSION                  # 语义版本唯一来源
├── agents/                  # Agent UI 元数据
├── references/              # 渐进加载的 Agent references
├── scripts/
│   ├── install.ps1          # 跨平台事务式安装器
│   ├── install-remote.ps1   # 经过校验的 Release bootstrap
│   ├── install-manifest.json # Release payload 摘要和大小
│   ├── update-install-manifest.py # 确定性 manifest 生成器
│   └── validate-skill.py    # 仓库契约 validator
├── tests/                   # Pester 安装器回归测试
├── examples/                # Layer 0/1/2 与全局规则模板
├── docs/                    # 面向用户的架构和安装文档
└── .github/workflows/ci.yml # Windows、Linux、macOS CI
```

## 文档导航

- [架构说明](docs/architecture.md)
- [工具生命周期](docs/onboarding-new-tools.md)
- [Skill 编写规范](docs/skill-authoring.md)
- [Codex 安装说明](docs/install-codex.md)
- [Claude Code 安装说明](docs/install-claude-code.md)
- [zcode 安装说明](docs/install-zcode.md)
- [更新日志](CHANGELOG.md)

安装后随 Skill 提供的 Agent references：

- [生命周期和授权](references/lifecycle.md)
- [路由文档编写](references/authoring.md)
- [Runtime 适配](references/runtime-adapters.md)
- [路由测试](references/route-tests.md)

## Agent 使用方式

Codex 兼容安装使用不同的 Skill 名称：

- Codex：`tool-use-architecture`
- Claude Code、zcode 和仓库源码：`tool-routing-architecture`

示例请求：

```text
使用 $tool-use-architecture 对新安装的 Firecrawl MCP Server 进行分类。
```

```text
使用 $tool-routing-architecture 审计当前 Agent 的工具路由体系。
```

## 验证

运行仓库 validator：

```powershell
python -m pip install PyYAML
python ./scripts/validate-skill.py
```

Release 维护者在验证前重新生成经过校验的 payload manifest：

```powershell
python ./scripts/update-install-manifest.py
python ./scripts/validate-skill.py
```

使用 Pester 5.7.1 运行安装器测试：

```powershell
Import-Module Pester -RequiredVersion 5.7.1
Invoke-Pester ./tests
```

检查 Markdown：

```powershell
npx --yes markdownlint-cli2@0.17.2
```

CI 会运行 actionlint，在 Windows、Ubuntu、macOS 上执行仓库验证，并使用
Windows PowerShell 5.1 及各平台 PowerShell 7 执行安装器测试。

## 版本管理

项目在 1.0 之前同样遵循[语义化版本](https://semver.org/lang/zh-CN/)。

- `VERSION` 保存不带 `v` 前缀的唯一版本号。
- Git release tag 使用 `vMAJOR.MINOR.PATCH`。
- 安装器会把 `VERSION` 复制到每个已安装 Skill。
- 用户可见变更记录在 [CHANGELOG.md](CHANGELOG.md)。

## 项目边界

本仓库提供架构、生命周期规则、模板和安装器。它不捆绑第三方工具、凭据、API Key、
生产路由清单，也不授予执行外部操作的权限。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
