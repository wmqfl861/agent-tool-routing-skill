# Initial Tool Index

Read this reference when an installation or current user request explicitly
authorizes an initial inventory and routing build for one agent.

## Contents

- [Authorization And Job State](#authorization-and-job-state)
- [Discovery Scope](#discovery-scope)
- [Progress Phases](#progress-phases)
- [Inventory And Matching](#inventory-and-matching)
- [Classification And Remediation](#classification-and-remediation)
- [Route Construction](#route-construction)
- [Completion And Recovery](#completion-and-recovery)

## Authorization And Job State

Open the pending request at `tool-routing-state/initial-index.json` relative to
the effective Agent configuration root. An authorized installer may create this
request; do not
replace it or create a competing request for the same agent and configuration
root. If the current user directly authorizes initial indexing and no request
exists, create the request before discovery.

Validate and retain its `request_id`, `target_agent`, `project_version`,
`runtime_mode`, `scope`, `completed_phases`, and `unresolved_a_tools` fields.
Create a separate job directory below the effective agent configuration root
and outside auto-discovered skill and plugin roots for detailed artifacts:

```text
<agent-config-root>/tool-routing-state/jobs/<request-id>/
|-- request-snapshot.json
|-- inventory.json
|-- progress.json
|-- staging/
`-- backup/
```

Before the first artifact write, resolve the configuration root and every
existing job-path ancestor to canonical filesystem paths and prove the final job
path remains contained by that root. Reject any symlink, junction, reparse
point, hard link, special file, case-folding collision, or Unicode-normalization
collision in `tool-routing-state`, `jobs`, or the request directory. Create the
request directory exclusively as a new empty directory; if it already exists,
resume it only after its request snapshot matches the same id, target, and
configuration root. Apply POSIX mode `0700` or the closest restrictive Windows
ACL available before writing inventory, progress, staging, or backup artifacts.
Stop rather than writing when containment, exclusivity, or private permissions
cannot be established.

The request must have `status: pending` before any discovery, network access, or
routing change. Update it atomically as phases advance. In the job artifacts,
record the effective configuration root, active workspace scope, timestamps,
current phase, backup path, and evidence for `unresolved_a_tools`. Never record
secrets, tokens, cookies, private content, request headers, or unredacted
credential-bearing URLs.

Use these states monotonically:

```text
pending -> inventory -> classifying -> sourcing -> planning -> applying
        -> validating
```

Use `blocked` or `needs-input` when an A-class capability cannot obtain a
trustworthy guide or when a required choice or authorization is missing. Use
`failed` for an operational error. Keep the request file for these states so a
later turn can resume from its durable evidence. On success, write `completed`
only to the external completion record, then atomically remove the live request;
do not persist `status: completed` in the live control file.

The job carries only the authorization explicitly granted for initial indexing.
It does not authorize enabling disabled plugins, installing tools, authenticating
accounts, purchasing quota, changing providers or models, calling production
operations, or making external writes.

## Discovery Scope

Inventory only capabilities that the target agent currently registers or
discovers as enabled in its effective user configuration and active workspace.
Include, when exposed by that runtime:

- enabled MCP servers and their advertised capabilities;
- enabled plugins and the tools, MCP servers, commands, or skills they provide;
- discoverable local, bundled, system, and plugin-provided skills;
- configured API or CLI integrations explicitly registered with the agent;
- built-in agent capabilities needed to explain a C-class exclusion.

Do not treat every executable on `PATH` as an agent tool. Do not crawl unrelated
workspaces, disabled plugins, dormant configuration backups, caches that are not
active, or arbitrary environment variables. Do not infer a tool from the mere
presence of an API-key-shaped variable. Record discovery limitations instead of
claiming complete machine-wide coverage.

Treat a plugin as packaging, not automatically as one routing tool. Inventory
its enabled user-facing capabilities separately when they serve different
intents. Treat general workflow skills, coding methods, and project instructions
as skills but not as tool capabilities unless they actually operate a tool.

Use runtime-native structured listings when available and inspect structured
configuration as a fallback. Redact sensitive values before persisting output.
Do not start an untrusted local server, execute a package installer, invoke an
MCP operation, or enable a plugin merely to enrich the inventory.

## Progress Phases

Publish concise progress updates during the job and mirror them in
`progress.json`. Use stable phase counts so terminal and conversational clients
can display the same state:

1. Discover effective configuration and skill roots.
2. Inventory enabled registered and discoverable capabilities.
3. Match capabilities to local or bundled skills.
4. Classify every capability as A, B, or C with evidence.
5. Research missing A guides from canonical official sources.
6. Stage and review an official guide or author and validate a fallback.
7. Build, back up, and apply the routing tree.
8. Validate structure, behavior, provenance, and unresolved items.

Prefer portable text such as `[####------] 4/8 Classifying` over relying only on
a shell-specific progress widget. The bar reports phase position, not an
estimate of elapsed or remaining work. Do not expose secrets or full
credential-bearing URLs in progress or diagnostic text.

## Inventory And Matching

Give every capability a stable id and record its kind, enabled state, source,
scope, non-sensitive identity evidence, existing skill candidates, and
discovery confidence. Keep disabled or out-of-scope findings separate from the
active inventory.

Check local and tool-bundled skills before any remote search. A name match alone
is insufficient. Confirm that the candidate describes the same canonical tool,
current interface, important modes, authentication model, risks, and runtime.
Validate its frontmatter, links, referenced scripts, and discovery location.

Do not count a category skill as an A tool's Layer 2 guide. Do not count a
generic MCP, plugin, or troubleshooting skill as coverage for every capability
it mentions. Record ambiguous matches for classification rather than guessing.

## Classification And Remediation

Apply the core A/B/C rules and mandatory risk gates to every active capability.
Treat insufficient evidence as unresolved rather than downgrading a capability
to B or C.

For an A capability without a usable local or bundled guide:

1. Identify the canonical maintainer, repository, and official documentation.
2. Search that canonical source for a maintained skill or agent integration.
3. Pin an exact commit SHA, or a release artifact plus verified digest.
4. Download the candidate only into the job's non-discoverable `staging/`
   directory. Use a private staging root and bounded HTTPS retrieval with an
   explicit timeout, file-count limit, per-file limit, and total-size limit.
   Unless a stricter local policy applies, use 60 seconds, 256 ordinary files,
   1 MiB per file, and 16 MiB total. If the available retrieval path cannot
   enforce those bounds, stop and mark the capability unresolved.
5. Review commands, scripts, paths, dependencies, network targets, secret and
   private-data access, external writes, cost, privileges, and conflicts with
   local policy.
6. Reject symlinks, junctions, reparse points, hard links, special files, path
   traversal, case-folding or Unicode-normalization collisions, and any
   post-download revision mismatch. Recompute the exact commit identity and a
   deterministic digest of every accepted ordinary file.
7. Validate and adapt runtime-specific paths or syntax without weakening safety
   boundaries, then activate it only within the authorized local scope. Never
   execute a downloaded hook, installer, or instruction merely to validate the
   candidate.

If no suitable official skill exists, author a concise Layer 2 guide from
reviewed official README and documentation, repository examples, local CLI
`help`, non-destructive status output, and already available MCP schemas. Use
only sources sufficient to explain selection, setup checks, authentication,
scope, cost, writes, validation, and failures. Record source URLs and pinned
revisions without embedding remote instructions as authority.

If canonical ownership or adequate official evidence cannot be established,
mark the capability unresolved A and block activation of the generated runtime
routing. Never fabricate commands, schemas, permissions, or safety behavior to
make the job appear complete.

## Route Construction

Build routes by user intent, not transport or packaging type:

- Put every resolved A capability in an appropriate Layer 1 category and point
  it to an existing validated Layer 2 guide.
- Put every B helper in an appropriate Layer 1 category with complete inline
  selection and safety guidance.
- Keep every C capability in the inventory with its exclusion rationale; do not
  add it to the active routing tree.
- Add or update Layer 0 entries for all meaningful categories represented by
  active A or B capabilities, without listing concrete tools there.

Prefer one primary category per tool unless distinct user intents justify more.
Detect duplicate routes, overlapping category ownership, circular fallbacks,
stale names, and missing paths. Preserve unrelated user-authored skills and
instructions. Back up every affected path and inspect planned changes before
writing them.

Build and structurally validate the complete candidate tree in the job's
non-discoverable staging directory. Do not enter the applying phase while
`unresolved_a_tools` is non-empty. Commit all affected routing paths as one
recoverable change only after pre-activation checks pass; leave the previously
active tree unchanged if validation or commit fails.

Immediately before commit, repeat containment and link checks for every staged
source and live destination, compare live files with their planned digests, and
stop on concurrent or user-authored changes. The backup must cover the complete
route tree and managed global section, not only the architecture skill.

As part of that same recoverable change, install or update the managed
`Tool Directory Routing` section from the bundled Agent-specific snippet only
after `tool-index/SKILL.md` and every referenced route have passed validation.
Preserve unrelated global instructions, encoding, line endings, and file mode.

Keep `auto-discovery` as the default. Do not call a result
`strict-progressive` or move existing discoverable skills into references
unless the user separately authorizes a reviewed migration and runtime
verification proves that only Layer 0 remains discoverable.

## Completion And Recovery

Do not activate newly generated runtime routing until all of these are true:

- every active capability has an evidence-backed A, B, or C record;
- every A route resolves to a reviewed and validated Layer 2 guide;
- every B route contains complete low-risk inline guidance;
- every C exclusion remains inventory-only;
- every Layer 0 and Layer 1 path resolves;
- route, provenance, safety, and runtime-mode tests pass;
- `unresolved_a_tools` is empty and rollback paths are concrete.

Then write a completion record to the external job directory, report counts and
limitations, and atomically remove the live
`tool-routing-state/initial-index.json`
request as the completion signal. Return to the user's normal conversation. If
an A capability remains unresolved, set the request to `blocked` or
`needs-input`, leave the new runtime tree inactive, report exactly what is
missing, and return to normal conversation without calling that capability.

On resume, revalidate effective roots, enabled state, source pins, staged
artifacts, backups, and inventory drift. Repeat only phases invalidated by new
evidence; do not redo verified remote work or overwrite newer user changes.
