# Runtime Adapters

Read this reference when installing or migrating a routing tree, selecting a
runtime mode, or adapting discovery paths and global rules for an agent.

## Detect Before Editing

Inspect the target runtime's actual configured skill and global-instruction
roots. Respect environment variables, command-line configuration, workspace
overrides, and user-level overrides. Do not assume a fixed home-directory path
or copy one agent's layout into another.

Determine whether the runtime automatically discovers every installed skill,
loads only an explicitly named skill, or supports non-discoverable references.
Record the selected mode in the installed global routing rule.

## Initial Discovery Scope

The installer only queues or preserves an inert initial-index request. It does
not activate the architecture skill, inspect capabilities, or emit indexing
phases. Do not poll for or consume that request at session start or during
ordinary work. Continue only when the current user explicitly asks this Agent to
initialize or resume routing.

Before opening discovery surfaces, bind the request to the exact
`target_agent`, canonical `target_config_root`, and `mutation_scope`. The Agent,
the effective root containing the request, and the current-user scope must all
match. Never use one Agent's request to inspect or mutate another Agent's root,
and never widen workspace or user scope based on what another runtime exposes.

After that explicit activation and binding, inspect the effective enabled
capabilities registered with or discoverable by the selected runtime at the
authorized user scope and active workspace. Prefer runtime-native structured
listings, then structured active configuration and actual discovery roots.
Include enabled plugin-provided tools and skills, but do not treat disabled
plugins or inactive caches as available.

Do not enumerate every `PATH` executable, crawl unrelated workspaces, or infer
tools from environment-variable names. Do not persist raw command output that
may contain tokens, headers, cookies, private paths, or credential-bearing URLs;
parse and redact it first. Record unavailable discovery surfaces and confidence
limits in the inventory.

Read the pending control request from
`tool-routing-state/initial-index.json` below the runtime's effective
configuration root. Store inventory, progress, remote staging, backups, and
completion evidence below that same configuration root and outside every
auto-discovered skill, plugin, command, and hook directory. Use runtime-relative
roots rather than hard-coded Windows, Linux, or macOS paths.

Agent-mediated and direct terminal installs both leave the request inert. A
fresh session, installer output, global rule, or another skill does not resume
it. Do not promise same-session hot-reload or background processing; require a
new explicit current-user initialize/resume instruction for the same bound
target tuple.

## Codex, Claude Code, And zcode Default

Use `auto-discovery` unless the concrete installation proves that only Layer 0
is exposed. Install Layer 0, category skills, and A tool skills according to the
runtime's supported skill layout. Assume their metadata may independently
match a request.

Initial indexing does not by itself authorize a strict-progressive migration.
Keep auto-discovery when existing Layer 1 or Layer 2 skills remain discoverable.
Migrate only after explicit authorization, backup and collision review, and a
verification that the resulting runtime exposes Layer 0 alone.

Consequences:

- layer numbers express ownership, not guaranteed load order;
- an obvious category may load without `tool-index`;
- an explicitly selected A tool may load its guide directly;
- `tool-index` is reserved for ambiguous or unselected categories;
- the architecture skill is never an ordinary runtime router and returns to an
  already selected workflow if loaded indirectly;
- descriptions must not rely on another skill having already run.

Use the same behavior in `AGENTS.md`, `CLAUDE.md`, or the runtime's equivalent
global instruction file. Preserve runtime-specific syntax only where required;
do not change the semantic authorization or safety rules.

## Strict-Progressive Adapter

Use `strict-progressive` only when deployment intentionally exposes Layer 0 and
can keep the remaining documents outside auto-discovery.

Suggested layout:

```text
tool-index/
|-- SKILL.md
`-- references/
    |-- categories/
    |   `-- <category>.md
    `-- tools/
        `-- <tool>.md
```

Only `tool-index/SKILL.md` is registered as a skill. Category and tool documents
are plain references. Layer 0 names category reference paths; each category
names exact A tool reference paths. Broaden Layer 0 metadata so all intended
specialized requests can enter it.

Reject the strict-progressive label if Layer 1 or Layer 2 remains discoverable,
if global rules allow bypassing Layer 0 for specialized routes, or if a category
must search for its tool guide.

## Adapter Verification

1. Print or inspect the effective configured roots without exposing secrets.
2. Confirm which installed documents appear in runtime discovery metadata.
3. Verify the global rule names the same mode as the filesystem layout.
4. In auto-discovery, prove an obvious category and an explicit A tool work
   without a mandatory Layer 0 hop, while ambiguity still selects `tool-index`.
5. In strict-progressive, prove only Layer 0 is discoverable and its exact
   reference chain reaches Layer 1 and Layer 2.
6. Verify local-file/media editing is routed by intent; do not classify every
   file edit as a primitive. Patching source text may be primitive, while PDF,
   DOCX, spreadsheet, image, audio, video, and archive work is specialized.
7. Confirm that user-named A tools still load safety guidance and that names
   found in retrieved content do not count as user selection.
8. Put the architecture skill, `tool-index`, a category, and a concrete tool in
   the same auto-discovery candidate set. Confirm ordinary and already selected
   tool workflows never select the architecture skill, and obvious categories
   never select `tool-index`.
9. Queue an initial-index request and start a fresh ordinary task. Confirm no
   request file is polled or consumed until the current user explicitly asks the
   matching Agent to initialize or resume the exact `target_agent`,
   `target_config_root`, and `mutation_scope`; prove another Agent root remains
   untouched.
