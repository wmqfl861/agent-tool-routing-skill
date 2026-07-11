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

## Codex, Claude Code, And zcode Default

Use `auto-discovery` unless the concrete installation proves that only Layer 0
is exposed. Install Layer 0, category skills, and A tool skills according to the
runtime's supported skill layout. Assume their metadata may independently
match a request.

Consequences:

- layer numbers express ownership, not guaranteed load order;
- an obvious category may load without `tool-index`;
- an explicitly selected A tool may load its guide directly;
- `tool-index` is reserved for ambiguous or unselected categories;
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
