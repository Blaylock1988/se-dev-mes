#!/usr/bin/env python3
"""
audit_prefab_thrust.py — Directional Thruster & Behavior Auditor for Space Engineers Prefabs.

Audits prefab SBC XML files to verify directional thruster coverage relative to the
Primary Remote Control block orientation, detecting critical failure modes:
1. Missing Backward (Braking) Thrusters -> 180° flip-and-burn slingshot into space.
2. Missing Lateral / Vertical Thrusters -> Strafe dropouts & dampener suppression.
3. Rover / Ground Vehicle Thrusters    -> Missing Down (downforce) or Up (altitude clamping).
4. FighterPlane Single-Axis Validation -> Permits forward-only thrust on planets.
5. Pitch Lockout Trap                  -> Warns if [FlyLevelWithGravity] or [LevelWithGravityWhenIdle] are set.

Usage:
  python audit_prefab_thrust.py
  python audit_prefab_thrust.py --path "Data/Prefabs"
  python audit_prefab_thrust.py --strict
  python audit_prefab_thrust.py --json
"""

import os
import sys
import re
import json
import argparse
import xml.etree.ElementTree as ET

DIR_VECTORS = {
    "Forward":  (0, 0, -1),
    "Backward": (0, 0, 1),
    "Left":     (-1, 0, 0),
    "Right":    (1, 0, 0),
    "Up":       (0, 1, 0),
    "Down":     (0, -1, 0),
}

def cross_product(v1, v2):
    return (
        v1[1] * v2[2] - v1[2] * v2[1],
        v1[2] * v2[0] - v1[0] * v2[2],
        v1[0] * v2[1] - v1[1] * v2[0]
    )

def negate_vector(v):
    return (-v[0], -v[1], -v[2])

def get_remote_basis(forward_str, up_str):
    f = DIR_VECTORS.get(forward_str, (0, 0, -1))
    u = DIR_VECTORS.get(up_str, (0, 1, 0))
    b = negate_vector(f)
    d = negate_vector(u)
    r = cross_product(f, u)
    l = negate_vector(r)
    return {
        "Forward":  f,
        "Backward": b,
        "Up":       u,
        "Down":     d,
        "Right":    r,
        "Left":     l
    }

def classify_thrust_direction(thrust_forward_str, remote_basis):
    """
    In Space Engineers (ThrusterProfile.cs:90-128):
    Thruster exhaust points out the back (+Forward in block space).
    Therefore, a thruster whose Forward matches remote Backward pushes the grid Forward.
    """
    th_f = DIR_VECTORS.get(thrust_forward_str, (0, 0, -1))
    if th_f == remote_basis["Backward"]:
        return "Forward"
    if th_f == remote_basis["Forward"]:
        return "Backward"
    if th_f == remote_basis["Down"]:
        return "Up"
    if th_f == remote_basis["Up"]:
        return "Down"
    if th_f == remote_basis["Left"]:
        return "Right"
    if th_f == remote_basis["Right"]:
        return "Left"
    return "Unknown"

def extract_custom_data_behavior(custom_data_text):
    if not custom_data_text:
        return None, []
    behavior_match = re.search(r'\[BehaviorName:\s*([^\]]+)\]', custom_data_text)
    behavior = behavior_match.group(1).strip() if behavior_match else None
    
    tags = []
    if re.search(r'\[FlyLevelWithGravity:\s*true\]', custom_data_text, re.IGNORECASE):
        tags.append("FlyLevelWithGravity")
    if re.search(r'\[LevelWithGravityWhenIdle:\s*true\]', custom_data_text, re.IGNORECASE):
        tags.append("LevelWithGravityWhenIdle")
    return behavior, tags

def audit_prefab_file(file_path):
    results = []
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception as e:
        return [{"file": file_path, "status": "ERROR", "message": f"XML parse failure: {e}"}]

    # Locate Prefab definitions
    prefabs = root.findall(".//Prefab")
    if not prefabs and root.tag.endswith("Prefab"):
        prefabs = [root]
    if not prefabs and root.findall(".//CubeGrids"):
        prefabs = [root]

    for p in prefabs:
        subtype_el = p.find(".//Id/SubtypeId")
        prefab_id = subtype_el.text if subtype_el is not None and subtype_el.text else os.path.basename(file_path)

        grids = p.findall(".//CubeGrids/MyObjectBuilder_CubeGrid")
        if not grids:
            grids = p.findall(".//MyObjectBuilder_CubeGrid")
        if not grids:
            continue

        for g_idx, grid in enumerate(grids):
            grid_name_el = grid.find("CustomName")
            grid_name = grid_name_el.text if grid_name_el is not None and grid_name_el.text else f"Grid_{g_idx+1}"

            # Check for wheels (rover indication)
            wheels = grid.findall(".//MyObjectBuilder_CubeBlock[@xsi:type='MyObjectBuilder_MotorSuspension']",
                                  {'xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
            if not wheels:
                wheels = [b for b in grid.findall(".//MyObjectBuilder_CubeBlock") if "MotorSuspension" in b.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")]

            is_wheeled_grid = len(wheels) > 0

            # Find Remote Controls
            remotes = grid.findall(".//MyObjectBuilder_CubeBlock[@xsi:type='MyObjectBuilder_RemoteControl']",
                                   {'xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
            if not remotes:
                remotes = [b for b in grid.findall(".//MyObjectBuilder_CubeBlock") if "RemoteControl" in b.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")]

            if not remotes:
                # No remote control on this grid
                continue

            primary_remote = remotes[0]
            orient_el = primary_remote.find("BlockOrientation")
            rc_forward = orient_el.get("Forward", "Forward") if orient_el is not None else "Forward"
            rc_up = orient_el.get("Up", "Up") if orient_el is not None else "Up"
            basis = get_remote_basis(rc_forward, rc_up)

            custom_data_el = primary_remote.find("CustomData")
            custom_data = custom_data_el.text if custom_data_el is not None else ""
            behavior, warning_tags = extract_custom_data_behavior(custom_data)

            # Find Thrusters
            thrusters = grid.findall(".//MyObjectBuilder_CubeBlock[@xsi:type='MyObjectBuilder_Thrust']",
                                     {'xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
            if not thrusters:
                thrusters = [b for b in grid.findall(".//MyObjectBuilder_CubeBlock") if "Thrust" in b.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")]

            thrust_counts = {
                "Forward": 0,
                "Backward": 0,
                "Up": 0,
                "Down": 0,
                "Left": 0,
                "Right": 0,
                "Unknown": 0
            }

            for t in thrusters:
                t_orient = t.find("BlockOrientation")
                t_forward = t_orient.get("Forward", "Forward") if t_orient is not None else "Forward"
                effective_dir = classify_thrust_direction(t_forward, basis)
                thrust_counts[effective_dir] += 1

            results.append({
                "file": file_path,
                "prefab": prefab_id,
                "grid": grid_name,
                "remote_orientation": f"Fwd={rc_forward}, Up={rc_up}",
                "behavior": behavior,
                "is_wheeled": is_wheeled_grid,
                "thrust_counts": thrust_counts,
                "warning_tags": warning_tags
            })

    return results

def evaluate_grid_thrust(grid_data):
    issues = []
    behavior = grid_data.get("behavior")
    counts = grid_data.get("thrust_counts", {})
    is_wheeled = grid_data.get("is_wheeled", False)
    tags = grid_data.get("warning_tags", [])

    # Pitch lockout tag check
    if "FlyLevelWithGravity" in tags or "LevelWithGravityWhenIdle" in tags:
        issues.append({
            "severity": "WARNING",
            "type": "PITCH_LOCKOUT_TRAP",
            "message": f"Remote contains [FlyLevelWithGravity] or [LevelWithGravityWhenIdle]. In MES, this locks gyro pitch to planetary horizon, preventing nose diving or climbing (RotationSystem.cs:187)."
        })

    # Behavior specific evaluation
    if behavior == "FighterPlane":
        if counts.get("Forward", 0) == 0:
            issues.append({
                "severity": "CRITICAL",
                "type": "MISSING_FORWARD_THRUST",
                "message": "FighterPlane requires at least 1 Forward thruster for attack runs."
            })
        if counts.get("Backward", 0) == 0 and counts.get("Left", 0) == 0 and counts.get("Up", 0) == 0:
            issues.append({
                "severity": "INFO",
                "type": "SINGLE_AXIS_PLANE",
                "message": "FighterPlane uses single-axis forward propulsion. Valid for planetary flight; will fail in zero-G space."
            })
    elif is_wheeled or behavior in ["Rover", "FakeRover"]:
        # Rover evaluation
        if counts.get("Down", 0) == 0:
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_DOWNFORCE_THRUST",
                "message": "Thrust-driven rover has NO Down thrusters. Downward thrusters provide artificial downforce against suspension bounce on rough terrain."
            })
        if counts.get("Up", 0) == 0:
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_ALTITUDE_CLAMP_THRUST",
                "message": "Thrust-driven rover has NO Up thrusters. CalculateHoverThrust() adjusts Y-axis on slopes; missing thrusters can cause dampener dropouts."
            })
        if counts.get("Backward", 0) == 0:
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_BRAKING_THRUST",
                "message": "Rover has NO Backward (braking) thrusters. CalculateStoppingDistance() will return 0, preventing deceleration before waypoint turns."
            })
        if counts.get("Forward", 0) == 0:
            issues.append({
                "severity": "CRITICAL",
                "type": "MISSING_FORWARD_THRUST",
                "message": "Rover has NO Forward thrusters for locomotion."
            })
    elif behavior == "Passive":
        # Passive grids don't navigate
        pass
    else:
        # Standard 3D Space / Hover Behaviors (Fighter, Strike, Horsefly, Sniper, Patrol, Hunter, etc.)
        if counts.get("Backward", 0) == 0:
            issues.append({
                "severity": "CRITICAL",
                "type": "REVERSE_INTO_SPACE_RISK",
                "message": f"Grid has NO Backward (braking) thrusters! Under behavior '{behavior or 'Default'}', MES will exceed MaxSpeed, fail to brake (force=0), overshoot waypoints, flip 180°, and accelerate into deep space at max forward thrust."
            })
        missing_dirs = [d for d in ["Forward", "Up", "Down", "Left", "Right"] if counts.get(d, 0) == 0]
        if missing_dirs:
            issues.append({
                "severity": "ERROR",
                "type": "MISSING_CARDINAL_THRUST",
                "message": f"Grid is missing thrusters in directions: {', '.join(missing_dirs)}. Behaviors using Strafe or Hover will drop dampeners to 0.0001f and induce uncontrolled drift."
            })

    return issues

def main():
    parser = argparse.ArgumentParser(description="Audit Space Engineers prefabs for directional thruster coverage and behavior compatibility.")
    parser.add_argument("--path", "-p", default=".", help="Path to search for prefab .sbc files (defaults to current directory).")
    parser.add_argument("--strict", "-s", action="store_true", help="Treat warnings as errors.")
    parser.add_argument("--json", "-j", action="store_true", help="Output results in JSON format.")
    args = parser.parse_args()

    target_dir = os.path.abspath(args.path)
    if not os.path.exists(target_dir):
        print(f"[ERROR] Target path does not exist: {target_dir}")
        sys.exit(2)

    prefab_files = []
    for root, _, files in os.walk(target_dir):
        for f in files:
            if f.endswith(".sbc") and not f.endswith(".sbcB5"):
                full_path = os.path.join(root, f)
                prefab_files.append(full_path)

    all_audits = []
    total_errors = 0
    total_warnings = 0

    for pf in prefab_files:
        grid_audits = audit_prefab_file(pf)
        for g in grid_audits:
            if "status" in g and g["status"] == "ERROR":
                total_errors += 1
                continue
            issues = evaluate_grid_thrust(g)
            g["issues"] = issues
            for iss in issues:
                if iss["severity"] in ["CRITICAL", "ERROR"]:
                    total_errors += 1
                elif iss["severity"] == "WARNING":
                    total_warnings += 1
            all_audits.append(g)

    if args.json:
        output = {
            "summary": {
                "prefabs_scanned": len(prefab_files),
                "grids_audited": len(all_audits),
                "errors": total_errors,
                "warnings": total_warnings
            },
            "audits": all_audits
        }
        print(json.dumps(output, indent=2))
        sys.exit(1 if (total_errors > 0 or (args.strict and total_warnings > 0)) else 0)

    print("=" * 70)
    print(" Space Engineers Prefab Thruster & Behavior Auditor")
    print("=" * 70)
    print(f"Target Directory: {target_dir}")
    print(f"Prefabs Scanned:  {len(prefab_files)}")
    print(f"Grids Audited:    {len(all_audits)}")
    print("-" * 70)

    for g in all_audits:
        c = g["thrust_counts"]
        print(f"\n[{g['prefab']}] -> {g['grid']} (Behavior: {g['behavior'] or 'Default/Unassigned'})")
        print(f"  Remote Orientation: {g['remote_orientation']}")
        print(f"  Thrust Coverage:    Fwd={c['Forward']} | Back(Brake)={c['Backward']} | Up={c['Up']} | Down={c['Down']} | Left={c['Left']} | Right={c['Right']}")
        
        issues = g.get("issues", [])
        if not issues:
            print("  [PASS] All required thruster directions present.")
        else:
            for iss in issues:
                prefix = f"  [{iss['severity']}] {iss['type']}:"
                print(f"{prefix} {iss['message']}")

    print("\n" + "=" * 70)
    if total_errors == 0 and (total_warnings == 0 or not args.strict):
        print(f"[PASS] Prefab thruster audit passed ({total_errors} errors, {total_warnings} warnings).")
        sys.exit(0)
    else:
        print(f"[FAIL] Prefab thruster audit failed ({total_errors} errors, {total_warnings} warnings).")
        sys.exit(1)

if __name__ == "__main__":
    main()

