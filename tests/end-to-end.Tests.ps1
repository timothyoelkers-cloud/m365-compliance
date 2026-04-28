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
    $script:Repo       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Fixture    = Join-Path $Repo 'tests/fixtures/synthetic-tenant-001'
    $script:Bundle     = Join-Path $Fixture 'scan-bundle'
    $script:Tenant     = Join-Path $Fixture 'tenant.yaml'
    $script:Resolve    = Join-Path $Repo 'scripts/common/Resolve-Baseline.ps1'
    $script:Compare    = Join-Path $Repo 'scripts/common/Compare-TenantState.ps1'
    $script:Rules      = Join-Path $Repo 'scripts/common/diff-rules.yaml'
    $script:Expected   = Join-Path $Repo 'tests/expected-findings.json'
    $script:CaApply    = Join-Path $Repo 'scripts/apply/Set-ConditionalAccess.ps1'
    $script:CaExpected = Join-Path $Repo 'tests/expected-ca-plan.json'

    $script:TenantId = '00000000-0000-0000-0000-aaaaaaaaaaaa'
    $script:Out      = Join-Path $env:TEMP "m365c-fixture-$(Get-Random)"
    New-Item -ItemType Directory -Path $Out -Force | Out-Null

    $script:ResolvedPath = Join-Path $Out 'resolved.json'
    $script:FindingsPath = Join-Path $Out 'findings.json'
    $script:CaOutDir     = Join-Path $Out 'ca-apply'
    New-Item -ItemType Directory -Path $CaOutDir -Force | Out-Null
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

    Context 'Framework report generator' {

        BeforeAll {
            $script:ReportTool = Join-Path $script:Repo 'scripts/report/New-FrameworkReport.ps1'
            $script:ReportDir  = Join-Path $script:Out 'reports'
            New-Item -ItemType Directory -Path $script:ReportDir -Force | Out-Null
        }

        It 'generates a CIS M365 report against the fixture findings' {
            $result = & $script:ReportTool `
                -Framework        cis-m365 `
                -FindingsPath     $script:FindingsPath `
                -OutputPath       (Join-Path $script:ReportDir 'cis-m365.md') `
                -ResolvedBaselinePath $script:ResolvedPath `
                -TenantDisplayName 'Synthetic Test Tenant (fixture)'
            $result.framework        | Should -Be 'cis-m365'
            $result.refsTotal        | Should -BeGreaterThan 0
            (Test-Path $result.output) | Should -BeTrue

            $content = Get-Content -Raw $result.output
            $content | Should -Match '## Headline'
            $content | Should -Match '## Coverage matrix'
            $content | Should -Match '## Findings scoped to'
            $content | Should -Match '## Gaps'
        }

        It 'generates a DORA report and surfaces drift on Art 9(2)(c)' {
            $result = & $script:ReportTool `
                -Framework        dora `
                -FindingsPath     $script:FindingsPath `
                -OutputPath       (Join-Path $script:ReportDir 'dora.md')
            $result.framework | Should -Be 'dora'

            $content = Get-Content -Raw $result.output
            $content | Should -Match 'DORA'
            $content | Should -Match 'Art 9\(2\)\(c\).+drift'
        }

        It 'refuses unknown framework' {
            { & $script:ReportTool -Framework iso27001 -FindingsPath $script:FindingsPath -OutputPath (Join-Path $script:ReportDir 'iso.md') } | Should -Throw
        }

        It 'returns headline counts that sum to refsTotal' {
            $result = & $script:ReportTool `
                -Framework    nis2 `
                -FindingsPath $script:FindingsPath `
                -OutputPath   (Join-Path $script:ReportDir 'nis2.md')
            ($result.refsCovered + $result.refsDrift + $result.refsPartialOnly + $result.refsUncovered) | Should -Be $result.refsTotal
        }
    }

    Context 'Conditional Access apply — plan / dry-run' {

        It 'runs Set-ConditionalAccess.ps1 in plan mode without throwing' {
            { & $script:CaApply `
                -ResolvedBaselinePath $script:ResolvedPath `
                -ScanBundlePath       $script:Bundle `
                -TenantId             $script:TenantId `
                -OutputDir            $script:CaOutDir `
                -Mode                 plan `
                | Out-Null } | Should -Not -Throw

            Test-Path (Join-Path $script:CaOutDir 'plan.json') | Should -BeTrue
        }

        It 'produces a CA plan whose summary matches expected-ca-plan.json' {
            $actual   = Get-Content -Raw (Join-Path $script:CaOutDir 'plan.json') | ConvertFrom-Json
            $expected = Get-Content -Raw $script:CaExpected | ConvertFrom-Json

            $actual.workload  | Should -Be 'conditional-access'
            $actual.mode      | Should -Be 'plan'
            $actual.tenantId  | Should -Be $script:TenantId

            $actual.summary.create    | Should -Be $expected.summary.create
            $actual.summary.patch     | Should -Be $expected.summary.patch
            $actual.summary.unchanged | Should -Be $expected.summary.unchanged
            $actual.summary.remove    | Should -Be $expected.summary.remove
        }

        It 'classifies untracked tenant policies (cis-l1-ca-002 was replaced by nis2-ca-030)' {
            $actual = Get-Content -Raw (Join-Path $script:CaOutDir 'plan.json') | ConvertFrom-Json
            $untracked = @($actual.actions | Where-Object action -eq 'untracked')
            $untracked.Count | Should -BeGreaterOrEqual 1
            ($untracked | ForEach-Object displayName) | Should -Contain 'CIS L1 — Require MFA for all users'
        }

        It 'classifies cis-l1-ca-001-block-legacy-auth as unchanged (normaliser handles encoding mismatch)' {
            $actual = Get-Content -Raw (Join-Path $script:CaOutDir 'plan.json') | ConvertFrom-Json
            $row = $actual.actions | Where-Object { $_.baselineId -eq 'cis-l1-ca-001-block-legacy-auth' } | Select-Object -First 1
            $row | Should -Not -BeNullOrEmpty
            $row.action | Should -Be 'unchanged'
        }

        It 'refuses apply mode without -ApprovalRef' {
            { & $script:CaApply `
                -ResolvedBaselinePath $script:ResolvedPath `
                -ScanBundlePath       $script:Bundle `
                -TenantId             $script:TenantId `
                -OutputDir            $script:CaOutDir `
                -Mode                 apply `
                | Out-Null } | Should -Throw -ExpectedMessage '*ApprovalRef*'
        }

        It 'produces empty blockedBy when baseline + fixture invariants hold' {
            $actual = Get-Content -Raw (Join-Path $script:CaOutDir 'plan.json') | ConvertFrom-Json
            $actual.blockedBy.Count | Should -Be 0
        }
    }
}
