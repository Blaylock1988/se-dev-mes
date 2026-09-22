#!/usr/bin/env python3
"""
audit_unknown_tags.py - find tags that MES will silently ignore.

MES parses each profile type (`[RivalAI Autopilot]`, `[RivalAI Trigger]`, ...) with a fixed list of
`tag.Contains("[TagName:")` checks. A tag that is not in that list for its profile type is not an error:
MES just never reads it, and the field keeps its default. This script compares every `[Tag:value]` line
inside each profile against `scripts/mes_tag_cache.json` (built from the MES source by
`query_mes_tags.py --rebuild-cache`) and reports tags the profile type does not parse.

Typical hits: a tag copied from an older wiki page or another profile type (`[StrikeBeginPlanetAttackRunDistance]`
in an autopilot profile), a tag that exists as a field but has no parser (`[AttackRunMaxTimeTrigger]`), or a typo.

By default only profile types whose parser is fully covered by the cache are checked: RivalAI Autopilot,
RivalAI Weapon System and RivalAI Target (every tag in their source files is written as `Contains("[Tag:")`).
Other profile types can produce false positives because the cache builder only records bracketed checks, and
some parsers use `tag.Contains("SpawnGroups:")` without the bracket (RivalAI Spawn does). Use --profile or
--all to check them anyway and treat the result as a hint to verify in the source.

Usage:
  python audit_unknown_tags.py <folder-or-file.sbc> [more paths ...]
  python audit_unknown_tags.py path --profile "RivalAI Trigger"       (check this type instead; repeatable)
  python audit_unknown_tags.py path --all                             (check every type in the cache)
  python audit_unknown_tags.py path --show-ok                         (also list files with no findings)

Exit code: 0 = nothing found, 1 = unknown tags found, 2 = usage / cache error.
Only profiles whose `<Description>` starts with a recognised `[Profile Type]` header are checked.
"""
import argparse
import difflib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

DEFAULT_PROFILES = {"RivalAI Autopilot", "RivalAI Weapon System", "RivalAI Target"}
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mes_tag_cache.json")
TAG_RE = re.compile(r"\[([A-Za-z0-9_]+):([^\]]*)\]")
HEADER_RE = re.compile(r"^\s*\[([A-Za-z][A-Za-z0-9 ]*)\]", re.M)


def load_cache():
    with open(CACHE, encoding="utf-8") as f:
        data = json.load(f)
    valid = defaultdict(set)
    for t in data["tags"]:
        valid[t["profile"]].add(t["tag"])
    return valid


def profiles_in(path):
    """Yield (subtype_id, header, description) for every EntityComponent profile in an .sbc file."""
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        print("  [skip] %s: XML parse error: %s" % (path, e))
        return
    for comp in root.iter("EntityComponent"):
        sid = comp.findtext("Id/SubtypeId") or "?"
        desc = comp.findtext("Description") or ""
        m = HEADER_RE.search(desc)
        if m:
            yield sid, m.group(1).strip(), desc


def files_under(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        else:
            for dp, _, fns in os.walk(p):
                for fn in fns:
                    if fn.lower().endswith(".sbc"):
                        yield os.path.join(dp, fn)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--profile", action="append", help="check this profile type instead of the defaults (repeatable)")
    ap.add_argument("--all", action="store_true", help="check every profile type in the cache")
    ap.add_argument("--show-ok", action="store_true")
    a = ap.parse_args()
    try:
        valid = load_cache()
    except (OSError, ValueError, KeyError) as e:
        print("cannot read %s: %s" % (CACHE, e))
        return 2
    wanted = set(valid) if a.all else (set(a.profile) if a.profile else DEFAULT_PROFILES)
    total = 0
    for f in files_under(a.paths):
        hits = []
        checked = 0
        for sid, header, desc in profiles_in(f):
            if header not in valid or header not in wanted:
                continue
            checked += 1
            for m in TAG_RE.finditer(desc):
                tag = m.group(1)
                if tag not in valid[header]:
                    guess = difflib.get_close_matches(tag, valid[header], n=1, cutoff=0.8)
                    other = sorted(p for p, tags in valid.items() if tag in tags and p != header)
                    note = ""
                    if guess:
                        note = " (did you mean %s?)" % guess[0]
                    elif other:
                        note = " (is a %s tag)" % ", ".join(other)
                    hits.append("  %s [%s] [%s:...]%s" % (sid, header, tag, note))
        if hits:
            print("%s" % f)
            print("\n".join(hits))
            total += len(hits)
        elif a.show_ok and checked:
            print("%s: OK (%d profiles)" % (f, checked))
    print("\n%d unknown tag(s) found." % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
