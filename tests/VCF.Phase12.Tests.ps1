# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $vcf=Join-Path $root 'scripts/VCF'
    $fixtures=Join-Path $PSScriptRoot fixtures
    function Write-Phase12Fixture {
        param($Value)
        $path=Join-Path $TestDrive 'input.json'
        ConvertTo-Json -InputObject $Value -Depth 30 | Set-Content -LiteralPath $path
        $path
    }
}
Describe 'Phase 12 documented offline VCF subsets' {
    It 'Projects lifecycle counters and preserves missing progress as unknown, without health verdicts' {
        $rows=@(& "$vcf/Get-VCFLifecycleStatus.ps1" -Path "$fixtures/vcf-lifecycle-phase12.json" -SourceVersion 'unverified-9.x-fixture')
        $rows.Count | Should -Be 2
        $rows[0].CompletedResources | Should -Be 1
        $rows[0].TotalResources | Should -Be 3
        $rows[1].UpgradeStatus | Should -Be Unknown
        $rows[1].TotalResources | Should -BeNullOrEmpty
        $rows[0].Assessment | Should -Be Unknown
        $rows[0].ContractVerifiedForProductVersion | Should -BeFalse
    }
    It 'Rejects invalid nested data, counters and duplicate identities atomically with safe errors' {
        $data=Get-Content "$fixtures/vcf-lifecycle-phase12.json" -Raw | ConvertFrom-Json
        $data.elements[1] | Add-Member upgradeStatus ([pscustomobject]@{status='IN_PROGRESS';completedResources=1;totalResources=3})
        foreach ($bad in @(-1,1.5,'2',4)) {
            $data.elements[1].upgradeStatus.completedResources=$bad
            $path=Write-Phase12Fixture $data
            $captured=[Collections.Generic.List[object]]::new()
            $rejected=$false
            try { & "$vcf/Get-VCFLifecycleStatus.ps1" -Path $path -SourceVersion fixture | ForEach-Object {$captured.Add($_)} } catch { $rejected=$true; $_.Exception.Message | Should -Not -Match 'private|sensitive-detail' }
            $rejected | Should -BeTrue
            $captured.Count | Should -Be 0
        }
        $data.elements[1].upgradeStatus=$null
        $data.elements[0].upgradeStatus=[pscustomobject]@{errors='sensitive-detail'}
        { & "$vcf/Get-VCFLifecycleStatus.ps1" -Path (Write-Phase12Fixture $data) -SourceVersion fixture } | Should -Throw '*export rejected*'
        $data.elements[0].upgradeStatus=$null
        $data.elements[1].id=$data.elements[0].id
        { & "$vcf/Get-VCFLifecycleStatus.ps1" -Path (Write-Phase12Fixture $data) -SourceVersion fixture } | Should -Throw
    }
    It 'Reads complete alert pages in order, omits owners and links, and does not guess timestamp units' {
        $pages=Get-Content "$fixtures/vcf-alerts-phase12.json" -Raw | ConvertFrom-Json
        $pages[0].alerts[0] | Add-Member ownerName 'omitted-fixture-owner'
        $pages[0].alerts[0] | Add-Member links @([pscustomobject]@{href='https://example.invalid'})
        $rows=@(& "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture @($pages[1],$pages[0])) -SourceVersion fixture)
        $rows.Count | Should -Be 2
        $rows[0].AlertId | Should -Be '00000000-0000-4000-8000-000000000001'
        $rows[0].StartTimeRaw | Should -Be 1750000000
        $rows[0].TimestampUnit | Should -Be Unknown
        ($rows | ConvertTo-Json -Depth 10) | Should -Not -Match 'ownerName|omitted-fixture-owner|example.invalid'
    }
    It 'Rejects incomplete, repeated and inconsistent alert pages and malformed identities or numeric fields' {
        $pages=Get-Content "$fixtures/vcf-alerts-phase12.json" -Raw | ConvertFrom-Json
        foreach ($badPages in @(@($pages[0]),@($pages[0],$pages[0]))) {
            { & "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $badPages) -SourceVersion fixture } | Should -Throw
        }
        $pages[1].pageInfo.totalCount=3
        { & "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $pages) -SourceVersion fixture } | Should -Throw
        $pages[1].pageInfo.totalCount=2
        $pages[1].alerts[0].alertId=$pages[0].alerts[0].alertId
        { & "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $pages) -SourceVersion fixture } | Should -Throw
        $pages[1].alerts[0].alertId='not-a-uuid'
        { & "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $pages) -SourceVersion fixture } | Should -Throw
        $pages[1].alerts[0].alertId='00000000-0000-4000-8000-000000000002'
        $pages[1].alerts[0].startTimeUTC='1750000000'
        { & "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $pages) -SourceVersion fixture } | Should -Throw
    }
    It 'Distinguishes licensing registration, subscription and missing values without entitlement inference' {
        $path="$fixtures/vcf-licensing-phase12.json"
        $row=& "$vcf/Get-VCFLicensingReport.ps1" -Path $path -SourceVersion fixture
        $row.IsRegistered | Should -BeTrue
        $row.IsSubscribed | Should -BeFalse
        $row.SubscribedState | Should -Be PARTIALLY_SUBSCRIBED
        $row.Assessment | Should -Be Unknown
        $row=& "$vcf/Get-VCFLicensingReport.ps1" -Path (Write-Phase12Fixture ([pscustomobject]@{resourceType='SYSTEM'})) -SourceVersion fixture
        $row.IsSubscribed | Should -Be Unknown
        $row.DaysRemainingToSubscribe | Should -BeNullOrEmpty
        foreach ($bad in @(@(),@([pscustomobject]@{resourceType='SYSTEM'}),[pscustomobject]@{resourceType='DOMAIN'},[pscustomobject]@{resourceType='SYSTEM';isRegistered='true'})) {
            { & "$vcf/Get-VCFLicensingReport.ps1" -Path (Write-Phase12Fixture $bad) -SourceVersion fixture } | Should -Throw
        }
    }
    It 'Handles explicit empty collections, future enum strings and absent metadata conservatively' {
        $empty=[pscustomobject]@{elements=@();pageMetadata=[pscustomobject]@{pageNumber=0;pageSize=1;totalElements=0;totalPages=0}}
        @(& "$vcf/Get-VCFLifecycleStatus.ps1" -Path (Write-Phase12Fixture $empty) -SourceVersion fixture).Count | Should -Be 0
        $empty=[pscustomobject]@{alerts=@();pageInfo=[pscustomobject]@{page=0;pageSize=1;totalCount=0}}
        @(& "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $empty) -SourceVersion fixture).Count | Should -Be 0
        $empty.pageInfo=$null
        { & "$vcf/Get-VCFOperationsAlerts.ps1" -Path (Write-Phase12Fixture $empty) -SourceVersion fixture } | Should -Throw
        $data=Get-Content "$fixtures/vcf-lifecycle-phase12.json" -Raw | ConvertFrom-Json
        $data.elements[0].upgradeStatus.status='FUTURE_STATE'
        $rows=@(& "$vcf/Get-VCFLifecycleStatus.ps1" -Path (Write-Phase12Fixture $data) -SourceVersion fixture)
        $rows[0].UpgradeStatus | Should -Be Unknown
    }
    It 'Rejects error envelopes and ambiguous JSON for every new entry point with no partial output' {
        foreach ($name in @('LifecycleStatus','OperationsAlerts','LicensingReport')) {
            $path=Write-Phase12Fixture ([pscustomobject]@{errorCode='fictional-denied';message='sensitive-detail'})
            $captured=[Collections.Generic.List[object]]::new()
            $rejected=$false
            try { & "$vcf/Get-VCF$name.ps1" -Path $path -SourceVersion fixture | ForEach-Object {$captured.Add($_)} } catch { $rejected=$true; $_.Exception.Message | Should -Not -Match 'sensitive-detail' }
            $rejected | Should -BeTrue
            $captured.Count | Should -Be 0
            '{"resourceType":"SYSTEM","ResourceType":"SYSTEM"}' | Set-Content $path
            { & "$vcf/Get-VCF$name.ps1" -Path $path -SourceVersion fixture } | Should -Throw
        }
    }
    It 'Adds source-specific HTML sections, escapes labels and withholds unallowlisted data' {
        $data=[pscustomobject]@{ScopeId='fictional';CapturedAt='2026-10-17T00:00:00Z';VCFLifecycle=@(& "$vcf/Get-VCFLifecycleStatus.ps1" -Path "$fixtures/vcf-lifecycle-phase12.json" -SourceVersion fixture);VCFOperationsAlerts=@(& "$vcf/Get-VCFOperationsAlerts.ps1" -Path "$fixtures/vcf-alerts-phase12.json" -SourceVersion fixture);VCFLicensing=@(& "$vcf/Get-VCFLicensingReport.ps1" -Path "$fixtures/vcf-licensing-phase12.json" -SourceVersion fixture)}
        $data.VCFLifecycle[0].Domain='<script>fixture</script>'
        $data.VCFLicensing[0] | Add-Member licenseKey 'omitted-fixture-value'
        $path=Join-Path $TestDrive 'vcf.html'
        $null=& "$root/scripts/Reporting/New-vSphereHealthReport.ps1" -Data $data -OutputPath $path
        $html=Get-Content $path -Raw
        $html | Should -Match 'section-VCFOperationsAlerts'
        $html | Should -Match '&lt;script&gt;fixture&lt;/script&gt;'
        $html | Should -Not -Match '<script>|omitted-fixture-value|licenseKey'
        $html | Should -Match '/suite-api/api/alerts'
        $data.VCFOperationsAlerts[0].Source='SDDC Manager'
        { & "$root/scripts/Reporting/New-vSphereHealthReport.ps1" -Data $data -OutputPath (Join-Path $TestDrive 'wrong-source.html') } | Should -Throw
        Test-Path (Join-Path $TestDrive 'wrong-source.html') | Should -BeFalse
    }
}
