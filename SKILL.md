---
name: tool-routing-architecture
description: >
  Design, install, audit, or maintain a Codex tool-routing skill architecture
  with a global trigger rule, a light tool directory, category skills, and
  tool-specific skills. Use when classifying tools as three-layer tools,
  category-only helpers, or implicit primitives; writing tool-index/category/tool
  SKILL.md files; deciding when agents should read tool documentation before
  calling tools; onboarding newly installed tools into the hierarchy; or
  repairing an agent's tool-routing rules.
---

# Tool Routing Architecture

Use this skill to build or maintain a tool-selection system for Codex agents.
The system should let agents choose tools on their own without making every
simple task slower.

The architecture has four parts:

1. A short global instruction tells the agent when to enter the tool directory.
2. Layer 0, the directory skill, routes user intent to one category skill.
3. Layer 1, category skills, choose the concrete tool or direct helper.
4. Layer 2, tool-specific skills, explain how to use complex tools safely.

Tool setup has one extra gate: when an agent installs, enables, configures,
repairs, updates, or removes a tool, the setup is not complete until the tool is
classified and either wired into this hierarchy or explicitly left out.

Do not put every native agent tool into this architecture. Primitive actions and
implicit defaults should stay implicit.

## Required Global Rule

Add a short rule to the agent's global instructions, such as `AGENTS.md`. This
rule is what makes the directory useful without forcing every ordinary tool call
through it.

Use this text as the baseline:

```markdown
## Tool Directory Routing

When a user request requires a specialized tool family and the correct tool has
not already been selected, read the `tool-index` skill before calling
specialized tools. Use `tool-index` only to choose a category. Then read the
selected category skill.

If the category selects a complex tool with its own skill, read that
tool-specific skill before calling the tool. If the category selects a simple
helper with no tool-specific skill, call that helper directly using the category
skill's inline guidance.

Trigger the directory for internet research, website reading or scraping,
browser operation, agent/tool setup, local file or media handling, visual asset
generation, structured live data, MCP tool routing, or uncertainty about which
specialized tool family applies.

Skip the directory for primitive actions such as applying patches, running known
commands or tests, updating plans, simple shell inspection, continuing an
already selected workflow, or using a concrete tool explicitly named by the
user.

Do not force every tool call through the directory. Existing-project code
discovery follows the project's code-discovery instructions directly.
```

Keep global instructions small. Put routing detail in skills, not in
`AGENTS.md`.

## Required Tool Onboarding Gate

Add a second short rule to the same global instructions. This rule makes newly
installed tools enter the routing architecture automatically and makes removed
tools leave it cleanly.

Use this text as the baseline:

```markdown
## Tool Onboarding Gate

Before installing, enabling, configuring, repairing, updating, or removing any
tool, MCP server, skill, plugin, CLI, external API integration, API-key-backed
service, PATH entry, or tool routing rule, read the tool-routing architecture
skill.

A tool setup task is not complete just because the tool installed or connected.
Classify the capability as A, B, or C. If routing should change, update the
tool hierarchy before declaring completion.

For A tools, install or create the Layer 2 tool-specific skill first, then wire
it into the relevant Layer 1 category. If no local Layer 2 skill exists, search
the official GitHub repository or official docs for a maintained skill. If none
exists, write one from official docs, README, CLI help, MCP schemas, examples,
and authentication docs.

For B helpers, add concise guidance to the relevant Layer 1 category and state
that no tool-specific skill is required. For C primitives or implicit defaults,
do not add them to the directory.

When removing, disabling, or replacing a tool, remove its Layer 1 routes, delete
or archive its Layer 2 skill when unused, update replacements, clean global
rules/docs/examples/config references, and search for dangling references before
declaring completion.

Do not update Layer 0 unless a new user-intent category is required. Do not
enable plugins or modify model/provider/API endpoint settings unless the user
explicitly asked for that specific change.
```

If the agent supports a separate `tool-onboarding` skill, the global rule may
point to that skill first. The `tool-onboarding` skill should then tell the
agent to read this architecture skill for the A/B/C classification and layer
rules. If the agent has only this skill, this skill is enough by itself.

## Runtime Routing

Use this procedure when an agent is deciding whether to read the directory:

1. Identify the user's real intent.
2. If the request is primitive, use the native capability directly.
3. If the user explicitly names one concrete tool, read that tool's skill if it
   has one; otherwise use the tool directly.
4. If a workflow already selected a tool family, continue that workflow.
5. If the request enters a specialized tool family and the tool is not obvious,
   read Layer 0, the directory skill.
6. Read exactly one relevant Layer 1 category skill unless the request spans
   independent tool families.
7. If Layer 1 selects an `A` tool, read the exact Layer 2 skill path named by
   Layer 1 before calling the tool.
8. If Layer 1 selects a `B` helper, call it directly using Layer 1 guidance.
9. If the task shifts families, route again only for the new family.
10. Escalate from cheap/simple tools to heavier tools only when output is
    blocked, incomplete, stale, or low quality.

Example family shift: broad internet lookup can start in `find-information`.
After it finds a specific URL to scrape, route into `read-and-extract-websites`.

## One-Step Tool Onboarding

Use this workflow whenever a tool setup task is started. It covers MCP servers,
CLIs, skills, plugins, API integrations, API-key-backed services, PATH entries,
and tool routing rule changes.

The setup is not complete until all required routing steps and validation steps
are done.

1. Back up affected files before changing them:
   - global instructions such as `AGENTS.md` or `CLAUDE.md`
   - affected skill folders
   - MCP, CLI, plugin, PATH, API, or tool config files that will be edited
   - enough state to roll back any environment variable created for auth
2. Identify the capability:
   - name and kind: MCP, CLI, skill, plugin, API, native helper, PATH entry, or
     routing rule
   - target agents
   - install/config location
   - official repository and docs
   - auth, API key, cookie, login, quota, cost, and privacy behavior
   - main modes, subcommands, MCP tools, or APIs
   - overlap with existing tools
   - expected user-facing tasks
3. Install or configure the tool using the agent's normal setup mechanism.
4. Run the lightest useful health check:
   - MCP: list/get/status the server and confirm the tool names.
   - CLI: run `--help`, `version`, `doctor`, or an equivalent non-destructive
     check.
   - Skill: validate frontmatter and folder name.
   - API/keyed service: confirm auth without printing secrets.
5. Classify the capability as `A`, `B`, or `C` using the rules in this skill.
6. For `A`:
   - check whether a local Layer 2 skill already exists
   - search the official GitHub repository or official docs for `SKILL.md`,
     `.codex`, `skills/`, `docs/skills`, or agent integration docs
   - install/copy the official skill if one exists
   - otherwise write a concise Layer 2 skill from official README, docs, CLI
     help, MCP schemas, examples, and authentication docs
   - update exactly one primary Layer 1 category unless multiple user-intent
     families truly apply
7. For `B`:
   - add a concise direct-helper rule to the relevant Layer 1 category
   - explicitly say no tool-specific skill is required
8. For `C`:
   - keep it out of `tool-index`
   - avoid creating a Layer 2 skill
   - add a short note only if future agents are likely to misclassify it
9. If the task removes, disables, or replaces a tool:
   - remove the tool from every Layer 1 category that routes to it
   - delete or archive the Layer 2 tool skill when no remaining route uses it
   - remove tool-specific mentions from Layer 0, global instructions, examples,
     docs, README, MCP/plugin/CLI/API/PATH config, and current decision lists
     unless the mention is intentionally historical
   - update replacement guidance if another tool now handles those tasks
   - search affected roots for the removed tool name, command, MCP server name,
     skill path, plugin id, env var, and docs path
   - state whether credentials, browser profiles, caches, or local data were
     left in place or removed
10. Update Layer 0 only when the new capability introduces a new user-intent
   category. Do not add vendor/tool names to Layer 0.
11. Validate:
    - `SKILL.md` frontmatter exists and names match folder names
    - Layer 1 paths point to existing Layer 2 skills for every `A` tool
    - `B` helpers explicitly say no tool-specific skill is required
    - `C` capabilities are not accidentally added to Layer 0
    - removed tools have no dangling Layer 0, Layer 1, Layer 2, global-rule,
      MCP/plugin/CLI/API/PATH, README, docs, or examples references
    - MCP/CLI/plugin/API health checks pass where applicable
    - secrets are not printed and are not stored in the wrong config file
    - disabled plugins remain disabled unless the user explicitly enabled them
    - model/provider/API endpoint settings were not changed unless requested
    - rollback instructions are concrete
12. Run a route test that proves the new capability is reachable through the
    expected layer path and that Layer 0 was not changed unnecessarily. For
    removals, run a negative route test proving the removed tool is no longer
    selected.
13. In the final response, report:
    - classification: `A`, `B`, or `C`
    - files/configs changed
    - where the tool was added, removed, replaced, or why routing was unchanged
    - validation result
    - backup and rollback location

### MCP Onboarding Notes

MCP servers are tools in this architecture. Classify each MCP server by behavior,
not by the fact that it is MCP.

Use `A` for MCP servers with multiple tools or modes, external auth, quota/cost,
overlap with existing tools, setup requirements, or meaningful failure routing.
Create a Layer 2 skill that names the exposed MCP tools and explains when to
use each one.

Use `B` for small, narrow MCP helpers that are safe to call directly from a
category skill.

Use `C` for MCP servers that are implicit project defaults governed by global
or project instructions, such as code-discovery graph tools when code-discovery
rules already require them.

Store MCP secrets through environment variables or the client's secret store
when possible. Prefer config entries that reference secret names over config
entries that embed raw tokens. Do not print tokens in logs or final answers.

### Example Onboarding Results

Example `A`: a Firecrawl MCP server with search, scrape, map, crawl, extract,
agent, and interact tools. Create `firecrawl-mcp`, add it to
`read-and-extract-websites`, and keep Layer 0 unchanged.

Example `A`: a GitHub repository reader MCP with `search_doc`,
`get_repo_structure`, and `read_file`. Create a Layer 2 skill for the MCP, add
it to `find-information`, and keep Layer 0 unchanged.

Example `B`: a direct weather lookup helper. Add a short line to
`get-live-data` saying no tool-specific skill is required.

Example removal: removing a crawler MCP. Remove its Layer 1 route from
`read-and-extract-websites`, delete or archive its Layer 2 skill if unused,
remove MCP config and docs/examples mentions, search for the server name and
skill path, then run a negative route test that no scraping task selects it.

Example `C`: a project code-discovery graph MCP already mandated by global
instructions. Keep it out of the directory and follow the project rule directly.

## Two Concepts

Keep these concepts separate.

Layers describe documentation roles:

| Layer | Name | Job | Contains | Must not contain |
| --- | --- | --- | --- | --- |
| 0 | Directory | Choose a category from user intent | Category names and paths | Concrete tool commands |
| 1 | Category | Choose a tool inside one intent family | Tool choice rules, Layer 2 paths, direct-helper rules | Long tool manuals |
| 2 | Tool | Explain one complex tool | Commands, MCP tools, auth, quotas, setup, failure handling | Broad category routing |

A/B/C classifies capabilities:

| Class | Meaning | Where documented | How used |
| --- | --- | --- | --- |
| A | Complex three-layer tool | Mention in Layer 1, document in Layer 2 | Read Layer 2 before calling |
| B | Simple category-only helper | Mention in Layer 1 only | Call directly from Layer 1 guidance |
| C | Implicit primitive/default | Usually not in directory or categories | Use directly |

## Capability Classification

Classify each tool or capability before editing skills.

Use `A` when the tool has at least three of these traits:

- Multiple meaningful modes, APIs, MCP tools, or subcommands.
- Overlaps with another specialized tool.
- Uses quotas, API keys, login state, cookies, browser profiles, or sensitive
  data.
- Needs environment checks, setup checks, authentication checks, or version
  checks.
- Needs a light-to-heavy escalation chain.
- Is frequently used for user-visible work.
- Needs safety, privacy, source attribution, or "do not use when" rules.
- Wrong use wastes money, time, tokens, or returns misleading results.
- Output needs cleanup, validation, or cross-checking.

Use `B` when one or two lines in a category skill are enough. Typical examples
are weather lookup, current time, simple finance quote lookup, sports schedule
lookup, image viewing, or a known verifier command after the route is clear.

Use `C` when the capability is an agent primitive or an implicit default.
Typical examples are `apply_patch`, plan updates, parallel file reads, simple
shell commands, or project code discovery rules that are already mandated by
global/project instructions.

Do not add automatic code-discovery tools to the directory when global or
project instructions already say to use them. The agent should follow those
instructions directly.

## Layer 0 Directory Skill

Layer 0 should be a small `tool-index` skill. It answers only one question:
"Which category skill should I read?"

Layer 0 should include:

- One entry per user-intent category.
- The exact category skill name or relative path.
- A short skip section for primitives and implicit defaults.

Layer 0 should not include:

- Concrete tool commands.
- Authentication or API-key details.
- Long comparisons.
- Every installed native tool.

### How To Choose Layer 0 Categories

Design Layer 0 categories from user intent, not from tool names. A good category
is a sentence the user might naturally ask for: find information, read a
website, operate a browser, manage agent tools, handle local files, get live
data, or create visual assets.

Create a Layer 0 category when all of these are true:

- The intent appears repeatedly across user requests.
- The intent can contain more than one concrete tool or direct helper.
- A category skill can make a meaningful choice or escalation decision.
- The name is understandable without knowing implementation internals.

Do not create a Layer 0 category when:

- It would contain only one obvious primitive action.
- It is named after an implementation detail, such as `devtools` or
  `codebase`, rather than what the user wants done.
- The behavior is already covered by global/project instructions, such as code
  discovery defaults.
- It is just a vendor or tool name. Vendor/tool names belong in Layer 1 or
  Layer 2.

When adding a new category, write three things before editing `tool-index`:

1. Trigger phrase: what the user says.
2. Boundary: when the request belongs somewhere else.
3. Next skill: exact category skill path.

Example:

```markdown
Trigger: user asks to click, type, fill a form, inspect rendered page state, or
capture browser evidence.
Boundary: reading page text without interaction belongs to
`read-and-extract-websites`.
Next skill: `../operate-browser/SKILL.md`.
```

Template:

```markdown
---
name: tool-index
description: >
  First-read directory for choosing specialized tool families. Use at
  tool-routing decision points such as internet research, website extraction,
  browser operation, agent/tool setup, local file handling, visual asset
  creation, live data, MCP routing, or uncertainty about which tool family
  applies. Do not use for primitive actions or already selected workflows.
---

# Tool Index

Use this skill only to choose a category. Do not call concrete tools from this
index.

If the user asks to search, research, compare public sources, inspect platforms,
or gather online evidence, read `../find-information/SKILL.md`.

If the user provides URLs or asks to read, scrape, crawl, map, summarize, or
extract website data, read `../read-and-extract-websites/SKILL.md`.

If the user asks Codex to operate a page, click, type, fill forms, inspect
rendered state, or capture browser evidence, read `../operate-browser/SKILL.md`.

If the user asks to install, configure, repair, or verify tools, MCP servers,
skills, API keys, PATH, or agent configuration, read
`../manage-agent-environment/SKILL.md`.

Skip this index for applying patches, running known commands/tests, updating
plans, simple shell work, already selected workflows, explicitly named concrete
tools, and project code discovery covered by project instructions.
```

## Layer 1 Category Skills

Layer 1 is where the real routing decision happens. A category skill compares
tools inside one intent family and tells the agent what to read or call next.

Every category skill should include:

- Scope: what belongs in this category.
- Boundary: what should be routed elsewhere.
- Tool choice rules in priority order.
- Conflict rules for overlapping tools.
- Escalation rules from simple to heavy.
- For every `A` tool: the exact Layer 2 skill name or relative path.
- For every `B` helper: enough inline guidance to call it directly.

Layer 1 must not make the agent hunt for Layer 2. If a selected tool has a
Layer 2 skill, Layer 1 gives the path. If a selected helper has no Layer 2 skill,
Layer 1 explicitly says no tool-specific skill is required.

Template:

```markdown
---
name: read-and-extract-websites
description: >
  Choose tools for reading, scraping, crawling, mapping, summarizing, or
  extracting content from websites and URLs.
---

# Read And Extract Websites

Use this category when the task is about website content itself.

## Tool Choice

Use `firecrawl-mcp` first for known URLs, clean Markdown, site maps, bounded
crawls, and structured extraction. Then read `../firecrawl-mcp/SKILL.md`.

Use `scrapling-official` when Firecrawl returns empty or blocked content, or
when local browser-backed scraping, stealth, selectors, screenshots, or spiders
matter. Then read `../scrapling-official/SKILL.md`.

Use a direct shell verifier only for simple local checks after the scraping
route is clear. No tool-specific skill is required.

## Escalation

Start with scrape for one known URL. Use map before crawl when URL discovery is
needed. Use local browser-backed scraping only after simple extraction is likely
insufficient.

## Boundaries

Use `find-information` for broad research. Use `operate-browser` when the user
needs clicking, typing, form filling, or rendered browser inspection.
```

## Layer 2 Tool-Specific Skills

Layer 2 is for `A` tools only. It explains one concrete tool well enough that an
agent can use it safely without prior conversation context.

Every Layer 2 tool skill should include:

- Best use cases.
- When not to use it.
- Concrete commands, MCP tool names, or API usage patterns.
- Setup, health checks, auth, login, API key, cookie, quota, and cost notes.
- Safe defaults and scope limits.
- Escalation and fallback rules.
- Output validation expectations.
- Privacy and secret-handling rules.

Keep the main `SKILL.md` short enough to read. Put platform-specific or
mode-specific detail in direct `references/*.md` files only when needed.

Template:

```markdown
---
name: firecrawl-mcp
description: >
  Use Firecrawl through the configured MCP server for web search with page
  content, URL scraping, site maps, crawls, structured extraction, and cloud web
  workflows.
---

# Firecrawl MCP

Use this tool for known URL extraction, clean Markdown, site maps, bounded
crawls, and structured JSON extraction.

Prefer broad research tools for multi-platform research. Prefer local scraping
tools when local browser state, stealth behavior, screenshots, selectors, or
avoiding credits matters.

## Tool Choice

Use `firecrawl_scrape` for one known URL. Use `firecrawl_map` before broad
crawls. Use `firecrawl_extract` for schema-shaped data. Use autonomous agent or
interaction tools only when simpler tools are insufficient.

## Safety

Do not print API keys. Keep crawls bounded. Avoid duplicate scrapes when search
results already include page content.

## Failure Routing

If content is empty, blocked, stale, or low quality, retry with narrower options
or route to the local scraping tool named by the category skill.
```

## Missing Layer 2 Skills

When a selected `A` tool has no Layer 2 skill yet, do not invent the tool
instructions from memory. Build or install the tool skill in this order:

1. Check whether the skill is already installed locally under the agent's skills
   directory.
2. Search the tool's official GitHub organization/repository for `SKILL.md`,
   `.codex`, `skills/`, `docs/skills`, or agent integration docs.
3. Prefer an official or maintainer-provided skill over a community skill.
4. If an official skill exists, install or copy it into the agent's skills
   directory, then review its frontmatter, paths, secrets handling, and commands
   before wiring it into Layer 1.
5. If no official skill exists, write the Layer 2 skill from the tool's official
   README, docs, CLI help, MCP tool schemas, examples, and authentication docs.
6. If official docs are incomplete, use the smallest reliable source set needed
   and mark uncertain behavior as a validation requirement in the skill.
7. Validate the new skill, then run a route test that actually reaches it.

When writing a Layer 2 skill yourself, include the source basis in the body only
when it helps future maintenance. Do not paste long upstream docs. Summarize
the operational rules the agent needs: when to use the tool, when not to use it,
how to check setup, how to call it, how to control cost/scope, how to handle
failures, and how to validate output.

Layer 1 should not point to a missing Layer 2 skill. If a tool is `A`, create or
install its Layer 2 skill first, then add the Layer 1 pointer.

## Maintenance Workflow

Use this workflow when adding, removing, or changing tools.

For tool setup tasks, use **One-Step Tool Onboarding** above. It is the full
completion definition.

For architecture-only edits where no tool is being installed or configured:

1. Back up live skills and agent instructions before editing.
2. Classify any affected capability as `A`, `B`, or `C`.
3. Update exactly the required layer.
4. Validate skill structure.
5. Run realistic route tests.
6. Keep rollback instructions concrete.

For removals, do not stop after uninstalling, disabling, or deleting the tool.
Also remove or update every route, skill pointer, global rule, docs/example
mention, current decision list entry, MCP/plugin/CLI/API/PATH config, and
replacement instruction that would make a future agent select the removed tool.
Search for dangling references before reporting completion.

Do not put backup files, scratch notes, or review documents inside the final
skill folder that will be installed. Keep installable skill folders clean.

## Route Tests

Run route tests after changes. A route test checks which skills the agent would
read and whether it avoids unnecessary layers.

Use examples like these:

- "Find the latest three posts from a public social account." Expected route:
  global rule -> `tool-index` -> `find-information` -> broad research tool;
  after finding URLs, route to `read-and-extract-websites`.
- "Scrape this known article URL." Expected route: global rule ->
  `tool-index` -> `read-and-extract-websites` -> extraction tool skill.
- "What is the weather in San Francisco tomorrow?" Expected route: global rule
  -> `tool-index` -> `get-live-data` -> direct weather helper, no Layer 2.
- "Run the tests." Expected route: skip directory, run known command.
- "Apply this patch." Expected route: skip directory, use primitive edit tool.
- "Inspect this existing codebase." Expected route: follow project code
  discovery instructions directly, not the tool directory.
- "Fix an agent PATH problem." Expected route: global rule -> `tool-index` ->
  `manage-agent-environment`.

## Common Category Set

Use category names based on user intent, not implementation names.

Useful categories:

- `find-information`: search, research, platform lookup, public evidence.
- `read-and-extract-websites`: URLs, scraping, crawling, mapping, extraction.
- `operate-browser`: open, click, type, fill forms, inspect rendered pages.
- `manage-agent-environment`: tools, MCP, API keys, PATH, skills, plugins.
- `handle-local-files`: documents, PDFs, spreadsheets, images, audio, archives.
- `get-live-data`: time, weather, markets, sports, structured current data.
- `create-visual-assets`: image generation, image editing, bitmap assets.

Avoid vague categories such as `devtools`, `codebase`, or `misc`. If a browser
DevTools tool is mainly used to control a web page, put it under
`operate-browser`.

## Quality Checklist

Before calling the architecture complete, verify:

- A fresh agent knows when to read `tool-index`.
- A fresh agent knows when to skip `tool-index`.
- A fresh agent knows that tool setup must pass the Tool Onboarding Gate.
- A fresh agent knows that tool removal must clean routes and dangling
  references before completion.
- Layer 0 routes only to categories.
- Layer 1 can choose between overlapping tools.
- Layer 1 gives exact Layer 2 paths for every `A` tool.
- Layer 1 says when a `B` helper should be called directly.
- Layer 2 exists only for complex tools that need it.
- `C` primitives stay out of the directory.
- Newly installed tools are classified as `A`, `B`, or `C` before completion.
- Removed tools are absent from Layer 1 routes, unused Layer 2 skills, global
  rules, examples, docs, and config references.
- Expensive, authenticated, quota-limited, or sensitive tools have safety rules.
- Source attribution and output validation are specified where relevant.
- Global instructions are short and do not duplicate the whole architecture.
- The installable skill folder is clean and validation passes.

## Anti-Patterns

Avoid these patterns:

- Requiring the directory before every tool call.
- Putting native primitives such as patching or planning in the directory.
- Making Layer 0 choose concrete tools.
- Making Layer 1 mention tools but not say whether to read Layer 2 or call
  directly.
- Creating Layer 2 skills for trivial helpers.
- Hiding auth, quota, or cost rules outside the tool-specific skill.
- Using category names that describe implementation internals instead of user
  intent.
- Installing a tool and declaring success without classification, routing
  updates, validation, and rollback.
- Removing a tool binary or MCP config while leaving Layer 1, Layer 2, examples,
  docs, or global rules pointing to it.
- Embedding raw API keys or bearer tokens into reusable skill docs or final
  answers.
- Asking the user to choose a tool when category rules are enough.
- Installing the architecture without running at least one realistic route test.
