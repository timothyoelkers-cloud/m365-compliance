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
MAP_CSV  = REPO / "skills" / "mapping" / "control-map" / "map.csv"
EXPECTED          = TESTS / "expected-findings.json"
EXPECTED_CA_PLAN  = TESTS / "expected-ca-plan.json"
EXPECTED_REPORTS  = {
    "cis-m365": TESTS / "expected-cis-m365-report.md",
    "dora":     TESTS / "expected-dora-report.md",
    "nis2":     TESTS / "expected-nis2-report.md",
    "hipaa":    TESTS / "expected-hipaa-report.md",
}

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


# Field rename map: baseline (YAML-friendly) -> Graph (canonical for diff).
# Rationale: Get-MgIdentityConditionalAccessPolicy emits Graph field names;
# our YAML baselines use shorter / Pythonic names for readability. Diff and
# apply happen against Graph shape — never compare baseline shape directly.
_USERS_RENAMES = {
    "include":                          "includeUsers",
    "exclude":                          "excludeUsers",
    "include_users":                    "includeUsers",
    "exclude_users":                    "excludeUsers",
    "include_groups":                   "includeGroups",
    "exclude_groups":                   "excludeGroups",
    "include_roles":                    "includeRoles",
    "exclude_roles":                    "excludeRoles",
    "include_guests_or_external_users": "includeGuestsOrExternalUsers",
    "exclude_guests_or_external_users": "excludeGuestsOrExternalUsers",
}
_APPS_RENAMES = {
    "include":              "includeApplications",
    "exclude":              "excludeApplications",
    "include_applications": "includeApplications",
    "exclude_applications": "excludeApplications",
    "include_user_actions": "includeUserActions",
    "include_authentication_context_class_references":
                            "includeAuthenticationContextClassReferences",
}
_PLATFORM_RENAMES  = { "include": "includePlatforms",  "exclude": "excludePlatforms"  }
_LOCATION_RENAMES  = { "include": "includeLocations",  "exclude": "excludeLocations"  }


def _strip_empty(obj):
    """Drop nulls and empty arrays/objects so two policies that mean the same
       thing but differ in which optional keys they emit compare equal."""
    if obj is None: return None
    if isinstance(obj, list):
        cleaned = [_strip_empty(x) for x in obj]
        cleaned = [x for x in cleaned if x is not None and x != [] and x != {}]
        return cleaned if cleaned else None
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            cleaned = _strip_empty(v)
            if cleaned is not None and cleaned != [] and cleaned != {}:
                out[k] = cleaned
        return out if out else None
    return obj


def _rename_keys(d: dict, renames: dict[str, str]) -> dict:
    if not isinstance(d, dict): return d
    return { renames.get(k, k): v for k, v in d.items() }


def normalise_baseline_ca_policy(policy: dict, declared_strengths: list[dict] | None = None) -> dict:
    """Convert a baseline-shaped CA policy to Graph shape for diff/apply.

       - Field renames: include/exclude_groups/etc -> Graph names
       - authenticationStrength: bare string id -> { id: <id> } object,
         resolving against declared strengths in the resolved baseline
       - Strip empty arrays / null fields"""
    if not isinstance(policy, dict): return policy
    out: dict = {}
    for k in ("id", "displayName", "state"):
        if k in policy: out[k] = policy[k]

    conds = dict(policy.get("conditions") or {})
    new_conds: dict = {}
    if "users" in conds:        new_conds["users"]        = _rename_keys(conds["users"],       _USERS_RENAMES)
    if "applications" in conds: new_conds["applications"] = _rename_keys(conds["applications"], _APPS_RENAMES)
    if "platforms" in conds:    new_conds["platforms"]    = _rename_keys(conds["platforms"],   _PLATFORM_RENAMES)
    if "locations" in conds:    new_conds["locations"]    = _rename_keys(conds["locations"],   _LOCATION_RENAMES)
    for passthrough in ("clientAppTypes", "signInRiskLevels", "userRiskLevels",
                        "servicePrincipalRiskLevels", "authentication_flows", "device_filter"):
        if passthrough in conds:
            # Map to Graph names where they differ
            if passthrough == "authentication_flows":
                new_conds["authenticationFlows"] = conds[passthrough]
            elif passthrough == "device_filter":
                new_conds["deviceFilter"] = conds[passthrough]
            else:
                new_conds[passthrough] = conds[passthrough]
    if new_conds:
        out["conditions"] = new_conds

    gc = dict(policy.get("grantControls") or {})
    if gc:
        new_gc = dict(gc)
        # authenticationStrength: bare string -> { id }
        if isinstance(gc.get("authenticationStrength"), str):
            sid = gc["authenticationStrength"]
            resolved_id = sid
            for s in (declared_strengths or []):
                if s.get("id") == sid:
                    resolved_id = sid  # keep id reference; Graph resolves via tenant strengths
                    break
            new_gc["authenticationStrength"] = { "id": resolved_id }
        out["grantControls"] = new_gc

    if "sessionControls" in policy and policy["sessionControls"] is not None:
        out["sessionControls"] = policy["sessionControls"]

    return _strip_empty(out) or {}


def normalise_scan_ca_policy(policy: dict) -> dict:
    """Strip-empty the scan policy so its sparseness matches the baseline's."""
    return _strip_empty(policy) or {}


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

    declared_strengths_for_norm = ((resolved.get("target") or {}).get("entra") or {}).get("authentication_strengths") or []

    def diff_policy(b_raw: dict, t_raw: dict) -> list[str]:
        b = normalise_baseline_ca_policy(b_raw, declared_strengths_for_norm)
        t = normalise_scan_ca_policy(t_raw)
        fields: list[str] = []
        if b.get("state") != t.get("state"):                                fields.append("state")
        if _norm(b.get("conditions"))     != _norm(t.get("conditions")):    fields.append("conditions")
        if _norm(b.get("grantControls"))  != _norm(t.get("grantControls")): fields.append("grantControls")
        if _norm(b.get("sessionControls")) != _norm(t.get("sessionControls")):
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
# Framework report generator — mirrors scripts/report/New-FrameworkReport.ps1
# ---------------------------------------------------------------------------

import csv as _csv

FRAMEWORK_LABELS = {
    "cis-m365": "CIS Microsoft 365 v6.0.1",
    "dora":     "DORA — Regulation (EU) 2022/2554",
    "nis2":     "NIS 2 Directive — Directive (EU) 2022/2555",
    "hipaa":    "HIPAA — 45 CFR 164",
}


def _load_map() -> list[dict]:
    with MAP_CSV.open(encoding="utf-8") as fh:
        return list(_csv.DictReader(fh))


def render_framework_report(framework: str, findings_doc: dict, *, tenant_display: str = "") -> str:
    if framework not in FRAMEWORK_LABELS:
        raise SystemExit(f"unknown framework: {framework}")

    rows = [r for r in _load_map() if r["framework"] == framework]
    if not rows:
        raise SystemExit(f"no map rows for framework={framework}")

    # Filter findings to this framework
    fw_findings = [
        f for f in findings_doc.get("findings", [])
        if any(fr.get("framework") == framework for fr in (f.get("frameworkRefs") or []))
    ]
    findings_by_control: dict[str, list[dict]] = {}
    for f in fw_findings:
        findings_by_control.setdefault(f["baselineControlId"], []).append(f)

    # Coverage per framework_ref
    by_ref: dict[str, list[dict]] = {}
    for r in rows:
        by_ref.setdefault(r["framework_ref"], []).append(r)

    coverage = []
    for ref in sorted(by_ref.keys()):
        ref_rows  = by_ref[ref]
        primary   = [r for r in ref_rows if r["coverage_type"] == "primary"]
        partial   = [r for r in ref_rows if r["coverage_type"] == "partial"]
        contrib   = [r for r in ref_rows if r["coverage_type"] == "contributes-to"]

        failing: list[str] = []
        for r in ref_rows:
            for f in findings_by_control.get(r["control_id"], []):
                if f.get("actionTaken") != "unchanged":
                    failing.append(r["control_id"])

        if not primary and not partial:
            status = "uncovered"
        elif not primary:
            status = "partial-only"
        else:
            status = "covered"
        if failing:
            status = "drift"

        coverage.append({
            "ref": ref, "status": status,
            "primary":  [r["control_id"] for r in primary],
            "partial":  [r["control_id"] for r in partial],
            "contrib":  [r["control_id"] for r in contrib],
            "failing":  list(dict.fromkeys(failing)),  # dedupe preserve order
        })

    # Evidence index
    evidence: dict[str, set[str]] = {}
    for r in rows:
        evidence.setdefault(r["evidence_artefact"], set()).add(r["framework_ref"])

    label = FRAMEWORK_LABELS[framework]
    tenant = tenant_display or findings_doc.get("tenantId") or "unknown"
    runId  = findings_doc.get("runId") or "unknown"

    out = []
    push = out.append

    push(f"# {label} — Audit-Prep Report\n")
    push(f"**Tenant:** {tenant}\n")
    push(f"**Run id:** {runId}  ")
    push(f"**Generated:** _deterministic-fixture_  ")
    push(f"**Findings file:** findings.json\n")

    total       = len(coverage)
    covered     = sum(1 for c in coverage if c["status"] == "covered")
    drift       = sum(1 for c in coverage if c["status"] == "drift")
    partial_only= sum(1 for c in coverage if c["status"] == "partial-only")
    uncovered   = sum(1 for c in coverage if c["status"] == "uncovered")

    push("## Headline\n")
    push("| Status | Count |")
    push("|---|---|")
    push(f"| Covered (primary deployed, no drift) | {covered} |")
    push(f"| Drift (control deployed but failing) | {drift} |")
    push(f"| Partial-only (no primary control deployed) | {partial_only} |")
    push(f"| Uncovered (no mapped control deployed) | {uncovered} |")
    push(f"| **Total mapped framework references** | **{total}** |\n")

    status_order = { "covered": 0, "drift": 1, "partial-only": 2, "uncovered": 3 }

    push("## Coverage matrix\n")
    push("| Framework reference | Status | Primary controls | Partial controls | Failing |")
    push("|---|---|---|---|---|")
    for c in sorted(coverage, key=lambda x: (status_order[x["status"]], x["ref"])):
        prim = "<br>".join(c["primary"]) if c["primary"] else "—"
        part = "<br>".join(c["partial"]) if c["partial"] else "—"
        fail = "<br>".join(c["failing"]) if c["failing"] else "—"
        push(f"| {c['ref']} | {c['status']} | {prim} | {part} | {fail} |")
    push("")

    push(f"## Findings scoped to {label}\n")
    if not fw_findings:
        push("_No findings tagged with this framework. Either the tenant matches the deployed baseline (good) or the diff-rules don't yet cover the framework's controls (gap)._\n")
    else:
        for severity in ("critical", "high", "medium", "low", "info"):
            bucket = [f for f in fw_findings if f.get("severity") == severity]
            if not bucket: continue
            push(f"### {severity}\n")
            for f in bucket:
                this_ref = next((fr["ref"] for fr in f["frameworkRefs"] if fr["framework"] == framework), "")
                push(f"- **{f['id']}** ({f['workload']})  ")
                push(f"  Maps to: `{this_ref}`  ")
                push(f"  Current: `{f.get('currentValue')}` — Desired: `{f.get('desiredValue')}`  ")
                push(f"  Action: {f.get('actionTaken')} — Evidence: `{f.get('evidenceArtefact')}`\n")

    push("## Evidence index\n")
    push("| Evidence artefact | Backing framework references |")
    push("|---|---|")
    for art in sorted(evidence.keys()):
        refs = "<br>".join(sorted(evidence[art]))
        push(f"| `{art}` | {refs} |")
    push("")

    push("## Gaps\n")
    gaps = [c for c in coverage if c["status"] in ("uncovered", "partial-only", "drift")]
    if not gaps:
        push("_No gaps for the mapped scope. Note: this scope is limited to controls present in skills/mapping/control-map/map.csv. Manual review is still required for framework requirements outside this map._\n")
    else:
        push("| Framework reference | Status | Action |")
        push("|---|---|---|")
        action_for = {
            "drift":        "Investigate failing controls; remediate to baseline",
            "partial-only": "Add a primary control or accept defence-in-depth posture",
            "uncovered":    "No deployed control maps to this requirement — review baseline scope",
        }
        for g in sorted(gaps, key=lambda x: ({"drift":0,"partial-only":1,"uncovered":2}[x["status"]], x["ref"])):
            push(f"| {g['ref']} | {g['status']} | {action_for[g['status']]} |")
        push("")

    push("---\n")
    push("_Generated by `scripts/report/New-FrameworkReport.ps1`. The mapped scope is limited to controls present in `skills/mapping/control-map/map.csv`. Requirements outside the map are not assessed automatically — see the framework skill for manual review guidance._")

    return "\n".join(out) + "\n"


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
        for fw, p in EXPECTED_REPORTS.items():
            md = render_framework_report(fw, actual, tenant_display="Synthetic Test Tenant (fixture)")
            p.write_text(md, encoding="utf-8")
            print(f"updated {p}")
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

    # Per-framework reports
    for fw, p in EXPECTED_REPORTS.items():
        if not p.exists():
            print(f"=== DRIFT — expected report missing: {p}")
            rc = 1; continue
        actual_md   = render_framework_report(fw, actual, tenant_display="Synthetic Test Tenant (fixture)")
        expected_md = p.read_text(encoding="utf-8")
        if actual_md != expected_md:
            print(f"=== DRIFT — {fw} report")
            # Brief diff: compare line counts + first divergence
            a_lines = actual_md.splitlines()
            e_lines = expected_md.splitlines()
            for i, (a, e) in enumerate(zip(a_lines, e_lines)):
                if a != e:
                    print(f"   first divergence at line {i+1}:")
                    print(f"     actual:   {a[:140]}")
                    print(f"     expected: {e[:140]}")
                    break
            else:
                print(f"   line count differs: actual={len(a_lines)} expected={len(e_lines)}")
            rc = 1

    if rc != 0: return rc

    print(f"OK — findings ({actual['summary']['total']}) and ca plan ({ca_plan['summary']}) both match expected")
    print(f"     framework reports: {', '.join(sorted(EXPECTED_REPORTS.keys()))} — all match")
    for k, v in actual["summary"].items():
        if k == "total": continue
        print(f"     findings.{k:9} {v}")
    for k, v in ca_plan["summary"].items():
        print(f"     ca-plan.{k:10} {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
