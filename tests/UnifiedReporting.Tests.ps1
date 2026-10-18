# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $htmlScript=Join-Path $root 'scripts/Reporting/New-vSphereHealthReport.ps1'
    $compareScript=Join-Path $root 'scripts/Reporting/Compare-vSphereInventory.ps1'
    function Read-Fixture { param($Name) Get-Content (Join-Path $PSScriptRoot "fixtures/$Name.json") -Raw | ConvertFrom-Json }
}
Describe 'Portable offline HTML report' {
    BeforeEach { $data=Read-Fixture unified-report; $output=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.html') }
    It 'Renders all seven existing model sections and normalized dates with a successful receipt' {
        $receipt=& $htmlScript -Data $data -OutputPath $output
        $receipt.Mode | Should -Be OfflineRendering
        $receipt.RealVmwareValidated | Should -BeFalse
        $content=Get-Content $output -Raw
        foreach ($heading in @('Virtual machine inventory','VMware Tools','Snapshots and age','Datastore capacity','ESXi host alarm','NTP configuration','Machine SSL')) { $content | Should -Match $heading }
        $content | Should -Match '2026-10-01T00:00:00'
        $content | Should -Match '<td>16</td>'
        $content | Should -Match '<td>75</td>'
        $content | Should -Match 'CPU total 2; memory total GiB 4'
        $content | Should -Not -Match '<script|<iframe|<link|https?://|src='
        $content | Should -Match 'Content-Security-Policy'
    }
    It 'Distinguishes missing collections, empty collections and incomplete records' {
        $data=[pscustomobject]@{ScopeId='fixture';CapturedAt='2026-10-17T00:00:00Z';VMs=@();Tools=@([pscustomobject]@{VM='lab'})}
        & $htmlScript -Data $data -OutputPath $output | Out-Null
        $content=Get-Content $output -Raw
        $content | Should -Match 'Provided rows: 0'
        $content | Should -Match 'collection not provided'
        $content | Should -Match '<td>Unknown</td>'
    }
    It 'Marks aggregate totals unknown if a VM measurement is missing' {
        $data.VMs[0].MemoryGB=$null
        & $htmlScript -Data $data -OutputPath $output | Out-Null
        (Get-Content $output -Raw) | Should -Match 'memory total GiB Unknown'
    }
    It 'Escapes executable HTML in labels and ignores sensitive extra properties without evaluating them' {
        $attack='<img src=x onerror=alert(1)><script>alert("x")</script>&'
        $data.VMs[0].VM=$attack
        $data | Add-Member Password 'fixture-sensitive-extra'
        $data.VMs[0] | Add-Member -MemberType ScriptProperty -Name Token -Value { throw 'Extra getter must not execute' }
        & $htmlScript -Data $data -OutputPath $output | Out-Null
        $content=Get-Content $output -Raw
        $content | Should -Match '&lt;img'
        $content | Should -Not -Match '<img|<script|fixture-sensitive-extra|Extra getter'
    }
    It 'Rejects credential objects in allowed columns rather than serializing them' {
        $secret=ConvertTo-SecureString 'fixture-not-real' -AsPlainText -Force
        $data.VMs[0].VM=[pscredential]::new('fixture-user',$secret)
        { & $htmlScript -Data $data -OutputPath $output } | Should -Throw '*HTML report generation failed*'
        Test-Path $output | Should -BeFalse
    }
    It 'Rejects duplicate stable identities without creating an output file' {
        $data.VMs+=,$data.VMs[0]
        { & $htmlScript -Data $data -OutputPath $output } | Should -Throw
        Test-Path $output | Should -BeFalse
    }
    It 'Rejects invalid numeric input and incoherent capacity' {
        foreach ($value in @(-1,[double]::NaN,[double]::PositiveInfinity,'2',$true)) {
            $data.VMs[0].NumCpu=$value
            { & $htmlScript -Data $data -OutputPath $output } | Should -Throw
            Test-Path $output | Should -BeFalse
        }
        $data=Read-Fixture unified-report;$data.Datastores[0].FreeGiB=101
        { & $htmlScript -Data $data -OutputPath $output } | Should -Throw
    }
    It 'Leaves inaccessible capacity and missing certificate dates unknown instead of trusting supplied summaries' {
        $data.Datastores[0].Accessible=$false
        $data.Certificates[0].PSObject.Properties.Remove('NotAfterUtc')
        $data.Certificates[0] | Add-Member TrustVerified $true
        & $htmlScript -Data $data -OutputPath $output | Out-Null
        $content=Get-Content $output -Raw
        $content | Should -Not -Match 'WithinDateWindow|<td>75</td>'
        $content | Should -Match '<td>False</td>'
    }
    It 'Rejects offset-free and future snapshot dates without a partial file' {
        foreach ($date in @('2026-10-01T00:00:00','2027-01-01T00:00:00Z')) {
            $data.Snapshots[0].Created=$date
            { & $htmlScript -Data $data -OutputPath $output } | Should -Throw
            Test-Path $output | Should -BeFalse
        }
    }
    It 'Never overwrites existing files and returns no receipt on a write failure' {
        [IO.File]::WriteAllText($output,'original')
        { & $htmlScript -Data $data -OutputPath $output } | Should -Throw
        [IO.File]::ReadAllText($output) | Should -Be original
        $missing=Join-Path $TestDrive 'absent-parent/report.html'
        $captured=@();$failure=$null
        try { $captured=@(& $htmlScript -Data $data -OutputPath $missing) } catch { $failure=$_ }
        $failure.FullyQualifiedErrorId | Should -Match Toolkit.HealthReportFailed
        $failure.Exception.Message | Should -Not -Match 'absent-parent'
        $captured.Count | Should -Be 0
        Test-Path $missing | Should -BeFalse
    }
    It 'Supports WhatIf and refuses symbolic-link output parents' {
        @(& $htmlScript -Data $data -OutputPath $output -WhatIf).Count | Should -Be 0
        Test-Path $output | Should -BeFalse
        $link=Join-Path $TestDrive ('linked-'+[guid]::NewGuid())
        New-Item -ItemType SymbolicLink -Path $link -Target $TestDrive | Out-Null
        { & $htmlScript -Data $data -OutputPath (Join-Path $link 'report.html') } | Should -Throw
    }
}
Describe 'Scoped inventory comparison' {
    BeforeEach { $before=Read-Fixture inventory-before;$after=Read-Fixture inventory-after }
    It 'Detects stable-ID additions, removals, CPU, memory and power changes despite renamed VMs' {
        $rows=@(& $compareScript -Baseline $before -Current $after)
        $rows.Count | Should -Be 5
        @($rows | Where-Object Change -eq Added).Count | Should -Be 1
        @($rows | Where-Object Change -eq Removed).Count | Should -Be 1
        @($rows | Where-Object Change -eq Changed).Count | Should -Be 3
    }
    It 'Handles explicit empty arrays without inferring a missing collection is empty' {
        $before.VMs=@();$after.VMs=@()
        @(& $compareScript -Baseline $before -Current $after).Count | Should -Be 0
        $after.PSObject.Properties.Remove('VMs')
        { & $compareScript -Baseline $before -Current $after } | Should -Throw
    }
    It 'Reports missing measurements and unrecognized power states as not comparable' {
        $after.VMs=@($after.VMs[0]);$before.VMs=@($before.VMs[0])
        $after.VMs[0].PSObject.Properties.Remove('NumCpu')
        $after.VMs[0].MemoryGB=$before.VMs[0].MemoryGB
        $after.VMs[0].PowerState='future-state'
        $rows=@(& $compareScript -Baseline $before -Current $after)
        $rows.Count | Should -Be 2
        @($rows | Where-Object Change -eq NotComparable).Count | Should -Be 2
    }
    It 'Does not infer additions or removals from incomplete opposite collections' {
        $before.Completeness='Partial';$after.Completeness='Unknown'
        $rows=@(& $compareScript -Baseline $before -Current $after)
        @($rows | Where-Object Change -in @('Added','Removed')).Count | Should -Be 0
        @($rows | Where-Object Change -eq PresenceUnknown).Count | Should -Be 2
    }
    It 'Rejects incompatible endpoint, identity and selection namespaces' {
        foreach ($field in @('ScopeId','IdentityKind','SelectionId')) {
            $after=Read-Fixture inventory-after;$after.$field='different'
            { & $compareScript -Baseline $before -Current $after } | Should -Throw
        }
    }
    It 'Compares UTC-equivalent captures consistently and rejects reversed or ambiguous timestamps' {
        $after=Read-Fixture inventory-before
        $after.CapturedAt='2026-10-16T00:00:00Z'
        @(& $compareScript -Baseline $before -Current $after).Count | Should -Be 0
        foreach ($time in @('2026-10-15T00:00:00Z','2026-10-17T00:00:00')) {
            $after.CapturedAt=$time
            { & $compareScript -Baseline $before -Current $after } | Should -Throw
        }
    }
    It 'Rejects duplicates, missing IDs and invalid numeric values without partial results' {
        foreach ($fault in @('duplicate','missing','number')) {
            $after=Read-Fixture inventory-after
            switch ($fault) {
                duplicate { $after.VMs+=,$after.VMs[0] }
                missing { $after.VMs[1].PSObject.Properties.Remove('VMId') }
                number { $after.VMs[1].MemoryGB=[double]::NaN }
            }
            $captured=[Collections.Generic.List[object]]::new();$failure=$null
            try { & $compareScript -Baseline $before -Current $after | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
            $failure | Should -Not -BeNullOrEmpty
            $captured.Count | Should -Be 0
        }
    }
    It 'Creates safe CSV while returning exact object labels and preserving existing files' {
        $after.VMs[0].VM='=fixture-formula'
        $csv=Join-Path $TestDrive 'changes.csv'
        $rows=@(& $compareScript -Baseline $before -Current $after -CsvPath $csv)
        $rows[0].VM | Should -Be '=fixture-formula'
        $fileRows=@(Import-Csv $csv)
        $fileRows[0].VM | Should -Be "'=fixture-formula"
        $original=[IO.File]::ReadAllText($csv)
        { & $compareScript -Baseline $before -Current $after -CsvPath $csv } | Should -Throw
        [IO.File]::ReadAllText($csv) | Should -Be $original
    }
    It 'Writes CSV headers for no changes and suppresses all results on CSV failure' {
        $after=Read-Fixture inventory-before
        $csv=Join-Path $TestDrive 'empty.csv'
        @(& $compareScript -Baseline $before -Current $after -CsvPath $csv).Count | Should -Be 0
        (Get-Content $csv -First 1) | Should -Match ScopeId
        $after=Read-Fixture inventory-after
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & $compareScript -Baseline $before -Current $after -CsvPath (Join-Path $TestDrive 'missing/out.csv') | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $captured.Count | Should -Be 0
    }
    It 'Uses the opt-in identity projection without changing existing inventory output' {
        function Get-VM { [CmdletBinding()] param($Server,$Name) }
        Mock Get-VM { [pscustomobject]@{Id='VirtualMachine-fixture';Name='lab';PowerState='PoweredOn';NumCpu=2;MemoryGB=4;VMHost='esxi.example.invalid'} }
        $serverObject=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}
        $default=& "$root/scripts/Reporting/Get-VMInventory.ps1" -Server $serverObject
        $default.PSObject.Properties.Name | Should -Not -Contain VMId
        $identified=& "$root/scripts/Reporting/Get-VMInventory.ps1" -Server $serverObject -IncludeIdentity
        $identified.VMId | Should -Be VirtualMachine-fixture
    }
}
