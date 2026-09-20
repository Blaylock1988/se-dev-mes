#!/usr/bin/env python3
"""
query_mes_tags.py — Fast tag and profile query CLI for Modular Encounters Systems (MES).
Searches the local MES source code tag dictionaries to display valid tags, profile types,
expected data types, and source locations.

Usage:
  python query_mes_tags.py --tag "ChangeZone"
  python query_mes_tags.py --profile "Action"
  python query_mes_tags.py --tag "Counters" --profile "Event"
"""

import os
import sys
import re
import argparse

DEFAULT_MES_PATH = os.path.expandvars(
    r'%AppData%\SpaceEngineers\Mods\Modular-Encounters-Systems\Data\Scripts\ModularEncountersSystems'
)

PROFILE_FILES = {
    'RivalAI Action': 'ActionReferenceProfile.cs',
    'RivalAI Condition': 'ConditionReferenceProfile.cs',
    'RivalAI Trigger': 'TriggerProfile.cs',
    'RivalAI Autopilot': 'AutoPilotProfile.cs',
    'RivalAI Target': 'TargetProfile.cs',
    'RivalAI Chat': 'ChatProfile.cs',
    'RivalAI Spawn': 'SpawnProfile.cs',
    'MES Event Action': 'EventActionReference.cs',
    'MES Event Condition': 'EventConditions.cs',
    'MES Spawn Conditions': 'SpawnConditionsProfile.cs',
    'MES Manipulation': 'ManipulationProfile.cs',
    'MES Zone': 'Zone.cs',
}

TYPE_MAP = {
    'TagBoolCheck': 'bool (true/false)',
    'TagStringCheck': 'string',
    'TagStringListCheck': 'List<string> (comma-separated)',
    'TagIntCheck': 'int',
    'TagIntListCheck': 'List<int> (comma-separated)',
    'TagDoubleCheck': 'double',
    'TagDoubleListCheck': 'List<double> (comma-separated)',
    'TagFloatCheck': 'float',
    'TagVector3DCheck': 'Vector3D ({X:0 Y:0 Z:0})',
    'TagVector3DListCheck': 'List<Vector3D>',
    'TagDirectionEnumCheck': 'Direction enum',
    'TagModifierEnumCheck': 'ModifierEnum (None, Add, Multiply, ...)',
    'TagCompareEnumCheck': 'CounterCompareEnum (GreaterOrEqual, Less, Equal, ...)',
    'TagDateTimeCheck': 'DateTime / TimeSpan (ms or ISO)',
    'CustomTagParse': 'custom / block parse',
}

def find_mes_files(mes_path):
    file_map = {}
    for root, _, files in os.walk(mes_path):
        for f in files:
            for ptype, target in PROFILE_FILES.items():
                if f.lower() == target.lower():
                    file_map[ptype] = os.path.join(root, f)
    return file_map

def parse_tags_from_file(file_path):
    tags = []
    if not os.path.exists(file_path):
        return tags

    with open(file_path, 'r', encoding='utf-8', errors='ignore') as fp:
        lines = fp.read().splitlines()

    for idx, line in enumerate(lines, 1):
        # Match dictionary pattern: {"TagName", (s, o) => TagParse.TagTypeCheck(s, ref Var) }
        m_dict = re.search(r'\{\s*"([^"]+)"\s*,\s*\([^)]*\)\s*=>\s*TagParse\.(\w+)\(', line)
        if m_dict:
            tag_name = m_dict.group(1)
            parser_fn = m_dict.group(2)
            data_type = TYPE_MAP.get(parser_fn, parser_fn)
            tags.append((tag_name, data_type, idx))
            continue

        # Match legacy / custom pattern: if (tag.StartsWith("[TagName:")
        m_start = re.search(r'tag\.(?:StartsWith|Contains)\("\[([a-zA-Z0-9_]+):"', line)
        if m_start:
            tag_name = m_start.group(1)
            tags.append((tag_name, 'custom / legacy', idx))

    return tags

def main():
    parser = argparse.ArgumentParser(description='Query MES tags and profile configurations from local MES source.')
    parser.add_argument('-t', '--tag', help='Filter by tag name substring (case-insensitive)')
    parser.add_argument('-p', '--profile', help='Filter by profile type substring (e.g. Action, Condition, Event, Zone)')
    parser.add_argument('-e', '--exact', action='store_true', help='Exact tag name match')
    parser.add_argument('--path', default=DEFAULT_MES_PATH, help='Path to MES source code')
    args = parser.parse_args()

    if not os.path.isdir(args.path):
        print(f"[ERROR] MES source path not found at: {args.path}")
        print("Please specify --path pointing to your local MES install.")
        sys.exit(1)

    file_map = find_mes_files(args.path)
    results = []

    for ptype, fpath in sorted(file_map.items()):
        if args.profile and args.profile.lower() not in ptype.lower():
            continue
        parsed = parse_tags_from_file(fpath)
        for tag_name, dtype, line_no in parsed:
            if args.tag:
                if args.exact:
                    if args.tag.lower() != tag_name.lower():
                        continue
                else:
                    if args.tag.lower() not in tag_name.lower():
                        continue
            results.append((ptype, tag_name, dtype, os.path.basename(fpath), line_no))

    if not results:
        print("No matching tags found.")
        return

    print(f"\nFound {len(results)} matching tag(s):\n")
    print(f"{'Profile Type':<22} | {'Tag Name':<35} | {'Expected Data Type':<30} | Source Location")
    print("-" * 115)

    for ptype, tag_name, dtype, fname, line_no in results:
        print(f"{ptype:<22} | [{tag_name}:...]{' ' * max(0, 27 - len(tag_name))} | {dtype:<30} | {fname}:{line_no}")

    print()

if __name__ == '__main__':
    main()

