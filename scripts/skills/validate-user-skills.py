#!/usr/bin/env python3
"""Validate the hand-authored skills under the Hermes skills tree.

Only ``user/`` is source in that repo: Hermes recreates category shells on boot and
its curator writes skills into the other categories, so those are reported as notes
instead of failing the run — a gate that is permanently red is a gate nobody reads.

The checks are the ones that have actually caught something here:

* **Frontmatter must parse as real YAML.** A ``description`` containing ``: `` is
  invalid YAML unless quoted, and the loader then skips the skill silently:
  ``hermes skills list`` returns one row fewer and nothing complains. A regex check
  does not catch it, only a parse does.
* ``name`` equals the directory, ``metadata.hermes.category`` equals the parent.
* ``description`` is at most 60 characters — it is the only thing the agent sees
  before deciding whether to load the body.
* Body budget: 60-100 lines of body, 150 total.
* Every ``references/…`` or ``templates/…`` cited resolves, and no support file is
  orphaned (present but never mentioned).
* ``related_skills`` names skills that exist in this tree, so a rename cannot leave
  a forward reference to something that no longer exists.
* No line duplicated across two different skills — copy-paste between them is how a
  library starts disagreeing with itself.

Usage:
  validate-user-skills.py [--tree PATH] [--all]

Exit codes:
  0  everything governed by ``user/`` is clean
  1  a governed skill is broken
  2  PyYAML is missing (the frontmatter check cannot be faked with regexes)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - depends on the host interpreter
    print("PyYAML is required: the frontmatter check cannot be faked with a regex.", file=sys.stderr)
    raise SystemExit(2) from None

GOVERNED_PREFIX = "user"
SUPPORT_DIRS = ("references", "templates", "scripts", "assets")
# A citation counts as local to the skill only when the token is not the tail of a longer
# path: `~/.dotfiles/scripts/icon-contrast.py` names the dotfiles repo, not this skill.
REF_RE = re.compile(r"(?<![\w./~-])(?:references|templates|scripts|assets)/[A-Za-z0-9_.-]+\.\w+")
BODY_TARGET, TOTAL_CAP, DESC_CAP = 100, 150, 60


def default_tree() -> Path:
    """The resolved skills tree: ~/.hermes/skills is a symlink into the dotfiles."""
    override = os.environ.get("HERMES_SKILLS_TREE")
    if override:
        return Path(override).expanduser().resolve()
    return (Path.home() / ".hermes" / "skills").resolve()


def skill_dirs(tree: Path) -> list[Path]:
    return sorted(
        child / name
        for child in tree.iterdir()
        if child.is_dir()
        for name in os.listdir(child)
        if (child / name / "SKILL.md").is_file()
    )


def support_files(skill: Path) -> set[str]:
    present = set()
    for sub in SUPPORT_DIRS:
        directory = skill / sub
        if directory.is_dir():
            present |= {f"{sub}/{entry.name}" for entry in directory.iterdir() if entry.is_file()}
    return present


def check(skill: Path, known_names: set[str], duplicate_lines: dict[str, list[str]]):
    """Return (problems, stats) for one skill directory."""
    text = (skill / "SKILL.md").read_text(encoding="utf-8")
    name, category = skill.name, skill.parent.name
    problems: list[str] = []
    try:
        front = yaml.safe_load(text.split("---")[1])
    except Exception as exc:  # noqa: BLE001 - any parse failure is the finding
        return [f"frontmatter does not parse: {exc}"], {}

    meta = (front.get("metadata") or {}).get("hermes") or {}
    total = text.count("\n") + (0 if text.endswith("\n") else 1)
    body = total - (text.split("---")[1].count("\n") + 2)
    description = front.get("description", "")

    if front.get("name") != name:
        problems.append(f"name {front.get('name')!r} != directory {name!r}")
    if meta.get("category") != category:
        problems.append(f"category {meta.get('category')!r} != parent {category!r}")
    if len(description) > DESC_CAP:
        problems.append(f"description is {len(description)} chars (cap {DESC_CAP})")
    if body > BODY_TARGET:
        problems.append(f"body is {body} lines (target {BODY_TARGET})")
    if total > TOTAL_CAP:
        problems.append(f"total is {total} lines (cap {TOTAL_CAP})")
    for related in meta.get("related_skills") or []:
        if related not in known_names:
            problems.append(f"related_skills names {related!r}, which does not exist here")

    present = support_files(skill)
    cited: set[str] = set()
    sources = [skill / "SKILL.md"] + sorted((skill / sub / f) for sub in SUPPORT_DIRS
                                           if (skill / sub).is_dir()
                                           for f in os.listdir(skill / sub) if f.endswith(".md"))
    for source in sources:
        found = set(REF_RE.findall(source.read_text(encoding="utf-8")))
        cited |= found
        for ref in sorted(found - present):
            problems.append(f"{source.relative_to(skill)} cites missing {ref}")
    for orphan in sorted(present - cited):
        problems.append(f"never cited from SKILL.md: {orphan}")

    # Duplication is a body problem, and only counts when two DIFFERENT skills share the
    # line: one owner means the line merely exists, which is not a finding.
    body_text = text.split("---", 2)[2]
    for line in set(body_text.splitlines()):
        stripped = line.strip()
        if len(stripped) > 40 and not stripped.startswith(("#", "|", "-", "1.", "2.", "```")):
            duplicate_lines[stripped].append(f"{skill.parent.name}/{name}")
    return problems, {"body": body, "total": total, "support": len(present), "desc": len(description)}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate the user/ skills against the house conventions.",
        epilog="Notes are reported for anything outside user/, which this repo does not own.",
    )
    parser.add_argument("--tree", type=Path, default=None,
                        help="skills tree to check (default: the resolved ~/.hermes/skills)")
    parser.add_argument("--all", action="store_true",
                        help="govern every category, not only user/ (a gate for a full audit)")
    args = parser.parse_args()

    tree = (args.tree or default_tree()).expanduser().resolve()
    if not tree.is_dir():
        print(f"not a directory: {tree}", file=sys.stderr)
        return 1

    skills = skill_dirs(tree)
    known = {skill.name for skill in skills}
    duplicates: dict[str, list[str]] = defaultdict(list)
    failed = False

    for skill in skills:
        label = str(skill.relative_to(tree))
        governed = args.all or skill.parent.name == GOVERNED_PREFIX
        problems, stats = check(skill, known, duplicates)
        print("%-40s body=%s total=%s support=%s desc=%s" % (
            label, stats.get("body"), stats.get("total"), stats.get("support"), stats.get("desc")))
        for problem in problems:
            if governed:
                failed = True
                print(f"    ! {problem}")
            else:
                print(f"    . note (not this repo's): {problem}")

    for line, where in duplicates.items():
        owners = set(where)
        if len(owners) < 2:  # one owner: the line exists, nobody duplicated it
            continue
        categories = {owner.split("/")[0] for owner in owners}
        if args.all or GOVERNED_PREFIX in categories:
            failed = True
            print(f"DUPLICATED across skills: {line[:70]}  <- {sorted(owners)}")

    print(f"\n{len(skills)} skill(s) checked — {'FAIL' if failed else 'OK'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
