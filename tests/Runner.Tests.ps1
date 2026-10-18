# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $runner=Join-Path $root 'scripts/Invoke-VMwareToolkit.ps1'
    Import-Module (Join-Path $root 'scripts/Private/Runner.Support.psm1') -Force
    $moduleName='Runner.Support'
    function Read-RunnerFixture { Get-Content (Join-Path $PSScriptRoot 'fixtures/runner-results.json') -Raw | ConvertFrom-Json }
}
Describe 'Central read-only runner' {
    BeforeEach {
        $fakeConnection=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}
        $arguments=@{Server=$fakeConnection;EndpointType='vCenter';ScopeId='fixture-endpoint';AsOf=[datetimeoffset]'2026-10-17T00:00:00Z'}
        $fixture=Read-RunnerFixture
        # This seam replaces only fixed existing read scripts; orchestration/status/HTML stay real.
        Mock Invoke-ToolkitReadCheck -ModuleName $moduleName {
            $fixture.PSObject.Properties[$Check].Value
        }
    }
    It 'Runs the default Inventory profile with one explicit connection and no unselected checks' {
        $result=& $runner @arguments
        $result.Outcome | Should -Be Completed
        $result.ExecutionCompleted | Should -BeTrue
        ($result.Data.VMs -is [array]) | Should -BeTrue
        $selected=@($result.Checks | Where-Object Requested)
        ($selected.Check -join ',') | Should -Be 'VMInventory,Tools,Datastores'
        @($result.Checks | Where-Object Status -eq NotRun).Count | Should -Be 11
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 3 -Exactly -ParameterFilter { $Arguments.Server -eq $fakeConnection -and $Arguments.ErrorAction -eq 'Stop' }
    }
    It 'Selects Operations and shares snapshot and time sources' {
        $result=& $runner @arguments -Profile Operations
        $result.Outcome | Should -Be Completed
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'Snapshots' }
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'Time' }
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 0 -Exactly -ParameterFilter { $Check -in @('Ntp','OldSnapshots') }
        $result.Data.Snapshots.Count | Should -Be 1
        $result.Data.Ntp[0].NtpServers[0] | Should -Be ntp.example.invalid
    }
    It 'Selects Security and merges the advanced-setting/syslog query without duplicating it' {
        $result=& $runner @arguments -Profile Security
        $result.Outcome | Should -Be Completed
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'AdvancedSettings' -and $Arguments.SettingName.Count -eq 5 }
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 0 -ParameterFilter { $Check -eq 'Syslog' }
        $result.Data.HostSyslog.Count | Should -Be 5
        $result.Data.HostAdvancedSettings.Count | Should -Be 5
    }
    It 'Executes All using the fixed fourteen-check catalog and eleven source scripts' {
        $result=& $runner @arguments -Profile All
        @($result.Checks | Where-Object Requested).Count | Should -Be 14
        $result.SourceExecutions | Should -Be 11
        $result.Outcome | Should -Be Completed
        ($result.Checks.Check -join ',') | Should -Not -Match 'Set-|DnsServers'
    }
    It 'Forwards explicit filters and respects the certificate scope parameter sets' {
        & $runner @arguments -Checks VMInventory,Firewall,Certificates -VMName 'lab-*' -VMHostName 'esxi-*' -RuleName 'fixture-*' -CertificateScope VCenter | Out-Null
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'VMInventory' -and $Arguments.Name -eq 'lab-*' -and $Arguments.IncludeIdentity }
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'Firewall' -and $Arguments.Name -eq 'esxi-*' -and $Arguments.RuleName -eq 'fixture-*' }
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'Certificates' -and $Arguments.Scope -eq 'VCenter' -and -not $Arguments.ContainsKey('Name') }
    }
    It 'Derives old snapshots with the existing shared pure projection and records dependencies' {
        $result=& $runner @arguments -Checks OldSnapshots
        $result.Outcome | Should -Be Completed
        $result.Data.Snapshots[0].AgeDays | Should -Be 16
        ($result.Checks | Where-Object Check -eq Snapshots).Reason | Should -Be Dependency
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly -ParameterFilter { $Check -eq 'Snapshots' -and $Arguments.IncludeIdentity }
    }
    It 'Distinguishes empty execution, missing evidence and unselected checks' {
        $fixture.VMInventory=@();$fixture.Tools[0].PSObject.Properties.Remove('ToolsRunningStatus')
        $result=& $runner @arguments -Checks VMInventory,Tools
        ($result.Checks | Where-Object Check -eq VMInventory).Status | Should -Be Empty
        ($result.Checks | Where-Object Check -eq Tools).Status | Should -Be Incomplete
        ($result.Checks | Where-Object Check -eq Firewall).Status | Should -Be NotRun
        $result.Outcome | Should -Be Incomplete
        @($result.Data.VMs).Count | Should -Be 0
        $result.Data.Completeness | Should -Be Unknown
    }
    It 'Stops after a middle permission failure without labeling partial execution successful' {
        Mock Invoke-ToolkitReadCheck -ModuleName $moduleName {
            if ($Check -eq 'Tools') { throw [UnauthorizedAccessException]::new('fixture-private-denial') }
            $fixture.PSObject.Properties[$Check].Value
        }
        $result=& $runner @arguments
        $result.Outcome | Should -Be PartialFailure
        $result.ExecutionCompleted | Should -BeFalse
        ($result.Checks | Where-Object Check -eq Tools).Status | Should -Be Failed
        ($result.Checks | Where-Object Check -eq Datastores).Reason | Should -Be StoppedAfterFailure
        $result.Data.Tools | Should -BeNullOrEmpty
        ($result.Checks | ConvertTo-Json) | Should -Not -Match 'fixture-private-denial|UnauthorizedAccessException'
    }
    It 'Continues independent work only when explicitly requested after a lost session' {
        Mock Invoke-ToolkitReadCheck -ModuleName $moduleName {
            if ($Check -eq 'Tools') { throw [IO.IOException]::new('fixture-private-session') }
            $fixture.PSObject.Properties[$Check].Value
        }
        $result=& $runner @arguments -ContinueOnError
        $result.Outcome | Should -Be PartialFailure
        ($result.Checks | Where-Object Check -eq Datastores).Status | Should -Be Completed
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 3 -Exactly
    }
    It 'Retains outputs for DNS and old-snapshot checks that do not both have dedicated HTML sections' {
        $result=& $runner @arguments -Checks Dns,Snapshots,OldSnapshots
        $result.Results.Dns[0].DnsAddress[0] | Should -Be '192.0.2.53'
        $result.Results.OldSnapshots[0].AgeDays | Should -Be 16
        ($result.Results.Dns -is [array]) | Should -BeTrue
    }
    It 'Rejects malformed connection and selection arguments before any read' {
        $fakeConnection.IsConnected=$false
        { & $runner @arguments } | Should -Throw '*connected VIServer*'
        $fakeConnection.IsConnected=$true
        { & $runner @arguments -Checks Tools,Tools } | Should -Throw
        { & $runner @arguments -Checks '../Network/Set-VMHostDnsServers.ps1' } | Should -Throw
        { & $runner @arguments -Checks Tools -Profile All } | Should -Throw
        { & $runner @arguments -MaxRowsPerCheck 0 } | Should -Throw
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 0
    }
    It 'Honors direct-ESXi certificate blocking as NotRun and never claims a complete All run' {
        $arguments.EndpointType='ESXi'
        $result=& $runner @arguments -Checks Certificates
        $result.Outcome | Should -Be Incomplete
        ($result.Checks | Where-Object Check -eq Certificates).Reason | Should -Be UnsupportedEndpoint
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 0
    }
    It 'Enforces row retention budgets and discards an over-budget check' {
        $fixture.VMInventory+=,$fixture.VMInventory[0]
        $result=& $runner @arguments -Checks VMInventory -MaxRowsPerCheck 1
        $result.Outcome | Should -Be Failed
        ($result.Checks | Where-Object Check -eq VMInventory).Reason | Should -Be RowLimitExceeded
        $result.Data.VMs | Should -BeNullOrEmpty
        $fixture=Read-RunnerFixture
        $result=& $runner @arguments -MaxTotalRows 1
        $result.Outcome | Should -Be PartialFailure
        $result.RetainedRows | Should -Be 1
    }
    It 'Rejects duplicate identities returned by a source without publishing that dataset' {
        $fixture.Tools+=,$fixture.Tools[0]
        $result=& $runner @arguments -Checks Tools
        $result.Outcome | Should -Be Failed
        $result.Data.Tools | Should -BeNullOrEmpty
    }
    It 'Rejects credential objects or nonfinite values in source output before returning that dataset' {
        $fixture.VMInventory[0].MemoryGB=[double]::NaN
        $result=& $runner @arguments -Checks VMInventory
        $result.Outcome | Should -Be Failed
        $result.Results.VMInventory | Should -BeNullOrEmpty
        $fixture=Read-RunnerFixture
        $fixture.VMInventory[0] | Add-Member Credential ([pscredential]::new('fixture-user',(ConvertTo-SecureString 'fixture-not-real' -AsPlainText -Force)))
        $result=& $runner @arguments -Checks VMInventory
        $result.Outcome | Should -Be Failed
        $result.Results.VMInventory | Should -BeNullOrEmpty
    }
    It 'Generates real portable HTML containing execution status and partial outcomes' {
        Mock Invoke-ToolkitReadCheck -ModuleName $moduleName {
            if ($Check -eq 'Tools') { throw 'fixture-private-failure' }
            $fixture.PSObject.Properties[$Check].Value
        }
        $file=Join-Path $TestDrive 'runner.html'
        $result=& $runner @arguments -HtmlPath $file
        $result.Outcome | Should -Be PartialFailure
        $result.Report.Status | Should -Be Completed
        $html=Get-Content $file -Raw
        $html | Should -Match 'Toolkit execution outcome: PartialFailure|Toolkit execution status|StoppedAfterFailure'
        $html | Should -Match '<td>Failed</td>'
        $html | Should -Not -Match 'fixture-private-failure|<script'
    }
    It 'Preserves output files and degrades the overall outcome on report-write failure' {
        $file=Join-Path $TestDrive 'existing.html';[IO.File]::WriteAllText($file,'original')
        $result=& $runner @arguments -Checks VMInventory -HtmlPath $file
        $result.Report.Status | Should -Be Failed
        $result.Outcome | Should -Be PartialFailure
        [IO.File]::ReadAllText($file) | Should -Be original
        ($result.Report | ConvertTo-Json) | Should -Not -Match 'existing.html'
    }
    It 'Treats WhatIf HTML as not generated while permitting the requested read-only work' {
        $file=Join-Path $TestDrive 'whatif.html'
        $result=& $runner @arguments -Checks VMInventory -HtmlPath $file -WhatIf
        $result.Report.Status | Should -Be NotRun
        $result.Outcome | Should -Be Incomplete
        Test-Path $file | Should -BeFalse
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly
    }
    It 'Renders every selected model for All without changing the existing HTML contracts' {
        $file=Join-Path $TestDrive 'all.html'
        $result=& $runner @arguments -Profile All -HtmlPath $file
        $result.Outcome | Should -Be Completed
        $result.Report.Status | Should -Be Completed
        ([regex]::Matches((Get-Content $file -Raw),'<section(?:\s[^>]*)?>')).Count | Should -Be 13
        $result.Data.Snapshots[0].Created | Should -BeOfType ([datetimeoffset])
    }
    It 'Records shared dependency failures without retrying or mislabeling their execution' {
        Mock Invoke-ToolkitReadCheck -ModuleName $moduleName { throw [IO.IOException]::new('fixture-shared-failure') }
        $result=& $runner @arguments -Checks Ntp,Time -ContinueOnError
        $result.Outcome | Should -Be Failed
        ($result.Checks | Where-Object Check -eq Time).Status | Should -Be Failed
        Should -Invoke Invoke-ToolkitReadCheck -ModuleName $moduleName -Times 1 -Exactly
    }
    It 'Uses only trusted fixed paths and never exposes a write check or script-path parameter' {
        $metadata=Get-Command $runner
        $metadata.Parameters.Keys | Should -Not -Contain ScriptPath
        $source=Get-Content (Join-Path $root 'scripts/Private/Runner.Support.psm1') -Raw
        $source | Should -Not -Match 'Set-VMHostDnsServers|Invoke-Expression|Connect-VIServer|SkipCertificateCheck'
        $source | Should -Match 'ReparsePoint|Toolkit.RowLimitExceeded'
    }
}
Describe 'Phase 11 offline discovery and presentation' {
    It 'Lists profiles and checks without a connection and keeps profile membership within the public allowlist' {
        $profiles=@(& $runner -ListProfiles)
        $checks=@(& $runner -ListChecks)
        $profiles.Count | Should -Be 4
        $checks.Count | Should -Be 14
        $allowed=(Get-Command $runner).Parameters.Checks.Attributes.ValidValues
        foreach ($profileInfo in $profiles) {
            foreach ($checkName in $profileInfo.Checks) { $checkName | Should -BeIn $allowed }
        }
        ($checks.Check -join ',') | Should -Not -Match 'Set-'
        { & $runner -ListProfiles -Checks Tools } | Should -Throw
        (Get-Help $runner -Full | Out-String) | Should -Match 'ListProfiles'
    }
    It 'Preserves legacy statuses while distinguishing empty success and unknown data in structured output and HTML' {
        Mock Invoke-ToolkitReadCheck -ModuleName $moduleName {
            if ($Check -eq 'VMInventory') { return }
            [pscustomobject]@{VMId='vm-fictional';VM='fixture';ToolsVersion=$null;ToolsVersionStatus='Unknown';ToolsRunningStatus='Unknown'}
        }
        $result=& $runner -Server ([pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}) -EndpointType vCenter -ScopeId fixture -Checks VMInventory,Tools -HtmlPath (Join-Path $TestDrive 'ux.html')
        $result.State | Should -Be Unknown
        ($result.Checks | Where-Object Check -eq VMInventory).Status | Should -Be Empty
        ($result.Checks | Where-Object Check -eq VMInventory).State | Should -Be Success
        ($result.Checks | Where-Object Check -eq VMInventory).Message | Should -Match 'visibility remains unverified'
        ($result.Checks | Where-Object Check -eq Tools).State | Should -Be Unknown
        $html=Get-Content $result.Report.Path -Raw
        $html | Should -Match 'Executive summary'
        $html | Should -Match 'href="#section-VMs"'
        $html | Should -Match 'id="section-VMs"'
        $html | Should -Match 'tabindex="0"'
        $html | Should -Match '@media\(max-width:600px\)'
        $html | Should -Not -Match '<script|<iframe|<link|https?://|src='
    }
}
