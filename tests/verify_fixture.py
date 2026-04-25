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
EXPECTED = TESTS / "expected-findings.json"

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

    if args.print:
        print(normalise(actual))

    if args.update:
        EXPECTED.write_text(normalise(actual) + "\n", encoding="utf-8")
        print(f"updated {EXPECTED}")
        return 0

    if not EXPECTED.exists():
        print(f"expected-findings.json does not exist; run with --update to create it")
        print(f"actual.summary: {actual['summary']}")
        return 1

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
        return 1

    print(f"OK — {actual['summary']['total']} findings match expected:")
    for k, v in actual["summary"].items():
        if k == "total": continue
        print(f"     {k:9} {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
