#!/usr/bin/env python3
"""Generate the deterministic payload manifest used by install-remote.ps1."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "scripts" / "install-manifest.json"
REPOSITORY = "wmqfl861/agent-tool-routing-skill"
FIXED_FILES = (
    "VERSION",
    "SKILL.md",
    "examples/AGENTS.md.snippet",
    "examples/CLAUDE.md.snippet",
    "scripts/install.ps1",
)
PAYLOAD_DIRECTORIES = ("agents", "references")
SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)


def payload_paths() -> list[Path]:
    paths = {ROOT / relative for relative in FIXED_FILES}
    for relative in PAYLOAD_DIRECTORIES:
        directory = ROOT / relative
        if not directory.is_dir():
            raise SystemExit(f"Missing payload directory: {directory}")
        paths.update(path for path in directory.rglob("*") if path.is_file())

    ordered = sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())
    for path in ordered:
        if not path.is_file():
            raise SystemExit(f"Missing payload file: {path}")
        if path.is_symlink():
            raise SystemExit(f"Payload files must not be symbolic links: {path}")
        try:
            path.resolve(strict=True).relative_to(ROOT.resolve(strict=True))
        except ValueError as exc:
            raise SystemExit(f"Payload file escapes repository root: {path}") from exc
    return ordered


def main() -> int:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not SEMVER_RE.fullmatch(version):
        raise SystemExit(f"VERSION is not valid semantic version text: {version!r}")

    files = []
    for path in payload_paths():
        content = path.read_bytes()
        if b"\r" in content:
            relative = path.relative_to(ROOT).as_posix()
            raise SystemExit(f"Remote payload must use LF newlines: {relative}")
        files.append(
            {
                "path": path.relative_to(ROOT).as_posix(),
                "sha256": hashlib.sha256(content).hexdigest(),
                "size": len(content),
            }
        )

    manifest = {
        "schema_version": 1,
        "repository": REPOSITORY,
        "version": version,
        "files": files,
    }
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Wrote {MANIFEST_PATH} with {len(files)} verified payload files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
