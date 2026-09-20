#!/usr/bin/env python3
"""
check_mes_sync.py — Automated Staleness & Version Drift Auditor for MES & RivalAI.
Compares the installed/local MES C# source code against the skill's tag cache metadata
to detect updates, new tags, or modified parsers pushed by Enenra / MES maintainers.

Usage:
  python check_mes_sync.py
  python check_mes_sync.py --path "C:\\Path\\To\\MES"
"""

import os
import sys
import json
import argparse
from query_mes_tags import detect_mes_path, compute_dir_hash, CACHE_FILE, load_cache, build_cache

def main():
    parser = argparse.ArgumentParser(description='Check if se-dev-mes tag cache is in sync with installed MES build.')
    parser.add_argument('--path', help='Path to MES source code')
    parser.add_argument('--auto-update', action='store_true', help='Automatically rebuild cache if drift is detected')
    args = parser.parse_args()

    mes_path = args.path or detect_mes_path()
    if not mes_path or not os.path.isdir(mes_path):
        print("[ERROR] No valid local MES source installation found.")
        print("Checked standard Steam Workshop and %AppData% paths.")
        sys.exit(2)

    cache = load_cache()
    if not cache:
        print("[WARN] No existing tag cache found. Building initial cache...")
        build_cache(mes_path)
        sys.exit(0)

    metadata = cache.get('metadata', {})
    cached_hash = metadata.get('source_hash', '')
    cached_tags = metadata.get('total_tags', 0)
    cached_date = metadata.get('generated_at', 'Unknown')

    current_hash = compute_dir_hash(mes_path)

    print("=" * 70)
    print(" MES Skill Staleness & Sync Audit")
    print("=" * 70)
    print(f"Detected MES Source: {mes_path}")
    print(f"Skill Cache Date:   {cached_date}")
    print(f"Skill Cache Hash:   {cached_hash} ({cached_tags} tags)")
    print(f"Current Local Hash: {current_hash}")
    print("-" * 70)

    if cached_hash == current_hash:
        print("[STATUS: IN SYNC] Skill tag database perfectly matches local MES build.")
        sys.exit(0)

    print("[STATUS: DRIFT DETECTED] Local MES source code has changed since last cache generation!")
    print("Enenra or an MES update has modified files in the MES source tree.")

    if args.auto_update:
        print("\n[ACTION] Rebuilding tag cache now...")
        build_cache(mes_path)
        print("[SUCCESS] Cache synchronized.")
        sys.exit(0)
    else:
        print("\nTo update the skill tag database, run:")
        print("  python scripts/query_mes_tags.py --rebuild-cache")
        print("  OR")
        print("  powershell -ExecutionPolicy Bypass -File scripts/Update-MesSkill.ps1")
        sys.exit(1)

if __name__ == '__main__':
    main()

