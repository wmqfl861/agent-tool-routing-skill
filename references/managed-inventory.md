# Managed Capability Inventory

Read this reference when initial indexing or a later lifecycle operation creates,
updates, disables, removes, or reclassifies an Agent capability.

## Contents

- [Canonical Location](#canonical-location)
- [Document Contract](#document-contract)
- [Capability Records](#capability-records)
- [Publication And Concurrency](#publication-and-concurrency)
- [Lifecycle Updates](#lifecycle-updates)
- [Privacy And Validation](#privacy-and-validation)

## Canonical Location

Maintain exactly one live inventory for each target Agent configuration root:

```text
<agent-config-root>/tool-routing-state/inventory.json
```

Keep this path outside every auto-discovered skill, plugin, command, and hook
root. A file at `tool-routing-state/jobs/<request-id>/inventory.json` is only a
job working copy. It is not the live inventory and must not be used by later
lifecycle work after the job completes.

Resolve the configuration root and existing state-path ancestors to canonical
filesystem paths before every read or write. Reject links, reparse points,
special files, case-folding collisions, and Unicode-normalization collisions.
Use private permissions equivalent to the initial-index job state.

## Document Contract

Write UTF-8 JSON with a trailing newline and this top-level shape:

```json
{
  "schema_version": 1,
  "inventory_id": "6df465b2-a5bd-44e5-b60f-7440197f833a",
  "revision": 4,
  "target_agent": "codex",
  "config_root_fingerprint": "sha256:<normalized-root-digest>",
  "runtime_mode": "auto-discovery",
  "created_at": "2026-07-13T05:00:00Z",
  "updated_at": "2026-07-13T05:30:00Z",
  "source": {
    "operation": "initial-index",
    "request_id": "<request-id>",
    "project_version": "0.2.2"
  },
  "scope": {
    "included": ["enabled user and active-workspace capabilities"],
    "excluded": ["disabled plugins", "unrelated workspaces", "PATH scan"],
    "limitations": []
  },
  "routing": {
    "tree_digest": "sha256:<deterministic-route-tree-digest>",
    "global_rules_digest": "sha256:<managed-sections-digest>"
  },
  "capabilities": []
}
```

Keep `inventory_id` stable for the lifetime of this Agent configuration root.
Increase `revision` by exactly one for every committed lifecycle change. Keep
`created_at` stable and update `updated_at` in UTC. Derive the root fingerprint
from the target Agent identifier plus its normalized, platform-canonical
configuration path; do not use the fingerprint as an authorization secret.

`source.operation` is `initial-index`, `lifecycle-sync`, `add`, `update`,
`disable`, `remove`, `replace`, or `reclassify`. Record a request id when the
operation has one. Scope and limitations must make incomplete runtime discovery
visible instead of claiming machine-wide coverage.

## Capability Records

Give every capability a stable id that survives display-name, version, and
route changes. A record contains at least:

```json
{
  "id": "mcp:example-owner/example-server:search",
  "display_name": "Example Search",
  "kind": "mcp-tool",
  "enabled": true,
  "source": {
    "type": "mcp-server",
    "identity": "example-server/search",
    "provenance": "local-config"
  },
  "scope": ["user", "workspace:<non-sensitive-id>"],
  "classification": "A",
  "classification_evidence": ["external service", "multiple modes"],
  "skill": {
    "status": "official",
    "path": "skills/example-search/SKILL.md",
    "management": "managed",
    "active_refcount": 1,
    "ownership": "managed-exclusive",
    "source_revision": "<immutable-revision>",
    "digest": "sha256:<reviewed-tree-digest>"
  },
  "route": {
    "state": "active",
    "categories": ["find-information"],
    "layer2": "skills/example-search/SKILL.md"
  },
  "exclusion_rationale": null,
  "first_seen_at": "2026-07-13T05:00:00Z",
  "last_seen_at": "2026-07-13T05:30:00Z"
}
```

Use a documented `kind` such as `mcp-server`, `mcp-tool`,
`plugin-capability`, `skill`, `cli-integration`, `api-integration`, or
`builtin`. Treat a plugin as packaging and record separately routable
capabilities separately.

For every Layer 2 guide, record management provenance and sharing separately.
Set `skill.management` to `managed`, `external`, or `unknown`, and set
`skill.active_refcount` to the number of active capabilities that will depend
on the guide after the planned transaction. Never infer managed provenance from
a matching folder name. Treat either field as unknown when an older record
cannot prove it.

Keep `skill.ownership` as a compatibility summary: use `managed-exclusive`
when a managed guide has at most one active reference, `managed-shared` when it
has more than one, `external` for externally managed guides, and `unknown`
otherwise. It is not the deletion gate by itself. Recompute the post-change
reference count from all planned active capability records before deciding a
guide disposition. A guide that was `managed-shared` before removal becomes a
managed orphan when its last reference is removed. Keep `skill.digest` equal to
the last reviewed managed tree so offboarding can detect later user changes.

Apply these class invariants:

- A requires `skill.status` of `local`, `bundled`, `official`, or `authored`,
  immutable provenance when remotely sourced, and an existing Layer 2 path
  before `route.state` can be `active`. Otherwise use `unresolved` and
  `blocked`.
- B uses `skill.status: not-required` and complete Layer 1 guidance. It has no
  Layer 2 path.
- C uses `skill.status: not-required`, `route.state: bypass`, no categories or
  Layer 2 path, and a non-empty `exclusion_rationale`.

Use route states `active`, `bypass`, `blocked`, `disabled`, or `removed`.
Unresolved A capabilities remain recorded as `blocked`, but a candidate route
tree containing them must not become active.

## Publication And Concurrency

During initial indexing, build and validate the job inventory working copy
beside the staged route tree. Publish the canonical inventory only after every
A/B/C record, Skill reference, route, provenance field, and digest validates.

Treat the canonical inventory, generated route tree, and managed global-rule
sections as one recoverable change. Before commit, compare the live inventory
id, revision, and digest plus every affected route digest with the values read
during planning. Stop on drift. Journal the intended revision and all affected
paths, then either publish all of them or restore all of them. Never leave a
new route tree paired with an old inventory or the reverse.

Write the next inventory to a private same-filesystem staging path, flush it,
validate it again, and replace the live file atomically. Keep the previous
inventory in the operation backup until route and runtime validation succeeds.
Do not remove the initial-index request until the canonical inventory and route
commit are both durable.

## Lifecycle Updates

Every authorized add, update, disable, remove, replacement, or reclassification
operation reads this canonical inventory before planning and updates it in the
same recoverable change as routing and managed global instructions.

A current-user request to remove, delete, or uninstall a named or unambiguously
identified capability authorizes the complete managed offboarding transaction
for that capability in the effective Agent scope. It does not need separate
wording for Skill, inventory, route, or managed-global-rule cleanup. It does not
authorize deleting shared or user-modified artifacts, credentials, caches,
browser profiles, user data, accounts, or other capabilities.

For removal, retain a tombstone record with the stable id, last non-sensitive
source identity, former classification, `enabled: false`,
`route.state: removed`, removal time, and concise reason. Remove active route
and Layer 2 references as required. Record the disposition of every affected
managed artifact as removed, archived, shared, modified, external, or retained.
Automatically delete a guide when its post-change `skill.active_refcount` is
zero, managed provenance is proven, and its live digest matches `skill.digest`,
even when its pre-change compatibility label was `managed-shared`. Move a
dedicated managed-but-modified or ownership-unknown orphan intact to the
operation backup's recoverable archive outside every Agent discovery root when
containment and exclusive use can be proven. Do not leave an orphan guide
discoverable merely because it cannot be destroyed automatically.

Retain a shared or external guide only when the negative route test proves it
cannot select the removed capability. If it still exposes that capability and
cannot be safely isolated without changing another owner or active capability,
leave the transaction `blocked` or `needs-input` instead of publishing a false
completion. Record the reason and ask only for the additional edit, move, or
scope authorization needed to continue. A documented local retention policy
may compact old tombstones after their backup and audit retention period
expires.

If a capability is discovered outside an Agent-mediated lifecycle operation,
do not mutate the inventory in the background. Record it during the next
explicitly authorized sync or index. If lifecycle validation or commit fails,
restore the inventory and routes together and report the unchanged revision.

## Privacy And Validation

Do not store secrets, tokens, cookies, environment values, request headers,
private document content, credential-bearing URLs, or raw authentication
output. Use non-sensitive identities and redacted scope labels. The inventory
records whether authentication exists and affects classification, not its
credential value.

Before completion, validate:

- schema version, inventory id, monotonic revision, timestamps, and root
  fingerprint;
- unique stable capability ids and documented kinds/states;
- class invariants, mandatory risk gates, Layer 1/Layer 2 paths, and C exclusion
  rationales;
- source pins and digests for remotely sourced A guides;
- route-tree and managed-global-section digests;
- absence of secrets and unresolved A capabilities in an active route tree;
- atomic publication evidence, backup path, and concrete rollback steps.
