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

## Versioning

This repository does not need a package version unless it is distributed through
a marketplace that requires one. If versioning is added later, keep a short
`CHANGELOG.md` with user-visible changes only.
