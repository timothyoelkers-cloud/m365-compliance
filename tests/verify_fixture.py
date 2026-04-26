#!/usr/bin/env python3
"""
End-to-end fixture verifier — Python port of Resolve-Baseline.ps1 + Compare-TenantState.ps1.

Runs the layered baseline merger and the rule-driven diff engine against the
synthetic-tenant-001 fixture, and asserts the produced findings match
expected-findings.json byte-for-byte.

This is the cross-check for the canonical Pester implementation — two
implementations agreeing on the same fixture = the diff logic is sound.
A drift between the two engines surfaces here without needing PowerShell
or a live tenant.

Exit codes:
    0  fixture verified — actual == expected
    1  drift between actual and expected findings
    2  fixture or rules malformed (read failure, schema violation, etc.)

Usage:
    python3 tests/verify_fixture.py            # assert == expected-findings.json
    python3 tests/verify_fixture.py --update   # write actual to expected (for fixture iteration)
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

import yaml  # PyYAML

REPO     = pathlib.Path(__file__).resolve().parent.parent
TESTS    = REPO / "tests"
FIXTURE  = TESTS / "fixtures" / "synthetic-tenant-001"
BUNDLE   = FIXTURE / "scan-bundle"
RULES    = REPO / "scripts" / "common" / "diff-rules.yaml"
PROFILES = REPO / "baselines" / "profiles"
GLOBAL   = REPO / "baselines" / "global"
EXPECTED         = TESTS / "expected-findings.json"
EXPECTED_CA_PLAN = TESTS / "expected-ca-plan.json"

SEVERITY_ORDER = { "critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4 }


# ---------------------------------------------------------------------------
# Resolver (mirrors scripts/common/Resolve-Baseline.ps1)
# ---------------------------------------------------------------------------

def _read_yaml(p: pathlib.Path) -> dict | None:
    if not p.exists(): return None
    return yaml.safe_load(p.read_text(encoding="utf-8")) or {}


def _is_dict(v: Any) -> bool:  return isinstance(v, dict)
def _is_list(v: Any) -> bool:  return isinstance(v, list) and not isinstance(v, str)


def merge(base: Any, overlay: Any) -> Any:
    """Layered merge: scalars later-wins, dicts recursive, lists with id named-merge,
       lists without id whole-replace, replaces: directive removes lower-layer ids."""
    if overlay is None:    return base
    if base is None:       return overlay
    if _is_dict(base) and _is_dict(overlay):
        out = dict(base)
        for k, v in overlay.items():
            out[k] = merge(out.get(k), v) if k in out else v
        return out
    if _is_list(base) and _is_list(overlay):
        overlay_ids = all(_is_dict(x) and "id" in x for x in overlay)
        base_ids    = all(_is_dict(x) and "id" in x for x in base)
        if not (overlay_ids and base_ids):
            return overlay
        to_remove = set()
        for item in overlay:
            for r in (item.get("replaces") or []):
                to_remove.add(r)
        by_id: dict[str, Any] = {}
        for item in base:
            if item["id"] in to_remove: continue
            by_id[item["id"]] = item
        for item in overlay:
            if item["id"] in by_id:
                by_id[item["id"]] = merge(by_id[item["id"]], item)
            else:
                by_id[item["id"]] = item
        return list(by_id.values())
    return overlay


def _resolve_profile(pin: str) -> tuple[str, dict]:
    name, _, spec = pin.partition("@")
    p = PROFILES / f"{name}.yaml"
    if not p.exists():
        raise SystemExit(f"profile not found: {p}")
    doc = _read_yaml(p) or {}
    if spec and spec != "*" and "version" in doc:
        ver = str(doc["version"])
        if spec.startswith("~"):
            mj, mn = spec[1:].split(".")[:2]
            if ver.split(".")[:2] != [mj, mn]:
                raise SystemExit(f"profile {name} version {ver} fails tilde pin {spec}")
        elif spec.startswith("^"):
            mj = spec[1:].split(".")[0]
            if ver.split(".")[0] != mj:
                raise SystemExit(f"profile {name} version {ver} fails caret pin {spec}")
        elif spec != ver:
            raise SystemExit(f"profile {name} version {ver} != exact pin {spec}")
    return f"profile/{pin}", doc


def resolve_baseline(tenant_yaml_path: pathlib.Path) -> dict:
    tenant = _read_yaml(tenant_yaml_path)
    if not tenant or "tenant" not in tenant:
        raise SystemExit(f"{tenant_yaml_path} is not a tenant registry document")
    layers: list[tuple[str, dict]] = []
    for fname in ("defaults.yaml", "break-glass.yaml"):
        d = _read_yaml(GLOBAL / fname)
        if d: layers.append((f"global/{fname.split('.')[0]}", d))
    for pin in (tenant.get("profiles") or []):
        layers.append(_resolve_profile(pin))
    overrides = REPO / "baselines" / "tenants" / tenant["tenant"]["id"] / "overrides.yaml"
    if overrides.exists():
        layers.append((f"tenant/{tenant['tenant']['id']}/overrides", _read_yaml(overrides) or {}))
    resolved: dict = {}
    for _name, doc in layers:
        to_merge = {k: v for k, v in doc.items() if k not in ("metadata", "version", "rollout")}
        resolved = merge(resolved, to_merge)
    return {
        "schemaVersion": "1.0.0",
        "tenant":   tenant["tenant"],
        "auth_mode": (tenant.get("auth") or {}).get("mode", "unknown"),
        "profiles": tenant.get("profiles") or [],
        "overridesPresent": overrides.exists(),
        "layersApplied": [n for n, _ in layers],
        "target": resolved,
    }


# ---------------------------------------------------------------------------
# Diff engine (mirrors scripts/common/Compare-TenantState.ps1)
# ---------------------------------------------------------------------------

PATH_BRACKET = re.compile(r'^\[(?P<k>[^=]+)=(?P<v>.+)\]$')

def get_by_path(root: Any, path: str) -> Any:
    if root is None or not path:
        return None
    # Tokenise: foo.bar[k=v].baz[*].qux
    segments: list[str] = []
    buf = ""
    i = 0
    while i < len(path):
        ch = path[i]
        if ch == ".":
            if buf: segments.append(buf); buf = ""
            i += 1; continue
        if ch == "[":
            if buf: segments.append(buf); buf = ""
            end = path.index("]", i)
            segments.append(path[i:end+1])
            i = end + 1; continue
        buf += ch
        i += 1
    if buf: segments.append(buf)

    current = root
    for idx, seg in enumerate(segments):
        if current is None:
            return None
        if seg == "[*]":
            if not isinstance(current, list): return None
            if idx == len(segments) - 1: return current
            remainder = ".".join(segments[idx+1:])
            return [get_by_path(item, remainder) for item in current]
        m = PATH_BRACKET.match(seg)
        if m:
            k, v = m.group("k"), m.group("v")
            if not isinstance(current, list): return None
            current = next(
                (it for it in current if isinstance(it, dict) and str(it.get(k)) == v),
                None,
            )
            continue
        if isinstance(current, dict):
            current = current.get(seg) if seg in current else None
        else:
            return None
    return current


def compare(expected: Any, actual: Any, mode: str) -> bool:
    if mode == "equals":              return actual == expected
    if mode == "notEquals":           return actual != expected
    if mode == "greaterOrEqual":      return actual is not None and actual >= expected
    if mode == "lessOrEqual":         return actual is not None and actual <= expected
    if mode == "contains":            return isinstance(actual, list) and expected in actual
    if mode == "notContains":         return isinstance(actual, list) and expected not in actual
    if mode == "presentAndNotNull":   return actual is not None
    if mode == "presentAndNotEmpty":
        if actual is None: return False
        if isinstance(actual, (list, dict, str)): return len(actual) > 0
        return True
    if mode == "allTrue":
        return isinstance(actual, list) and all(x is True for x in actual)
    if mode == "invertedEquals":      return actual == (not expected)
    if mode == "equalsZeroWhenBaseline":
        return (actual == 0) if expected is True else True
    if mode == "tenantSettingDisabled":
        if expected == "disabled":
            return actual is None or actual is False
        return True
    raise SystemExit(f"unknown compareMode: {mode}")


def run_diff(resolved: dict, bundle_dir: pathlib.Path, rules_path: pathlib.Path) -> dict:
    rules_doc = yaml.safe_load(rules_path.read_text(encoding="utf-8"))
    rules = rules_doc.get("rules") or []
    manifest = json.loads((bundle_dir / "manifest.json").read_text(encoding="utf-8"))
    workload_data: dict[str, dict] = {}
    for art in manifest.get("artefacts", []):
        p = bundle_dir / art["path"]
        if p.exists():
            workload_data[art["workload"]] = json.loads(p.read_text(encoding="utf-8"))

    findings: list[dict] = []
    for rule in rules:
        expected = get_by_path(resolved["target"], rule["baselinePath"])
        if expected is None:
            continue   # baseline doesn't declare; rule not applicable
        scan = workload_data.get(rule["scanWorkload"])
        if scan is None:
            findings.append({
                "id": rule["id"],
                "severity": "info",
                "workload": rule["workload"],
                "baselineControlId": rule["baselineControlId"],
                "cisRef": rule["cisRef"],
                "frameworkRefs": rule["frameworks"],
                "currentValue": None,
                "desiredValue": expected,
                "actionTaken": "deferred",
                "evidenceArtefact": f"(no {rule['scanWorkload']} artefact in bundle)",
            })
            continue
        actual = get_by_path(scan, rule["scanPath"])
        if not compare(expected, actual, rule["compareMode"]):
            findings.append({
                "id": rule["id"],
                "severity": rule["severity"],
                "workload": rule["workload"],
                "baselineControlId": rule["baselineControlId"],
                "cisRef": rule["cisRef"],
                "frameworkRefs": rule["frameworks"],
                "currentValue": actual,
                "desiredValue": expected,
                "actionTaken": "reported",
                "evidenceArtefact": f"{rule['scanWorkload']}.json",
            })

    findings.sort(key=lambda f: (SEVERITY_ORDER[f["severity"]], f["workload"], f["id"]))

    return {
        "tenantId": manifest["tenant"]["tenantId"],
        "runId":    manifest["run"]["runId"],
        "rulesFile": str(rules_path.relative_to(REPO)),
        "summary": {
            "total":    len(findings),
            "critical": sum(1 for f in findings if f["severity"] == "critical"),
            "high":     sum(1 for f in findings if f["severity"] == "high"),
            "medium":   sum(1 for f in findings if f["severity"] == "medium"),
            "low":      sum(1 for f in findings if f["severity"] == "low"),
            "info":     sum(1 for f in findings if f["severity"] == "info"),
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# CA apply planner — Python mirror of scripts/apply/Set-ConditionalAccess.ps1
# Limited to the plan/dry-run path. Live writes are PowerShell-only.
# ---------------------------------------------------------------------------

def _norm(obj):
    return None if obj is None else json.dumps(obj, sort_keys=True, separators=(",", ":"))


def compute_ca_plan(resolved: dict, ca_scan: dict, tenant_map: dict[str, str] | None = None) -> dict:
    tenant_map = tenant_map or {}
    tenant_by_id   = { p["id"]: p for p in (ca_scan.get("policies") or []) }
    tenant_by_name = { p["displayName"]: p for p in (ca_scan.get("policies") or []) if p.get("displayName") }

    def resolve_tenant(b_id: str, b_display: str) -> dict | None:
        if b_id in tenant_map and tenant_map[b_id] in tenant_by_id:
            return tenant_by_id[tenant_map[b_id]]
        if b_display and b_display in tenant_by_name:
            return tenant_by_name[b_display]
        return None

    def diff_policy(b: dict, t: dict) -> list[str]:
        fields: list[str] = []
        if b.get("state") != t.get("state"):                                fields.append("state")
        if _norm(b.get("conditions"))     != _norm(t.get("conditions")):    fields.append("conditions")
        if _norm(b.get("grantControls"))  != _norm(t.get("grantControls")): fields.append("grantControls")
        if "sessionControls" in b and _norm(b.get("sessionControls")) != _norm(t.get("sessionControls")):
            fields.append("sessionControls")
        return fields

    actions: list[dict] = []
    summary = { "create": 0, "patch": 0, "unchanged": 0, "remove": 0 }
    bg_group = ((resolved.get("target") or {}).get("entra") or {}).get("break_glass", {}).get("group_id")

    declared_strengths = ((resolved.get("target") or {}).get("entra") or {}).get("authentication_strengths") or []
    declared_strength_ids = { s.get("id") for s in declared_strengths if isinstance(s, dict) }
    builtin_strengths = { "mfa", "passwordlessMfa", "phishingResistantMfa" }

    blocked_by: list[dict] = []
    if not bg_group:
        blocked_by.append({ "rule": "break-glass.declared", "detail": "No break-glass group declared" })

    baseline_policies = ((resolved.get("target") or {}).get("entra") or {}).get("conditional_access_policies") or []
    seen_baseline_displays: set[str] = set()
    seen_tenant_ids:        set[str] = set(tenant_map.values())

    for b in baseline_policies:
        seen_baseline_displays.add(b.get("displayName") or "")
        t = resolve_tenant(b["id"], b.get("displayName") or "")
        if t:
            seen_tenant_ids.add(t["id"])
            fields = diff_policy(b, t)
            if not fields:
                actions.append({
                    "baselineId":   b["id"], "tenantId": t["id"], "displayName": b.get("displayName"),
                    "action":       "unchanged",
                    "reason":       "Tenant policy matches baseline",
                    "currentState": t.get("state"), "targetState": b.get("state"),
                })
                summary["unchanged"] += 1
            else:
                actions.append({
                    "baselineId":   b["id"], "tenantId": t["id"], "displayName": b.get("displayName"),
                    "action":       "patch",
                    "reason":       "Drift in: " + ", ".join(fields),
                    "currentState": t.get("state"), "targetState": b.get("state"),
                    "diffFields":   fields,
                })
                summary["patch"] += 1
                # Forbidden state transition
                if t.get("state") == "disabled" and b.get("state") == "enabled":
                    blocked_by.append({
                        "rule": "state.transition", "baselineId": b["id"],
                        "detail": "Must transition disabled -> enabledForReportingButNotEnforced before -> enabled",
                    })
        else:
            actions.append({
                "baselineId":  b["id"], "displayName": b.get("displayName"),
                "action":      "create",
                "reason":      "Baseline policy not present in tenant",
                "currentState": None, "targetState": b.get("state"),
            })
            summary["create"] += 1

        # Invariant: empty users / applications
        users = (b.get("conditions") or {}).get("users") or {}
        if not (users.get("include") or users.get("includeUsers")):
            blocked_by.append({ "rule": "conditions.users.nonempty", "baselineId": b["id"] })
        apps = (b.get("conditions") or {}).get("applications") or {}
        if not (apps.get("include") or apps.get("includeApplications") or apps.get("include_user_actions")):
            blocked_by.append({ "rule": "conditions.applications.nonempty", "baselineId": b["id"] })

        # Block-policy break-glass exclusion
        gc = b.get("grantControls") or {}
        is_block = "block" in (gc.get("builtInControls") or [])
        if is_block and bg_group:
            excludes = (users.get("exclude_groups") or users.get("excludeGroups") or [])
            if bg_group not in excludes:
                blocked_by.append({
                    "rule": "break-glass.excluded", "baselineId": b["id"],
                    "detail": f"Block policy does not exclude {bg_group}",
                })

        # Non-block must have grantControls or authenticationStrength
        if not is_block:
            has_built = bool(gc.get("builtInControls"))
            has_strength = bool(gc.get("authenticationStrength"))
            if not (has_built or has_strength):
                blocked_by.append({
                    "rule": "grantControls.nonempty", "baselineId": b["id"],
                    "detail": "Non-block policy must declare at least one grant control or authenticationStrength",
                })

        # authenticationStrength references resolve
        ref = gc.get("authenticationStrength")
        if ref and ref not in declared_strength_ids and ref not in builtin_strengths:
            blocked_by.append({
                "rule": "authenticationStrength.resolved", "baselineId": b["id"],
                "detail": f"authenticationStrength '{ref}' not declared and not built-in",
            })

    # Untracked tenant policies
    for t in (ca_scan.get("policies") or []):
        if t["id"] in seen_tenant_ids:                continue
        if (t.get("displayName") or "") in seen_baseline_displays: continue
        actions.append({
            "tenantId":     t["id"], "displayName": t.get("displayName"),
            "action":       "untracked",
            "reason":       "Tenant policy not in baseline (apply will leave alone; review)",
            "currentState": t.get("state"),
        })

    order = { "create": 0, "patch": 1, "unchanged": 2, "untracked": 3, "remove": 4 }
    actions.sort(key=lambda a: (order[a["action"]], a.get("baselineId") or "", a.get("tenantId") or ""))

    return {
        "schemaVersion":    "1.0.0",
        "workload":         "conditional-access",
        "mode":             "plan",
        "tenantId":         resolved["tenant"]["id"],
        "summary":          summary,
        "requiresApproval": False,
        "approvalRef":      None,
        "blockedBy":        blocked_by,
        "actions":          actions,
    }


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def normalise(d: dict) -> str:
    """Canonical JSON for comparison — ignore generated fields."""
    d = dict(d)
    d.pop("generatedAt", None)
    d.pop("resolvedBaseline", None)
    return json.dumps(d, indent=2, sort_keys=False, ensure_ascii=False)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true",
                    help="Overwrite expected-findings.json with current actual output")
    ap.add_argument("--print",  action="store_true",
                    help="Print the actual findings JSON to stdout")
    args = ap.parse_args()

    resolved = resolve_baseline(FIXTURE / "tenant.yaml")
    actual   = run_diff(resolved, BUNDLE, RULES)
    ca_scan  = json.loads((BUNDLE / "conditional-access.json").read_text(encoding="utf-8"))
    ca_plan  = compute_ca_plan(resolved, ca_scan)

    if args.print:
        print("=== findings ===")
        print(normalise(actual))
        print()
        print("=== ca plan ===")
        print(normalise(ca_plan))

    if args.update:
        EXPECTED.write_text(normalise(actual) + "\n", encoding="utf-8")
        EXPECTED_CA_PLAN.write_text(normalise(ca_plan) + "\n", encoding="utf-8")
        print(f"updated {EXPECTED}")
        print(f"updated {EXPECTED_CA_PLAN}")
        return 0

    if not EXPECTED.exists() or not EXPECTED_CA_PLAN.exists():
        print(f"expected outputs missing; run with --update to create them")
        print(f"actual findings.summary: {actual['summary']}")
        print(f"actual ca-plan.summary:  {ca_plan['summary']}")
        return 1

    rc = 0
    expected = json.loads(EXPECTED.read_text(encoding="utf-8"))
    if normalise(actual) != normalise(expected):
        # Show a brief diff
        a_ids = [f"{f['severity']:8}  {f['id']}" for f in actual["findings"]]
        e_ids = [f"{f['severity']:8}  {f['id']}" for f in expected["findings"]]
        print("=== DRIFT — actual vs expected findings ===")
        print(f"actual:   {actual['summary']}")
        print(f"expected: {expected['summary']}")
        print()
        a_set = {f["id"] for f in actual["findings"]}
        e_set = {f["id"] for f in expected["findings"]}
        only_a = a_set - e_set
        only_e = e_set - a_set
        if only_a:
            print("  + Extra in actual (not in expected):")
            for i in sorted(only_a): print(f"      {i}")
        if only_e:
            print("  - Missing in actual (in expected):")
            for i in sorted(only_e): print(f"      {i}")
        rc = 1

    expected_plan = json.loads(EXPECTED_CA_PLAN.read_text(encoding="utf-8"))
    if normalise(ca_plan) != normalise(expected_plan):
        print("=== DRIFT — ca plan vs expected ===")
        print(f"actual.summary:   {ca_plan['summary']}")
        print(f"expected.summary: {expected_plan['summary']}")
        a_ids = { (a.get('action'), a.get('baselineId') or a.get('tenantId')) for a in ca_plan['actions'] }
        e_ids = { (a.get('action'), a.get('baselineId') or a.get('tenantId')) for a in expected_plan['actions'] }
        only_a = a_ids - e_ids
        only_e = e_ids - a_ids
        if only_a:
            print("  + Extra in actual:")
            for i in sorted(only_a, key=lambda x: (x[0] or '', x[1] or '')): print(f"      {i}")
        if only_e:
            print("  - Missing in actual:")
            for i in sorted(only_e, key=lambda x: (x[0] or '', x[1] or '')): print(f"      {i}")
        rc = 1

    if rc != 0: return rc

    print(f"OK — findings ({actual['summary']['total']}) and ca plan ({ca_plan['summary']}) both match expected")
    for k, v in actual["summary"].items():
        if k == "total": continue
        print(f"     findings.{k:9} {v}")
    for k, v in ca_plan["summary"].items():
        print(f"     ca-plan.{k:10} {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
