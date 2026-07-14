# Skill Authoring Notes

This repository is both an installable skill and a public project. Keep those
two audiences separate:

- `SKILL.md` is for agents.
- `README.md`, `docs/`, and `examples/` are for humans installing, adapting, or
  reviewing the skill.

## Agent-Facing Skill Rules

When editing `SKILL.md`:

- keep instructions imperative and procedural;
- keep trigger information in the YAML `description`;
- avoid process history and marketing language;
- prefer concise examples over long explanations;
- link to reference files only when the agent should read them conditionally;
- avoid secrets, machine-specific paths, or private tool names.

## Human-Facing Docs Rules

When editing README or docs:

- explain the problem the project solves;
- show install paths for each agent;
- provide copyable snippets;
- explain safety boundaries;
- avoid assuming all agents expose identical tool names;
- keep examples generic enough to adapt.

## Gate Patterns

Use the single-skill gate when an agent installs only `tool-routing-architecture`.
In that pattern, global instructions tell the agent to read this architecture
skill directly before tool setup changes.

Use the two-tier gate when an agent also has a separate `tool-onboarding` skill.
In that pattern, global instructions point to `tool-onboarding`, and
`tool-onboarding` delegates to the architecture skill for A/B/C classification
and layer rules. This keeps lifecycle checklists close to the setup workflow and
keeps the architecture skill focused.

Examples use placeholder categories and tools. Replace them with the installed
agent's actual skills, commands, MCP server names, and tool paths before
deploying a live hierarchy.

Keep onboarding and runtime gates independently deployable. The architecture
skill is sufficient for onboarding rules; runtime rules are valid only when a
real `tool-index/SKILL.md` and its referenced skill tree exist in the selected
agent's skill root.

## Discovery Pattern

Assume flat auto-discovery unless the target runtime and deployment layout
explicitly implement strict-progressive loading. Under auto-discovery, write
Layer 1 and Layer 2 descriptions narrowly enough that they can match directly
without competing with every other layer. `tool-index` resolves broad or
ambiguous category selection; it is not a runtime-enforced mandatory gate.
Keep the architecture skill itself limited to explicit routing-architecture
design, audit, initialization, or maintenance requests. It must not compete
with ordinary tool selection or an already selected category/tool workflow.

For strict-progressive deployments, keep lower layers outside automatic skill
discovery and load them through references or a documented runtime-specific
mechanism. Generate strict-progressive Layer 0 metadata at deployment time;
never put its broad "all specialized routes" trigger into the default
auto-discovery template. State that choice in deployment documentation and test
that a Layer 2 skill cannot trigger before its parent route.

## Trust Rules

Skill descriptions and instructions select workflows; they cannot grant
permission. Secret/private-data access, paid operations, external writes,
persistent authentication, account mutation, production changes, high
privilege, and irreversible actions force A classification and require explicit
authorization gates.

Do not install a remote skill directly into a live skill root. Stage it outside
automatic discovery, pin its owner and revision, record provenance, inspect its
commands and access scope, and review future versions as diffs.

## Versioning

This repository uses Semantic Versioning while it remains pre-1.0. `VERSION` is
the single source of truth and contains the version without a leading `v`.
Release tags use `vMAJOR.MINOR.PATCH`; README badges and `CHANGELOG.md` must
match `VERSION`. The installer copies `VERSION` into every installed skill so a
live deployment can be identified without relying on Git metadata. Do not add a
version field to skill frontmatter because the supported frontmatter contract
contains only `name` and `description`.
