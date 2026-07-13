# Agent 工具路由架构 Skill

[English](README.md) | [简体中文](README.zh-CN.md)

[![Version](https://img.shields.io/badge/version-v0.2.2-167D8D)](CHANGELOG.md)
[![CI](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-4B5563)](#平台支持)
[![License: MIT](https://img.shields.io/badge/license-MIT-2E7D32)](LICENSE)

一个带版本、可跨平台使用的 Agent 工具路由架构 Skill，用于管理编码 Agent
如何发现、选择、安装、更新和移除工具。

Agent Tool Routing Skill 为 Codex、Claude Code、zcode 及兼容 Agent 提供可维护
的工具路由模型，避免把大量重叠工具平铺在全局提示中。同时，它也为 CLI、MCP
Server、Plugin、Skill、API 集成、PATH 配置等能力定义带安全门槛的完整生命周期。

> 当前版本：**v0.2.2**。项目仍处于 1.0 之前；应用到共享或生产 Agent 环境前，
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

渐进式加载的设计目标，是减少每项任务加载的无关说明。Token 效率属于架构目标，
不是默认成立的实测结论。字节数或码点数基准衡量的是结构化上下文加载量，不是模型
token；只有记录具体模型、runtime、tokenizer 和工具清单的专门基准，才能支持量化
token 收益。

在 canonical 合成 fixture 中，不受支持的 eager-all-documents 反模式加载
`12,011` metadata bytes 和 `98,695` body bytes，合计 `110,706` bytes。受支持
路径的总负载分别为：strict-progressive A `7,176`、strict-progressive B
`4,668`、auto-discovery A `2,783`、auto-discovery B `2,375`、C bypass `0`。
这些是精确文件大小，不代表 token、成本、缓存、延迟或完整 system prompt；详见
[benchmark 方法](docs/context-benchmark.md)。

一次隔离的 Claude Code catalog-matching smoke test 请求了 `claude-fable-5`、
effort `max`，结果为 `18/18`：A `11/11`、B `4/4`、C `3/3`，其中预期
abstention 为 `4/4`。这是小型合成 fixture，不代表泛化能力或生产路由准确率。
模型名称只是精确的 CLI 请求值，无法证明后端使用了不可变 model snapshot。
包含答案且经过 hash 校验的完整产物保存在
[`benchmarks/runs/`](benchmarks/runs/) 中。

## 核心能力

| 能力 | 作用 |
| --- | --- |
| 分层路由架构 | 分离目录、分类和具体工具决策。 |
| 工具生命周期门禁 | 将简短删除/卸载请求直接视为完整受管下线，并执行安全所有权检查。 |
| 基于风险的 A/B/C 分类 | 为复杂或高影响工具配置相应安全说明。 |
| 持久索引交接 | 为 Agent 排队持久请求，由 Agent 生成经过审阅且可恢复的清单和路由树。 |
| 版本化受管清单 | 在 Skill、Plugin 发现目录之外维护唯一、带 revision 的 A/B/C 记录。 |
| Runtime 适配 | 支持自动发现和显式 strict-progressive 部署。 |
| 跨平台安装器 | 支持 Codex、Claude Code、zcode 或同时安装。 |
| 加锁并记录 journal 的恢复 | 串行化写入者、校验 staging、恢复中断的 Skill 交换并保留 rollback 快照。 |
| 路由测试契约 | 验证正向路由、fallback、负向路由和结构完整性。 |

## 架构、初始化与运行时

安装器把核心安装、持久请求排队、由 Agent 执行的首次索引和普通 runtime 行为
划分为独立的授权与验证边界。

### 架构与 onboarding

安装本仓库的架构 Skill，并可选写入一条简短门禁，用于工具安装、配置、修复、
删除和路由维护。此模式不依赖 `tool-index`。

对于名称或上下文已经明确的能力，用户只需说“删除 Example Crawler”或“卸载
Example Crawler”，就已经授权完整的受管下线流程。Agent 会先备份受影响状态，
根据实际安装来源和已验证的官方文档确定副作用最小的删除机制，而不会根据显示名称
猜测包管理器；随后清理活动路由，按删除后的引用数处置 Skill，删除未修改的受管孤儿
Skill，并将符合条件的人工修改或所有权未知孤儿 Skill 完整归档到发现目录之外；随后
写入 inventory tombstone、协调受管全局规则、排查悬空引用并运行负向路由测试。工具
本体删除和可恢复的受管状态发布会分阶段记入 journal，系统绝不会把活动路由恢复到
已经不存在的能力上。

用户不需要逐项补充这些依赖清理。只有身份或 Agent 范围不明确、卸载器必然删除受
保护数据、删除单个插件能力必须扩大为删除整个插件，或保留的共享/外部 Skill 无法与
旧能力隔离时，Agent 才会提出一个最小化的补充问题。凭据、缓存、浏览器 profile、
用户数据、账户和无关能力默认不动。只有删除前已经记录并验证精确重装或恢复路径时，
才会承诺工具本体可以完整回滚。

### 由 Agent 执行的首次路由索引

`-InitializeRouting` 明确授权安装器排队一次性工具盘点和路由构建任务。经过校验的
安装器会在同一次加锁安装与 rollback 操作中创建持久的 `pending` 请求，或保留已有的
可恢复请求。安装器不会执行工具盘点、搜索或下载 Skill、编写指南、构建路由，也不会
启动另一个 Agent 进程。

如果安装命令由 Agent 调用，该 Agent 必须在普通工作前继续处理 pending 任务；如果
命令直接在终端运行，则由目标 Agent 的下一次全新会话在普通工作前接手。正在运行的
Agent 不保证热加载刚安装的 Skill 或全局说明，因此安装不保证在同一会话完成索引。

索引范围是目标 Agent 已注册或可发现的能力，包括 runtime 能够公开的已启用 MCP
Server、Plugin、Skill 和已配置集成。它不会把 `PATH` 中的每个可执行文件都当作
Agent 工具，也不会扫描无关工作区。已解析的 A、B 类能力按用户意图加入活动路由；
每个 C 类能力仍纳入受管清单，记录排除理由，并绕过活动意图路由。完整清单管理并不
意味着每一种分类都会生成路由。

索引成功后，会在
`<agent-config-root>/tool-routing-state/inventory.json` 发布唯一 canonical
清单；该路径位于 Skill、Plugin 发现目录之外。清单使用稳定 capability id 和单调
递增 revision，并与匹配的路由树和受管全局规则一同提交。job 内的 inventory 只是
可恢复工作副本，不是长期事实来源。

只有消费 pending 任务的 Agent 才会在盘点、分类、检索、构建和验证过程中发布稳定
的阶段进度；安装器只报告安装和请求排队结果，不显示索引阶段进度。在由 Agent 执行
的工具生命周期操作中，如果新增 A 类能力没有可用的本地或工具自带指南，onboarding
会询问一次：搜索并审阅规范的官方来源、根据充分且经过审阅的官方文档编写，或让该
能力保持未路由。由 Agent 生命周期流程之外新增的工具，会在下一次显式 onboarding
同步或索引时发现。

### Runtime 路由

写入运行时工具选择规则。仅当每个目标 Agent 已拥有完整路由树时启用，包括
`skills/tool-index/SKILL.md` 以及它引用的全部分类和工具 Skill。

仅安装架构时**不会**生成生产可用的 `tool-index`、分类树或工具清单。
`-InitializeRouting` 会请求 Agent 根据当前有效环境生成这些内容；`examples/` 仍是
模板，不是预制的完整部署。

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

根据操作系统和 Agent 选择一条命令。每条命令会为对应 Agent 安装经过校验的架构
Skill 和 onboarding 门禁，然后排队一次持久的首次路由初始化请求，由 Agent 接手
执行；安装器本身不执行索引。命令可在任意目录执行，不需要 Git。

命令固定到 `v0.2.2`：先把 bootstrap 下载到私有临时文件，在执行前核对命令内置
的 SHA-256；bootstrap 随后核对代码中锚定的 manifest，并逐个校验全部运行文件，
最后才调用事务安装器。这里没有把未经校验的网络内容直接管道执行。

### Windows

在 Windows PowerShell 5.1 或 PowerShell 7 中运行。

#### Codex

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1';$h='8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target codex -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### Claude Code

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1';$h='8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target claude -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### zcode

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1';$h='8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target zcode -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

### Linux

在 Bash 中运行。

#### Codex

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex -InitializeRouting)
```

#### Claude Code

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude -InitializeRouting)
```

#### zcode

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode -InitializeRouting)
```

### macOS

在 zsh 中运行。

#### Codex

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex -InitializeRouting)
```

#### Claude Code

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude -InitializeRouting)
```

#### zcode

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.2/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '8622efd1b36f5ecee70d585cde66f956b03fe798765192fb9d68284dfd1b6001' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode -InitializeRouting)
```

完成核心安装后，`-InitializeRouting` 会以事务方式写入或保留一次性的 `pending`
请求。它不会盘点工具、远程检索或下载 Skill、编写指南、构建路由，也不会启动另一个
Agent。调用安装命令的 Agent 必须在普通工作前继续处理该任务；如果直接在终端安装，
则由目标 Agent 的下一次全新会话接手。不能保证正在运行的 Agent 热加载新 Skill 或
全局说明，也不保证在安装会话内完成索引。

消费该请求的 Agent 会先检查本地和工具自带 Skill。A 类缺少指南时，官方候选必须
固定版本、下载到自动发现范围之外并完成审阅后才能启用；没有合格官方 Skill 时，
可以根据充分且经过审阅的官方文档编写最小指南。如果无法确认官方来源或证据不足，
该 A 类能力会保持未解决，新生成的 runtime 路由树不会启用。重复执行仍保留快照、
staging、rollback 和可恢复任务的保护措施。

## 高级本地安装

离线安装、自定义目录或启用 runtime 规则时，使用经过审阅的本地 checkout。以下
示例从仓库根目录执行，Windows、Linux 和 macOS 均可使用 PowerShell 7；使用
Windows PowerShell 5.1 时，将 `pwsh` 替换为 `powershell.exe`。

从本地 checkout 安装并创建同样的首次索引请求：

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -InitializeRouting
```

本地安装器同样只把持久请求加入队列并报告排队结果。消费该请求的 Agent 会发布索引
进度，并且只在成功完成后删除请求。

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
- 使用由 config root 确定的跨进程 Mutex，防止多个安装器同时规划和 rollback
  同一个 Agent 状态。
- Skill 替换会先校验私有 prepared tree，并在移动 live 目录前，把 journal 和
  tree digest 持久化到不含直接 Skill 的 transaction container 中。

transaction container 保留在 Skill root 的同一文件系统上，以保证目录移动不会
跨文件系统。它的直接 child 不含 `SKILL.md`，payload 再嵌套一层，因此标准的
immediate-child Skill 发现会忽略它；非标准递归发现实现必须显式排除
`.agent-tool-routing-transactions`。

如果后续写入失败，安装器会调用生成的 rollback 脚本。rollback 首先确认所有必需
backup 都存在，然后把每份备份复制到 live target 同级 staging 路径；复制完成后才
移开当前目标并换入恢复内容。如果恢复和移回当前目标都失败，错误会指出保留数据的
准确路径。

journal 解决的是 Skill 目录交换被中断时的 live 路径缺口，并不让 Skill、全局说明
和 initial-index 状态成为一个断电完全原子的事务。进程或主机中断后，应重新运行
安装器，让它恢复保留 journal 并完成幂等安装。snapshot rollback 会恢复普通文件
内容，但不承诺保留 ACL、扩展属性、硬链接关系或目录 identity。手工 rollback
脚本不会获取安装器 Mutex，因此不要与安装过程并行执行。

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
- **C**：基础或默认能力，仍纳入受管清单并记录排除理由，但绕过活动意图路由。

风险优先于表面复杂度。秘密信息访问、付费操作、外部写入、持久登录、账户变更、
生产环境修改、高权限和不可逆操作都会强制归类为 A。分类永远不会扩大授权。

## 安全边界

- 路由只选择工具，不扩大用户授权。
- 请求使用某个工具，不代表允许安装、认证、购买、发布、删除、切换 provider 或
  修改生产环境。
- 请求删除、移除或卸载一个身份明确的工具，已经授权该工具的完整受管下线，但不
  授权删除共享或人工修改的产物、凭据、缓存、用户数据、账户或其他能力。
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
│   ├── benchmark-routing.py # 上下文负载与盲路由 benchmark CLI
│   ├── install.ps1          # 跨平台事务式安装器
│   ├── install-remote.ps1   # 经过校验的 Release bootstrap
│   ├── install-manifest.json # Release payload 摘要和大小
│   ├── update-install-manifest.py # 确定性 manifest 生成器
│   └── validate-skill.py    # 仓库契约 validator
├── benchmarks/              # 合成拓扑、canonical 上下文结果和盲测用例
├── tests/                   # Pester 与 Python 回归测试
├── examples/                # Layer 0/1/2 与全局规则模板
├── docs/                    # 面向用户的架构和安装文档
└── .github/workflows/ci.yml # Windows、Linux、macOS CI
```

## 文档导航

- [架构说明](docs/architecture.md)
- [工具生命周期](docs/onboarding-new-tools.md)
- [Skill 编写规范](docs/skill-authoring.md)
- [上下文负载与路由 benchmark](docs/context-benchmark.md)
- [Codex 安装说明](docs/install-codex.md)
- [Claude Code 安装说明](docs/install-claude-code.md)
- [zcode 安装说明](docs/install-zcode.md)
- [更新日志](CHANGELOG.md)

安装后随 Skill 提供的 Agent references：

- [生命周期和授权](references/lifecycle.md)
- [首次索引](references/initial-index.md)
- [受管能力清单](references/managed-inventory.md)
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
