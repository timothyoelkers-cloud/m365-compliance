<#
.SYNOPSIS
    Pester end-to-end test — runs Resolve-Baseline.ps1 + Compare-TenantState.ps1
    against the synthetic-tenant-001 fixture and asserts the produced findings
    match tests/expected-findings.json (the same ground truth used by the
    Python verifier in tests/verify_fixture.py).

.DESCRIPTION
    Two implementations of the diff logic agreeing on the same fixture is the
    strongest pre-tenant validation we can do:
        - Python verifier (verify_fixture.py) → expected-findings.json
        - PowerShell engine (Resolve-Baseline.ps1 + Compare-TenantState.ps1)
          → actual findings

    Drift between them = a real bug in one engine. Either fix the engine or
    fix the fixture, never just rubber-stamp expected to match the broken side.

    Run:
        Invoke-Pester -Path tests/end-to-end.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:Repo     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Fixture  = Join-Path $Repo 'tests/fixtures/synthetic-tenant-001'
    $script:Bundle   = Join-Path $Fixture 'scan-bundle'
    $script:Tenant   = Join-Path $Fixture 'tenant.yaml'
    $script:Resolve  = Join-Path $Repo 'scripts/common/Resolve-Baseline.ps1'
    $script:Compare  = Join-Path $Repo 'scripts/common/Compare-TenantState.ps1'
    $script:Rules    = Join-Path $Repo 'scripts/common/diff-rules.yaml'
    $script:Expected = Join-Path $Repo 'tests/expected-findings.json'

    $script:Out      = Join-Path $env:TEMP "m365c-fixture-$(Get-Random)"
    New-Item -ItemType Directory -Path $Out -Force | Out-Null

    $script:ResolvedPath = Join-Path $Out 'resolved.json'
    $script:FindingsPath = Join-Path $Out 'findings.json'
}

AfterAll {
    if (Test-Path $script:Out) { Remove-Item $script:Out -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Synthetic-tenant-001 end-to-end' {

    Context 'Layered baseline resolution' {

        It 'resolves the baseline against the synthetic tenant.yaml' {
            { & $script:Resolve `
                -TenantConfigPath $script:Tenant `
                -BaselinesRoot   (Join-Path $script:Repo 'baselines') `
                -OutputPath      $script:ResolvedPath `
                | Out-Null } | Should -Not -Throw

            Test-Path $script:ResolvedPath | Should -BeTrue
        }

        It 'applies the expected layer chain (cis-l1 -> cis-l1-l2 -> nis2-overlay)' {
            $resolved = Get-Content -Raw $script:ResolvedPath | ConvertFrom-Json
            $resolved.layersApplied | Should -Contain 'global/defaults'
            $resolved.layersApplied | Should -Contain 'global/break-glass'
            $resolved.layersApplied | Should -Contain 'profile/cis-l1@~1.0'
            $resolved.layersApplied | Should -Contain 'profile/cis-l1-l2@~1.0'
            $resolved.layersApplied | Should -Contain 'profile/nis2-overlay@~1.0'
        }

        It 'merges sharepoint.sharing_capability to ExistingExternalUserSharingOnly (cis-l1-l2 + nis2 tighter than cis-l1)' {
            $resolved = Get-Content -Raw $script:ResolvedPath | ConvertFrom-Json
            $resolved.target.sharepoint.sharing_capability | Should -Be 'ExistingExternalUserSharingOnly'
        }

        It 'honours nis2-overlay replaces directive (removes cis-l1-ca-002-mfa-all-users)' {
            $resolved = Get-Content -Raw $script:ResolvedPath | ConvertFrom-Json
            $ids = @($resolved.target.entra.conditional_access_policies | ForEach-Object { $_.id })
            $ids | Should -Not -Contain 'cis-l1-ca-002-mfa-all-users'
            $ids | Should -Contain     'nis2-ca-030-phishing-resistant-all'
        }
    }

    Context 'Diff engine vs synthetic scan bundle' {

        It 'runs Compare-TenantState.ps1 against the fixture bundle' {
            { & $script:Compare `
                -ResolvedBaselinePath $script:ResolvedPath `
                -BundlePath           $script:Bundle `
                -RulesPath            $script:Rules `
                -OutputPath           $script:FindingsPath `
                | Out-Null } | Should -Not -Throw

            Test-Path $script:FindingsPath | Should -BeTrue
        }

        It 'produces findings matching expected-findings.json' {
            $actual   = Get-Content -Raw $script:FindingsPath | ConvertFrom-Json
            $expected = Get-Content -Raw $script:Expected     | ConvertFrom-Json

            # Summary parity
            $actual.summary.total    | Should -Be $expected.summary.total
            $actual.summary.critical | Should -Be $expected.summary.critical
            $actual.summary.high     | Should -Be $expected.summary.high
            $actual.summary.medium   | Should -Be $expected.summary.medium
            $actual.summary.low      | Should -Be $expected.summary.low
            $actual.summary.info     | Should -Be $expected.summary.info

            # Finding-id parity (set equality)
            $actualIds   = @($actual.findings   | ForEach-Object { $_.id }) | Sort-Object
            $expectedIds = @($expected.findings | ForEach-Object { $_.id }) | Sort-Object
            ($actualIds -join ',') | Should -Be ($expectedIds -join ',')

            # Per-finding severity parity
            foreach ($eF in $expected.findings) {
                $aF = $actual.findings | Where-Object id -eq $eF.id | Select-Object -First 1
                $aF | Should -Not -BeNullOrEmpty
                $aF.severity     | Should -Be $eF.severity
                $aF.workload     | Should -Be $eF.workload
                $aF.actionTaken  | Should -Be $eF.actionTaken
            }
        }

        It 'flags the expected high-severity findings' {
            $actual = Get-Content -Raw $script:FindingsPath | ConvertFrom-Json
            $highs  = @($actual.findings | Where-Object severity -eq 'high' | ForEach-Object { $_.id })

            $highs | Should -Contain 'entra.weak-auth-voice-disabled'
            $highs | Should -Contain 'exchange.auto-forwarding-off'
            $highs | Should -Contain 'exchange.mailbox-audit-on'
            $highs | Should -Contain 'sharepoint.sharing-capability'
        }

        It 'defers powerbi rules with no scan artefact' {
            $actual = Get-Content -Raw $script:FindingsPath | ConvertFrom-Json
            $deferred = @($actual.findings | Where-Object actionTaken -eq 'deferred')
            $deferred.Count | Should -BeGreaterOrEqual 2
            ($deferred | ForEach-Object workload) | Should -Contain 'powerbi'
        }
    }
}
