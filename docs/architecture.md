# Architecture

This project defines a layered tool-routing architecture for agents with many
tools. The goal is to make tool choice reliable without making every simple
operation slower.

## Core Idea

Use a small global trigger rule to decide when routing is needed. Once routing
is needed, load progressively more specific skill files:

1. **Global rule**: decide whether the current request needs specialized tool
   routing.
2. **Layer 0 directory**: choose a category by user intent.
3. **Layer 1 category skill**: choose a specific tool or direct helper within
   that category.
4. **Layer 2 tool skill**: provide detailed instructions for one complex tool.

## Layer Responsibilities

### Global Rule

The global rule belongs in the agent's durable instructions, such as
`AGENTS.md`, `CLAUDE.md`, or the equivalent zcode global instruction file.

It should stay short. Its job is only to decide when the agent should read the
directory skill.

It should trigger for:

- internet research;
- website reading, scraping, crawling, or extraction;
- browser-like operation;
- agent/tool setup or repair;
- local file and media handling;
- visual asset generation;
- structured live data;
- MCP tool routing;
- uncertainty about which specialized tool family applies.

It should not trigger for:

- applying patches;
- running known commands or tests;
- updating plans;
- simple shell inspection;
- continuing an already selected workflow;
- using a concrete tool explicitly named by the user;
- project code discovery governed by project instructions.

### Layer 0: Directory Skill

Layer 0 is the light directory. It should answer one question:

> Which category skill should be read next?

Layer 0 should not contain detailed tool instructions. It should not compare
every tool in depth. It should only map user intent to a category.

Good category names describe user intent:

- `find-information`
- `read-and-extract-websites`
- `operate-browser`
- `manage-agent-environment`
- `handle-local-files`
- `create-visual-assets`
- `get-live-data`

Avoid category names that describe implementation internals more than user
intent, such as `devtools` or `codebase`, unless the local agent ecosystem uses
those names consistently and clearly.

### Layer 1: Category Skills

Layer 1 category skills compare tools inside one user-intent family.

They should explain:

- what the category covers;
- which complex tools have Layer 2 skills;
- which simple helpers can be called directly;
- when to escalate from one tool to another;
- what auth, quota, privacy, or safety caveats matter before use.

Layer 1 can directly route to a helper when no Layer 2 skill is needed.

### Layer 2: Tool-Specific Skills

Layer 2 skills explain one complex tool.

They should include:

- when to use the tool;
- when not to use it;
- setup and health checks;
- auth, quota, privacy, and cost behavior;
- main commands, MCP tools, or APIs;
- fallback paths;
- output cleanup and validation;
- source attribution expectations.

Use official or maintainer-provided skills when available. If none exists, write
the skill from official README/docs, CLI help, MCP schemas, examples, and auth
documentation.

## Classification

Classify new capabilities as A, B, or C.

### A: Three-Layer Tool

Use A when the capability has three or more of these traits:

- multiple meaningful modes, subcommands, APIs, or MCP tools;
- overlaps with another specialized tool;
- uses quota, API keys, login state, cookies, browser profiles, or sensitive
  data;
- needs setup checks, auth checks, version checks, or environment checks;
- needs a light-to-heavy failure escalation chain;
- is frequently used for user-visible work;
- needs safety, privacy, source-attribution, or "do not use when" rules;
- wrong use wastes money, time, tokens, or returns misleading results;
- output needs cleanup, validation, or cross-checking.

A tools need Layer 2 skills and should be wired into exactly one primary Layer 1
category unless the tool truly serves multiple independent intent families.

### B: Category-Only Helper

Use B when one or two category lines are enough for safe direct use.

B helpers do not need tool-specific skills. Mention them in the relevant Layer 1
category and state that no separate skill is required.

### C: Implicit Primitive or Default

Use C when the capability is a primitive action, an implicit default, or already
governed by global/project instructions.

Examples:

- patching files;
- running known shell commands;
- updating plans;
- simple local verification;
- built-in code discovery rules already specified by the project.

C capabilities should not appear in Layer 0.

## New Tool Flow

When installing or enabling a new tool, setup is not complete until routing is
handled:

1. Identify the capability and scope.
2. Classify it as A, B, or C.
3. For A, install or create a Layer 2 skill first.
4. For A, wire the skill into the relevant Layer 1 category.
5. For B, add concise guidance to the relevant Layer 1 category.
6. For C, leave it out of the directory.
7. Update Layer 0 only when a new user-intent category is required.
8. Validate paths, frontmatter, routing, and health checks.

See [Onboarding New Tools](onboarding-new-tools.md) for the detailed checklist.
