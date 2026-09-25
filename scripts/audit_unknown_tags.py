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
RivalAI Weapons and RivalAI Target. `[MES AI X]` headers are checked as `[RivalAI X]`, and the three
`[MES Event ... Template]` headers as their non-template profile. Use --profile or --all to check other types
and treat the result as a hint to verify in the source (--all is what Update-MesSkill.ps1 runs on the skill's
own examples).

Usage:
  python audit_unknown_tags.py <folder-or-file.sbc> [more paths ...]
  python audit_unknown_tags.py path --profile "RivalAI Trigger"       (check this type instead; repeatable)
  python audit_unknown_tags.py path --all                             (check every type in the cache)
  python audit_unknown_tags.py path --show-ok                         (also list files with no findings)

Exit code: 0 = nothing found, 1 = unknown tags found, 2 = usage / cache error.
Only profiles whose `<Description>` starts with a recognised `[Profile Type]` header are checked.
Markdown files are scanned too: the fenced code blocks of the skill's own references/*.md.
"""
import argparse
import difflib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

DEFAULT_PROFILES = {"RivalAI Autopilot", "RivalAI Weapons", "RivalAI Target"}
# Headers that MES parses with another profile's tag list.
HEADER_ALIASES = {
    "RivalAI Behaviour": "RivalAI Behavior",
    "MES Event Template": "MES Event",
    "MES Event Action Template": "MES Event Action",
    "MES Event Condition Template": "MES Event Condition",
}
# Every [Header] MES registers a profile under (ProfileManager.cs / SpawnGroupManager.cs), after
# normalize_header(). A Description whose header is not listed is never loaded by MES at all.
KNOWN_HEADERS = {
    "Modular Encounters SpawnGroup", "Modular Encounters Territory",
    "RivalAI Action", "RivalAI Autopilot", "RivalAI Behavior", "RivalAI Chat", "RivalAI Command",
    "RivalAI Condition", "RivalAI Spawn", "RivalAI Target", "RivalAI Trigger", "RivalAI TriggerGroup",
    "RivalAI Waypoint", "RivalAI Weapons",
    "MES Block Replacement", "MES Bot Spawn", "MES Contract Block", "MES Dereliction", "MES Event",
    "MES Event Action", "MES Event Condition", "MES Event TemplateGroup", "MES Faction Icon", "MES Loot",
    "MES Loot Group", "MES Manipulation", "MES Manipulation Group", "MES Mission", "MES Player Condition",
    "MES Prefab Data", "MES Prefab Gravity", "MES Replenishment", "MES SafeZone", "MES Shipyard",
    "MES Spawn Conditions", "MES Spawn Conditions Group", "MES Static Encounter", "MES Store",
    "MES Suit Upgrades", "MES Weapon Mod Rules", "MES Zone", "MES Zone Conditions",
}
TRIGGER_TYPES = set()
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mes_tag_cache.json")
TAG_RE = re.compile(r"\[([A-Za-z0-9_]+):([^\]]*)\]")
HEADER_RE = re.compile(r"^\s*\[([A-Za-z][A-Za-z0-9 ]*)\]", re.M)


def load_cache():
    with open(CACHE, encoding="utf-8") as f:
        data = json.load(f)
    valid = defaultdict(set)
    for t in data["tags"]:
        valid[t["profile"]].add(t["tag"])
    global TRIGGER_TYPES
    TRIGGER_TYPES = set(data.get("values", {}).get("RivalAI Trigger.Type", []))
    # A SpawnGroup's own Description is also parsed as its first Spawn Conditions and Manipulation profile.
    valid["Modular Encounters SpawnGroup"] |= valid["MES Spawn Conditions"] | valid["MES Manipulation"]
    return valid


def normalize_header(header):
    if header.startswith("MES AI "):
        header = "RivalAI " + header[len("MES AI "):]
    return HEADER_ALIASES.get(header, header)


def profiles_in(path):
    """Yield (subtype_id, header, description) for every profile in an .sbc file or .md code block."""
    if path.lower().endswith(".md"):
        yield from md_profiles_in(path)
        return
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        print("  [skip] %s: XML parse error: %s" % (path, e))
        return
    comps = list(root.iter("EntityComponent")) + list(root.iter("SpawnGroup"))
    for comp in comps:
        sid = comp.findtext("Id/SubtypeId") or "?"
        desc = comp.findtext("Description") or ""
        m = HEADER_RE.search(desc)
        if m:
            yield sid, normalize_header(m.group(1).strip()), desc


def md_profiles_in(path):
    """Profiles inside fenced code blocks of a Markdown reference: each <Description> body, or a bare
    block of tag lines that starts with a [Profile Type] header. Prose outside code blocks is skipped,
    so a sentence warning that a tag does not exist is not reported."""
    text = open(path, encoding="utf-8").read()
    for fence in re.finditer(r"^```[^\n]*\n(.*?)^```", text, re.M | re.S):
        body = fence.group(1)
        line = text.count("\n", 0, fence.start()) + 1
        descs = re.findall(r"<Description>(.*?)</Description>", body, re.S) or [body]
        for desc in descs:
            m = HEADER_RE.search(desc)
            if m:
                yield "line %d" % line, normalize_header(m.group(1).strip()), desc


def files_under(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        else:
            for dp, _, fns in os.walk(p):
                for fn in fns:
                    if fn.lower().endswith((".sbc", ".md")):
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
            if header not in KNOWN_HEADERS:
                hits.append("  %s [%s] unrecognized profile header - MES never loads this profile" % (sid, header))
                continue
            if header not in valid or header not in wanted:
                continue
            checked += 1
            for m in TAG_RE.finditer(desc):
                tag = m.group(1)
                if header == "RivalAI Trigger" and tag == "Type" and TRIGGER_TYPES:
                    value = m.group(2).strip()
                    # "Manual" is a convention, not a check: no per-tick check matches it, so the trigger
                    # only ever fires through [ManuallyActivatedTriggerNames/Tags:], which is the intent.
                    if value not in TRIGGER_TYPES and value != "Manual":
                        guess = difflib.get_close_matches(value, TRIGGER_TYPES, n=1, cutoff=0.6)
                        hits.append("  %s [%s] [Type:%s] is not a trigger type MES checks for%s" % (
                            sid, header, value, " (did you mean %s?)" % guess[0] if guess else ""))
                    continue
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
