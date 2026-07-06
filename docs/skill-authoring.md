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

## Versioning

This repository does not need a package version unless it is distributed through
a marketplace that requires one. If versioning is added later, keep a short
`CHANGELOG.md` with user-visible changes only.
