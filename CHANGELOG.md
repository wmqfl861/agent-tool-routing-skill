# Changelog / 更新日志

All notable user-visible changes are recorded here. The project follows
[Semantic Versioning](https://semver.org/) while it remains pre-1.0.

此文件记录所有用户可见的重要变更。项目在 1.0 之前同样遵循
[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.3] - 2026-07-14

### Fixed / 修复

- Make `-Target` fail closed in both local and remote installers. Omitting it
  no longer expands silently to every supported Agent; only explicit
  `-Target all` authorizes a multi-Agent install.
- Bind queued initial-index work to its recorded target Agent and configuration
  root. Pending work is inert until the current user explicitly asks to
  initialize or resume it, and it cannot inspect or mutate another Agent root.
- Stop remote quick installs from adding global onboarding rules or queuing an
  initial index by default. Both behaviors now require explicit switches.
- Narrow architecture and Layer 0 discovery metadata so ordinary tool calls,
  selected category/tool workflows, quoted content, and transitive references
  cannot activate the architecture skill or replace the user's current task.
- Keep direct capability lifecycle delegation behind the opt-in
  `-AddOnboardingRules` gate. Skill-only installs require an explicit
  architecture invocation for managed offboarding.
- Reject non-object pending and recovery JSON before writes, and validate every
  selected Agent's retained transaction and install plan before recovery mutates
  any target.
- Reject the legacy `-AddGlobalRules` switch before path resolution or writes;
  onboarding and runtime rules now require their independent explicit switches.
- Explicitly exclude individual tool lifecycle and tool-mediated data changes
  from auto-discovery metadata, including when lifecycle verbs appear in task
  data or retrieved content.
- Add target-isolation, opt-in initialization, metadata-boundary, and static
  anti-hijack contract coverage. These checks do not claim to simulate a host
  model's Skill auto-selection behavior.
- Refresh the synthetic context artifact after narrowing Layer 0 metadata:
  eager metadata `11,916`, body `98,901`, total `110,817`; strict A `7,287`,
  strict B `4,779`, auto A `2,783`, auto B `2,375`, and C bypass `0` bytes.
- 本地和远程安装器现在都要求显式 `-Target`。缺少参数时会在任何写入前失败，
  不再静默扩大到全部 Agent；只有显式 `-Target all` 才授权多 Agent 安装。
- 首次索引请求绑定其记录的目标 Agent 和配置根目录。pending 任务默认静默，
  只有当前用户明确要求初始化或恢复时才执行，并且不能检查或修改其他 Agent 根目录。
- 远程快速安装不再默认写入全局 onboarding 规则或排队首次索引；两项行为都改为
  显式开关。
- 收紧架构 Skill 和 Layer 0 的发现 metadata，普通工具调用、已选定的分类/工具
  工作流、引用内容和传递加载不能再激活架构 Skill 或替代用户当前任务。
- 只有显式安装 `-AddOnboardingRules` 门禁后，才会委托直接的能力生命周期请求；
  仅安装 Skill 时，受管下线必须显式调用架构 Skill。
- pending 与恢复 JSON 的顶层不是对象时会在写入前拒绝；恢复修改任何目标前，
  会先校验全部选定 Agent 的保留事务与安装计划。
- 旧的 `-AddGlobalRules` 会在路径解析或写入前失败；onboarding 和 runtime 规则
  必须分别使用各自的显式开关。
- 自动发现 metadata 现在明确排除单个工具生命周期和工具处理的数据变更，即使任务
  数据或检索内容中出现生命周期动词也不会激活架构 Skill。
- 增加目标隔离、显式初始化、metadata 边界和静态 anti-hijack 契约测试；这些
  检查不声称模拟宿主模型真实的 Skill 自动选择行为。
- 收紧 Layer 0 metadata 后同步刷新合成上下文基准：eager metadata `11,916`、
  body `98,901`、total `110,817`；strict A `7,287`、strict B `4,779`、
  auto A `2,783`、auto B `2,375`、C bypass `0` bytes。

## [0.2.2] - 2026-07-13

### Changed / 变更

- Treat a concise current-user request to remove, delete, or uninstall a named
  capability as authorization for its complete managed offboarding in the
  effective Agent scope. The Agent no longer asks the user to separately list
  Skill, inventory, route, managed-global-rule, alias, documentation, or
  negative-test cleanup.
- Make removal a journaled lifecycle workflow: inspect remover side effects,
  resolve the exact command from installed provenance and verified official
  documentation, preserve protected state with keep-data/config/profile options,
  remove active routes, prune empty categories, reconcile managed global rules,
  write an inventory tombstone, search dangling references, and run a negative
  route test. Managed-state publication is recoverable; exact tool rollback is
  only claimed when a tested reinstall or restore path exists.
- Record Layer 2 management provenance separately from the post-change active
  reference count and compatibility ownership label. Delete an unchanged
  zero-reference managed guide even when it was previously shared; archive an
  eligible modified or unknown orphan outside discovery; and never report
  completion while a retained guide can still select the removed capability.
- Treat plugin capabilities as separate inventory records. A single capability
  request cannot silently uninstall its whole plugin, while plugin-wide removal
  offboards every exclusively provided capability and preserves capabilities
  available through another provider.
- Keep the short removal request scoped to the identified capability. Ask only
  to disambiguate identity or Agent scope, or before deleting shared or
  user-modified artifacts, credentials, caches, browser profiles, user data,
  accounts, or other capabilities.
- Expand repository validation and semantic regression tests for concise
  removal authorization, remover side-effect gates, plugin scope, reference
  counting, non-discoverable archival, honest rollback, protected-state
  retention, and bilingual documentation.
- 将用户简短的“删除、移除或卸载某个工具”直接视为对目标 Agent 范围内完整受管
  下线的授权。Agent 不再要求用户逐项补充 Skill、inventory、路由、受管全局规则、
  别名、文档或负向测试清理。
- 将删除实现为分阶段 journal 的生命周期流程：先审查卸载器副作用，使用保留数据/
  配置/profile 的选项保护用户状态，并只从实际安装来源和已验证的官方文档确定卸载
  命令，不根据显示名称猜测包管理器；再清理活动路由、裁剪空分类、协调受管全局规则、
  写入 inventory tombstone、排查悬空引用并运行负向路由测试。受管状态发布可恢复；
  只有存在经过验证的重装或恢复路径时，才承诺工具本体可精确回滚。
- 将 Layer 2 的管理来源、删除后的活动引用数和兼容所有权标签分别记录。未修改且引用
  归零的受管指南即使此前共享也会删除；符合条件的人工修改或所有权未知孤儿指南会
  移到发现目录外归档；任何仍可选择旧能力的指南都会阻止完成状态。
- 把插件能力作为独立 inventory 记录。删除单项能力不会静默卸载整个插件；删除插件
  本身时，会下线其独占提供的每项能力，并保留仍有其他 provider 的能力。
- 简短删除请求只作用于身份明确的能力。只有身份或 Agent 范围有歧义，或将删除共享/
  人工修改产物、凭据、缓存、浏览器 profile、用户数据、账户或其他能力时才询问。
- 扩充仓库契约校验和语义回归测试，覆盖简短删除授权、卸载副作用门禁、插件范围、
  引用计数、发现目录外归档、真实回滚边界、受保护状态保留和中英文文档。

## [0.2.1] - 2026-07-13

### Changed / 变更

- Clarify that `-InitializeRouting` makes the installer queue or preserve a
  durable request; the installer does not inventory tools, search or download
  Skills, author guides, build routes, or emit indexing phase progress. An
  invoking Agent continues the job, while a direct terminal install waits for
  the target Agent's next fresh session; same-session hot-reload is not
  guaranteed.
- Define C consistently as a managed inventory record with an exclusion
  rationale that bypasses active intent routing. A and B enter active routes;
  complete inventory management does not mean every class generates a route.
- Define one durable canonical inventory at
  `<agent-config-root>/tool-routing-state/inventory.json`, with stable
  capability ids, monotonic revisions, class invariants, source provenance,
  C-class exclusion rationales, and publication with matching routes.
- Limit token-efficiency claims to the progressive-disclosure design goal.
  Byte or code-point measurements are not token counts; quantified or
  significant token claims require a model-specific runtime/tokenizer/inventory
  benchmark.
- Replace delete-then-copy Skill installation with a single-writer, journaled
  directory swap. The installer verifies a private incoming tree, persists its
  digest before displacing live data, restores exact previous data on caught
  commit failures, and recovers or fails closed after process interruption.
- Add a standard-library benchmark CLI that separates YAML frontmatter from
  Skill bodies and distinguishes strict-progressive, auto-discovery, and C
  bypass paths. The unsupported eager-all-documents anti-pattern is `12,011`
  metadata + `98,695` body = `110,706` total bytes; supported route totals are
  strict A `7,176`, strict B `4,668`, auto A `2,783`, auto B `2,375`, and C
  `0`. These are exact synthetic file sizes, not token measurements.
- Expand blind routing to opaque case IDs, correct `abstain` scoring, unavailable
  and missing-guide cases, authorization boundaries, explicit selection, and
  adversarial quoted tool names. Replace the incomplete prior run with a fully
  preserved isolated Claude Code smoke test: requested `claude-fable-5`/`max`,
  `18/18` overall, A `11/11`, B `4/4`, C `3/3`, and expected abstentions `4/4`.
  The result is a small synthetic catalog-matching test, not a generalization or
  production-accuracy claim; the model name is the CLI request value, not a
  proven immutable backend snapshot.
- 明确 `-InitializeRouting` 只让安装器排队或保留持久请求；安装器不执行工具
  盘点、Skill 检索或下载、指南编写、路由构建，也不输出索引阶段进度。由调用
  安装器的 Agent 继续任务；终端直接安装时，由目标 Agent 的下一次全新会话
  接手，不保证同一会话热加载。
- 统一将 C 类定义为受管清单记录：保留排除理由并绕过活动意图路由。A、B 类
  进入活动路由；完整清单管理不代表每种分类都生成路由。
- 规定唯一持久清单路径
  `<agent-config-root>/tool-routing-state/inventory.json`，使用稳定 capability id、
  单调 revision、分类不变量和来源证据；C 类必须有排除理由，并与匹配路由一同发布。
- Token 效率仅作为渐进式加载的设计目标；字节数或码点数不能改称 token 数，
  量化收益或“显著降低 token”的表述必须由记录模型、runtime、tokenizer 和
  工具清单的专门基准支持。
- Skill 安装从“先删除再复制”改为单写入者、带 journal 的目录交换：先完整校验
  私有 incoming tree 并持久化 digest，再移开 live Skill；捕获到 commit 失败时
  原样恢复 previous，进程中断后安全恢复或 fail closed。
- 新增纯标准库 benchmark CLI，分别计量 YAML frontmatter 与 Skill 正文，并区分
  strict-progressive、auto-discovery 和 C bypass。eager-all-documents 是不受支持的
  合成反模式，其负载为 metadata `12,011` + body `98,695` = total `110,706`
  bytes；受支持路径的总负载为 strict A `7,176`、strict B `4,668`、auto A
  `2,783`、auto B `2,375`、C `0`。这些是合成文件大小，不是 token 计量。
- 盲路由改用不透明 case ID，正确计分 `abstain`，并覆盖工具不可用、缺失指南、
  授权边界、显式选择和引用内容中的对抗性工具名。用完整保留证据的隔离 Claude Code
  smoke test 取代旧的不完整运行：请求 `claude-fable-5`/`max`，总分 `18/18`，
  A `11/11`、B `4/4`、C `3/3`、预期 abstention `4/4`。这是小型合成
  catalog-matching 测试，不代表泛化或生产准确率；模型名称是 CLI 请求值，不能证明
  后端使用了不可变 snapshot。

## [0.2.0] - 2026-07-13

### Added / 新增

- Add an explicit `-InitializeRouting` installation mode. It installs the
  onboarding gate and creates or preserves a resumable per-Agent initial-index
  request. An Agent-mediated install continues the job before ordinary work;
  a terminal install is resumed on the next fresh Agent turn.
- Add an eight-phase initial-index workflow for registered MCP servers, enabled
  plugins, installed Skills, configured CLI/API integrations, and Agent-visible
  built-ins. The workflow maps existing Skills, classifies capabilities as
  A/B/C, resolves missing A guides, builds routes, validates them, and activates
  runtime routing only when no enabled A capability remains unresolved.
- Add a future-tool gate that checks local and bundled Skills first, then asks
  whether to search and review an official Skill, author from verified official
  documentation, or leave the tool unrouted.
- Preserve active `pending`, in-progress, blocked, needs-input, and failed index
  requests byte-for-byte across architecture refreshes instead of resetting or
  orphaning the job.
- 新增显式 `-InitializeRouting` 安装模式：安装 onboarding 门禁、为每个 Agent
  创建或保留可恢复的首次索引请求。由 Agent 发起安装时会在恢复普通工作前继续
  该任务；在终端安装时由下一次新 Agent 会话继续。
- 新增八阶段首次索引流程，覆盖已注册 MCP Server、已启用插件、已安装 Skill、
  已配置 CLI/API 集成和 Agent 可见内置能力。流程会匹配现有 Skill、执行 A/B/C
  分类、补齐缺失的 A 类指南、构建并验证路由，并且只在所有已启用 A 类能力均
  已解决后激活 runtime 路由。
- 新增后续工具门禁：先检查本地及工具自带 Skill；缺失时询问用户选择检索并
  审查官方 Skill、根据已验证官方文档编写，或保持未路由。
- 架构刷新会逐字节保留 `pending`、处理中、blocked、needs-input 和 failed
  的索引请求，不再重置任务或留下失去控制文件的孤立 job。

### Security and behavior / 安全与行为

- Define “all tools” as capabilities registered with or exposed to the target
  Agent, not every executable on `PATH`. A and B capabilities enter active
  intent routing; C primitives remain managed in inventory with an exclusion
  rationale and bypass active routing.
- Require canonical-source verification, exact commit or artifact pinning,
  non-discoverable staging, and review before activating any remote Skill.
  Insufficient official evidence leaves an A capability unresolved instead of
  generating a speculative guide.
- Bundle the complete Layer 0/1/2 templates with the installed architecture
  Skill and extend verified remote payload coverage to those templates and the
  initial-index reference.
- Make generated rollback scripts remove only the unchanged initial-index
  request created by that installation. Requests already advanced by an Agent
  are preserved with an explicit warning, and malformed request list fields are
  rejected before any target write.
- 将“所有工具”限定为目标 Agent 已注册或实际暴露的能力，而不是扫描 `PATH`
  中的所有程序；A、B 类进入活动意图路由，C 类原语仍纳入受管清单、记录排除
  理由并绕过活动路由。
- 远程 Skill 激活前必须确认 canonical source、固定精确 commit 或 artifact
  digest、在非自动发现目录暂存并完成审查；官方证据不足时保持 A 类未解决，
  不生成推测性指南。
- 已安装架构 Skill 现在包含完整 Layer 0/1/2 模板，远程 payload 校验范围同步
  覆盖这些模板和首次索引 reference。
- 生成的回滚脚本现在只删除由本次安装创建且内容未变化的首次索引请求；已被
  Agent 推进的请求会保留并明确告警，畸形请求中的列表字段则会在任何目标写入
  前被拒绝。

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

[0.2.3]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.2.3
[0.2.2]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.2.2
[0.2.1]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.2.1
[0.2.0]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.2.0
[0.1.5]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.5
[0.1.4]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.4
[0.1.3]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.3
[0.1.2]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.2
[0.1.1]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.1
[0.1.0]: https://github.com/wmqfl861/agent-tool-routing-skill/releases/tag/v0.1.0
