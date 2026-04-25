#!/usr/bin/env python3
"""
Build manifest.json for the synthetic-tenant-001 fixture deterministically.

Reads the per-workload JSON files in scan-bundle/, computes their SHA-256,
writes manifest.json with correct artefacts[*].sha256, and computes the
manifest's own integrity.manifestSha256 the same way Invoke-TenantScan.ps1
does (hash the manifest with integrity.manifestSha256 = '' and signature = null).

Usage: python3 tests/build_fixture.py
"""
from __future__ import annotations

import hashlib
import json
import pathlib

FIXTURE = pathlib.Path(__file__).resolve().parent / "fixtures" / "synthetic-tenant-001"
BUNDLE  = FIXTURE / "scan-bundle"

WORKLOADS = [
    "entra",
    "conditional-access",
    "exchange",
    "sharepoint",
    "teams",
    "purview",
    "defender",
    "intune",
]


def sha256_of(path: pathlib.Path) -> tuple[str, int]:
    h = hashlib.sha256()
    data = path.read_bytes()
    h.update(data)
    return h.hexdigest(), len(data)


def build_manifest() -> dict:
    artefacts = []
    for w in WORKLOADS:
        p = BUNDLE / f"{w}.json"
        if not p.exists():
            continue
        sha, n = sha256_of(p)
        artefacts.append({
            "workload":   w,
            "path":       f"{w}.json",
            "sha256":     sha,
            "bytes":      n,
            "producedBy": f"Invoke-{w.replace('-','').title()}Scan.ps1@1.0.0-fixture",
        })

    manifest = {
        "schemaVersion": "1.0.0",
        "tenant": {
            "tenantId":    "00000000-0000-0000-0000-aaaaaaaaaaaa",
            "displayName": "Synthetic Test Tenant (fixture)",
            "region":      "EU-North",
            "jurisdictions": ["GB"],
            "tenantClass": "synthetic",
        },
        "run": {
            "runId":       "00000000-0000-0000-0000-cccccccccccc",
            "mode":        "audit",
            "startedAt":   "2026-04-25T10:00:00Z",
            "completedAt": "2026-04-25T10:00:30Z",
            "operator": {
                "kind":        "user",
                "id":          "fixture@example.invalid",
                "displayName": "Fixture Builder",
            },
        },
        "baseline": {
            "gitSha":   "deadbeefcafebabefeedface",
            "profiles": [
                { "name": "cis-l1-l2",     "version": "1.0.0" },
                { "name": "nis2-overlay",  "version": "1.0.0" },
            ],
            "overridesPresent": False,
        },
        "artefacts": artefacts,
        "findings":  [],
        "integrity": {
            "manifestSha256": "",
            "signature":      None,
        },
    }

    # Mirror Invoke-TenantScan.ps1: hash the JSON with integrity.signature=null
    # and integrity.manifestSha256='', then write the hash back.
    serialised = json.dumps(manifest, indent=2, sort_keys=False, ensure_ascii=False)
    sha = hashlib.sha256(serialised.encode("utf-8")).hexdigest()
    manifest["integrity"]["manifestSha256"] = sha
    return manifest


def write_chain_file(manifest: dict) -> None:
    """Companion sha256 chain — same shape Invoke-TenantScan.ps1 emits."""
    lines = [f"{manifest['integrity']['manifestSha256']}  manifest.json"]
    for art in manifest["artefacts"]:
        lines.append(f"{art['sha256']}  {art['path']}")
    (BUNDLE / "bundle.sha256").write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> int:
    if not BUNDLE.is_dir():
        print(f"bundle dir missing: {BUNDLE}")
        return 1
    manifest = build_manifest()
    (BUNDLE / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    write_chain_file(manifest)
    print(f"manifest.json: {len(manifest['artefacts'])} artefacts")
    print(f"manifestSha256: {manifest['integrity']['manifestSha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
