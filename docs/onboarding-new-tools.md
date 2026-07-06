# Onboarding New Tools

This guide explains how a newly installed tool enters the routing architecture.
It is the human-facing companion to the "Tool Onboarding Gate" in `SKILL.md`.

## Completion Rule

A tool setup task is not complete just because the tool installed, connected, or
appeared in a tool list.

Setup is complete only after:

1. the capability is identified;
2. the tool is classified as A, B, or C;
3. routing is updated or explicitly left unchanged;
4. validation has run;
5. rollback or recovery instructions are clear when config files were changed.

## Identify the Capability

Record:

- name and kind: MCP, CLI, skill, plugin, API, native helper, PATH entry, or
  routing rule;
- target agent scope: Codex, Claude Code, zcode, or another agent;
- install/config location;
- official repository or documentation source;
- authentication, API key, login, cookie, quota, cost, or privacy behavior;
- main modes, subcommands, MCP tools, or APIs;
- overlap with existing tools;
- expected user-facing tasks.

## Classify as A, B, or C

### A: Three-Layer Tool

Choose A when the tool is complex enough to need a dedicated tool-specific
skill.

Common examples:

- web search/research routers;
- website crawlers and scrapers;
- browser automation tools;
- remote MCP servers with many tools;
- API-key-backed services;
- tools with login/cookie/browser-profile state;
- tools with overlapping alternatives and fallback chains.

Action:

1. Check for an existing local Layer 2 skill.
2. Search the official GitHub repository or official docs for `SKILL.md`,
   `.codex`, `skills/`, `docs/skills`, or agent integration docs.
3. Prefer official or maintainer-provided skills.
4. If none exists, write a concise Layer 2 skill from official docs, README, CLI
   help, MCP schemas, examples, auth docs, and failure modes.
5. Wire the skill into exactly one primary Layer 1 category unless the tool
   truly belongs to multiple independent user-intent families.

### B: Category-Only Helper

Choose B when the helper is simple enough that one or two category lines are
safe.

Common examples:

- current time;
- weather;
- finance quotes;
- sports schedules;
- simple image viewing;
- small helper commands used after a route is already obvious.

Action:

1. Add concise guidance to the relevant Layer 1 category.
2. State that no tool-specific skill is required.
3. Include any auth, cost, privacy, or scope caveat that matters before direct
   use.

### C: Implicit Primitive or Default

Choose C when the capability should stay outside the routing directory.

Common examples:

- applying patches;
- running known shell commands;
- updating plans;
- reading obvious local files;
- project code discovery rules already governed by project instructions.

Action:

1. Do not add it to Layer 0.
2. Do not create a Layer 2 skill.
3. If future confusion is likely, document the decision in the architecture
   maintenance notes, not in the tool directory.

## Update Order

For A tools:

1. Create or install the Layer 2 tool-specific skill.
2. Validate frontmatter and file paths.
3. Add the tool to the relevant Layer 1 category.
4. Update Layer 0 only if the tool introduces a new user-intent category.
5. Run health checks for the tool or MCP server.

For B tools:

1. Update the relevant Layer 1 category.
2. Validate that the category says no tool-specific skill is required.

For C capabilities:

1. Leave the directory unchanged.
2. Mention the reason only if needed to prevent repeated mistaken additions.

## Validation Checklist

- `SKILL.md` frontmatter exists.
- `name` matches the skill folder name.
- Layer 1 paths point to existing Layer 2 skills for every A tool.
- B helpers explicitly say no tool-specific skill is required.
- C capabilities are not accidentally added to Layer 0.
- MCP, CLI, plugin, PATH, or API health checks pass when applicable.
- Disabled plugins remain disabled unless explicitly approved.
- Model/provider/API endpoint settings were not changed unless explicitly
  requested.
- Secrets are not printed in logs, docs, or final answers.
- Rollback instructions exist for changed config files.

## Example

New tool: `crawl4ai`.

Classification: A.

Reason:

- multiple crawling and extraction modes;
- overlaps with Scrapling and Firecrawl;
- can use browser sessions, hooks, proxies, and structured extraction;
- wrong use can waste time or return incomplete data.

Routing:

- Layer 1 category: `read-and-extract-websites`.
- Layer 2 skill: `crawl4ai-official`.
- Layer 0 change: none, because website reading/extraction already exists as a
  user-intent category.
