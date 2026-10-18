# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    function Get-View { [CmdletBinding()] param($Server,$ViewType,$Property) throw 'Unexpected provider call' }
    function Get-Datastore { [CmdletBinding()] param($Server,$Name) throw 'Unexpected provider call' }
    function Get-VMHost { [CmdletBinding()] param($Server,$Name) throw 'Unexpected provider call' }
    function Get-VMHostNtpServer { [CmdletBinding()] param($Server,$VMHost) throw 'Unexpected provider call' }
    function Get-VM { [CmdletBinding()] param($Server,$Name) throw 'Unexpected provider call' }
    function Get-Snapshot { [CmdletBinding()] param($Server,$VM) throw 'Unexpected provider call' }
    function Get-VIMachineCertificate { [CmdletBinding()] param($Server,$VMHost,[switch]$VCenterOnly) throw 'Unexpected provider call' }
    function Initialize-Phase7Fixture {
        Get-Content (Join-Path $PSScriptRoot 'fixtures/phase7-projections.json') -Raw | ConvertFrom-Json
    }
}
Describe 'New read-only tool <Tool>' -ForEach @(
    @{Tool='Reporting/Get-VMwareToolsStatus';Primary='Get-View';Kind='tools';Expected=2},
    @{Tool='Health/Get-VMHostHealth';Primary='Get-View';Kind='health';Expected=2},
    @{Tool='Storage/Get-DatastoreCapacity';Primary='Get-Datastore';Kind='store';Expected=2},
    @{Tool='Reporting/Get-OldSnapshots';Primary='Get-VM';Kind='snapshot';Expected=1},
    @{Tool='Network/Get-VMHostNtpConfiguration';Primary='Get-VMHost';Kind='ntp';Expected=2},
    @{Tool='Security/Get-VMCertificateExpiry';Primary='Get-VMHost';Kind='certificate';Expected=2}
) {
    BeforeEach {
        $data=Initialize-Phase7Fixture
        $fakeConnection=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}
        $toolPath=Join-Path $root "scripts/$Tool.ps1"
        $arguments=@{Server=$fakeConnection}
        if ($Kind -eq 'snapshot') { $arguments.AsOf=[datetimeoffset]'2026-10-17T00:00:00Z' }
        if ($Kind -eq 'certificate') { $arguments.EndpointType='vCenter'; $arguments.AsOf=[datetimeoffset]'2026-10-17T00:00:00Z' }
        Mock Get-View { if ($ViewType -eq 'VirtualMachine') { $data.vmViews } else { $data.hostViews } }
        Mock Get-Datastore { $data.stores }
        Mock Get-VMHost { $data.hosts }
        Mock Get-VMHostNtpServer { $data.ntpServers }
        Mock Get-VM { $data.vms }
        Mock Get-Snapshot { $data.snapshots }
        Mock Get-VIMachineCertificate { $data.certificate }
    }
    It 'Projects synthetic documented fields and scopes every primary query' {
        $rows=@(& $toolPath @arguments)
        $rows.Count | Should -Be $Expected
        $rows[0].VIServer | Should -Be $fakeConnection.Name
        Should -Invoke $Primary -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection }
    }
    It 'Returns no rows for empty inventory' {
        Mock $Primary { @() }
        @(& $toolPath @arguments).Count | Should -Be 0
    }
    It 'Rejects disconnected objects before provider access' {
        $fakeConnection.IsConnected=$false
        { & $toolPath @arguments } | Should -Throw '*connected VIServer*'
        Should -Invoke $Primary -Times 0
    }
    It 'Rejects missing identity or malformed required data without partial success' {
        switch ($Kind) {
            tools { $data.vmViews[1].MoRef.PSObject.Properties.Remove('Value') }
            health { $data.hostViews[1].Runtime.InMaintenanceMode='false' }
            store { $data.stores[1].Accessible=$null }
            snapshot { $data.snapshots[1].PSObject.Properties.Remove('Id') }
            ntp { $data.hosts[1].PSObject.Properties.Remove('Id') }
            certificate { $data.hosts[1].PSObject.Properties.Remove('Id') }
        }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & $toolPath @arguments | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $captured.Count | Should -Be 0
    }
    It 'Rejects repeated object identities atomically' {
        switch ($Kind) {
            tools { $data.vmViews[1].MoRef.Value=$data.vmViews[0].MoRef.Value }
            health { $data.hostViews[1].MoRef.Value=$data.hostViews[0].MoRef.Value }
            store { $data.stores[1].Id=$data.stores[0].Id }
            snapshot { $data.snapshots[1].Id=$data.snapshots[0].Id }
            ntp { $data.hosts[1].Id=$data.hosts[0].Id }
            certificate { $data.hosts[1].Id=$data.hosts[0].Id }
        }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & $toolPath @arguments | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $captured.Count | Should -Be 0
    }
    It 'Sanitizes permission errors with stable error IDs' {
        Mock $Primary { throw [UnauthorizedAccessException]::new('fixture-private-denial') }
        $failure=$null
        try { & $toolPath @arguments } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -Match 'Toolkit\..*Failed'
        $failure.Exception.Message | Should -Not -Match 'fixture-private-denial'
    }
    It 'Sanitizes a lost provider session instead of returning successful output' {
        Mock $Primary { throw [IO.IOException]::new('fixture-private-connection-loss') }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & $toolPath @arguments | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -Match 'Toolkit\..*Failed'
        $failure.Exception.Message | Should -Not -Match fixture-private-connection-loss
        $captured.Count | Should -Be 0
    }
    It 'Stops on provider warnings instead of claiming complete inventory' {
        Mock $Primary { Write-Warning 'fixture-private-warning' }
        $failure=$null
        try { & $toolPath @arguments } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -Not -Match 'fixture-private-warning'
    }
    It 'Rejects whitespace name filters' {
        $arguments.Name=' '
        { & $toolPath @arguments } | Should -Throw
        Should -Invoke $Primary -Times 0
    }
}
Describe 'Specific semantics and query boundaries' {
    BeforeEach {
        $data=Initialize-Phase7Fixture
        $fakeConnection=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}
        $asOf=[datetimeoffset]'2026-10-17T00:00:00Z'
        Mock Get-View { if ($ViewType -eq 'VirtualMachine') { $data.vmViews } else { $data.hostViews } }
        Mock Get-Datastore { $data.stores }
        Mock Get-VMHost { $data.hosts }
        Mock Get-VMHostNtpServer { $data.ntpServers }
        Mock Get-VM { $data.vms }
        Mock Get-Snapshot { $data.snapshots }
        Mock Get-VIMachineCertificate { $data.certificate }
    }
    It 'Does not treat absent Tools information as current or installed' {
        $rows=@(& "$root/scripts/Reporting/Get-VMwareToolsStatus.ps1" -Server $fakeConnection)
        $rows[0].ToolsVersionStatus | Should -Be guestToolsCurrent
        $rows[1].ToolsRunningStatus | Should -Be Unknown
        $rows[1].DataSemantics | Should -Be LastKnownGuestInfo
    }
    It 'Preserves unexpected Tools strings without inventing a compliance assessment' {
        $data.vmViews[0].Guest.ToolsVersionStatus2='future-enum'
        $row=& "$root/scripts/Reporting/Get-VMwareToolsStatus.ps1" -Server $fakeConnection -Name lab-vm01
        $row.ToolsVersionStatus | Should -Be future-enum
    }
    It 'Keeps host alarm unknown for an unexpected or missing status and avoids hardware health claims' {
        $data.hostViews[0].Summary.OverallStatus='future-enum'
        $data.hostViews[1].Summary=$null
        $rows=@(& "$root/scripts/Health/Get-VMHostHealth.ps1" -Server $fakeConnection)
        $rows[0].AlarmStatus | Should -Be Unknown
        $rows[1].AlarmStatus | Should -Be Unknown
        $rows[0].HardwareHealth | Should -Be NotEvaluated
    }
    It 'Filters view names as wildcards with OR semantics, not regex' {
        @(& "$root/scripts/Reporting/Get-VMwareToolsStatus.ps1" -Server $fakeConnection -Name @('missing*','lab-vm02')).Count | Should -Be 1
        @(& "$root/scripts/Health/Get-VMHostHealth.ps1" -Server $fakeConnection -Name 'missing*').Count | Should -Be 0
    }
    It 'Preserves distinct objects sharing a display name' {
        $data.vmViews[1].Name=$data.vmViews[0].Name
        @(& "$root/scripts/Reporting/Get-VMwareToolsStatus.ps1" -Server $fakeConnection).Count | Should -Be 2
    }
    It 'Calculates capacity and leaves inaccessible or zero-capacity percentages unknown' {
        $rows=@(& "$root/scripts/Storage/Get-DatastoreCapacity.ps1" -Server $fakeConnection)
        $rows[0].UsedGiB | Should -Be 75
        $rows[0].UsedPercent | Should -Be 75
        $rows[1].CapacityGiB | Should -BeNullOrEmpty
        $rows[1].CapacityStatus | Should -Be Unknown
        $data.stores[0].CapacityGB=0;$data.stores[0].FreeSpaceGB=0
        $rows=@(& "$root/scripts/Storage/Get-DatastoreCapacity.ps1" -Server $fakeConnection)
        $rows[0].UsedPercent | Should -BeNullOrEmpty
    }
    It 'Rejects null, negative, nonfinite, nonnumeric and inconsistent capacity' {
        foreach ($value in @($null,-1,[double]::NaN,[double]::PositiveInfinity,'100',$true)) {
            $data.stores[0].CapacityGB=$value
            { & "$root/scripts/Storage/Get-DatastoreCapacity.ps1" -Server $fakeConnection } | Should -Throw
        }
        $data.stores[0].CapacityGB=10;$data.stores[0].FreeSpaceGB=20
        { & "$root/scripts/Storage/Get-DatastoreCapacity.ps1" -Server $fakeConnection } | Should -Throw
    }
    It 'Uses a strict snapshot age boundary and explicit scoping for reused queries' {
        $rows=@(& "$root/scripts/Reporting/Get-OldSnapshots.ps1" -Server $fakeConnection -AsOf $asOf -OlderThanDays 7)
        $rows.Count | Should -Be 1
        $rows[0].AgeDays | Should -Be 16
        Should -Invoke Get-Snapshot -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $VM.Id -eq $data.vms[0].Id }
    }
    It 'Rejects future snapshots, ambiguous timestamps and invalid thresholds' {
        $data.snapshots[1].Created=[datetime]'2027-01-01T00:00:00Z'
        { & "$root/scripts/Reporting/Get-OldSnapshots.ps1" -Server $fakeConnection -AsOf $asOf } | Should -Throw
        $data.snapshots[1].Created=[datetime]::SpecifyKind([datetime]'2026-10-10',[DateTimeKind]::Unspecified)
        { & "$root/scripts/Reporting/Get-OldSnapshots.ps1" -Server $fakeConnection -AsOf $asOf } | Should -Throw
        @(& "$root/scripts/Reporting/Get-OldSnapshots.ps1" -Server $fakeConnection -AsOf $asOf -UnspecifiedTimeZone ([TimeZoneInfo]::Utc)).Count | Should -Be 1
        foreach ($number in @(-1,[double]::NaN,[double]::PositiveInfinity)) {
            { & "$root/scripts/Reporting/Get-OldSnapshots.ps1" -Server $fakeConnection -OlderThanDays $number } | Should -Throw
        }
    }
    It 'Returns empty NTP configuration but does not claim synchronization' {
        Mock Get-VMHostNtpServer { @() }
        $rows=@(& "$root/scripts/Network/Get-VMHostNtpConfiguration.ps1" -Server $fakeConnection)
        @($rows[0].NtpServers).Count | Should -Be 0
        $rows[0].Synchronization | Should -Be NotEvaluated
        Should -Invoke Get-VMHostNtpServer -Times 2 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $null -ne $VMHost }
    }
    It 'Rejects invalid and repeated NTP entries' {
        Mock Get-VMHostNtpServer { 'ntp.example.invalid','NTP.example.invalid' }
        { & "$root/scripts/Network/Get-VMHostNtpConfiguration.ps1" -Server $fakeConnection } | Should -Throw
        Mock Get-VMHostNtpServer { 123 }
        { & "$root/scripts/Network/Get-VMHostNtpConfiguration.ps1" -Server $fakeConnection } | Should -Throw
    }
    It 'Calculates certificate horizon without returning PEM or claiming trust' {
        $row=& "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter -Scope VCenter -AsOf $asOf -ExpiringWithinDays 3
        $row.DaysToExpiry | Should -Be 3
        $row.TrustVerified | Should -BeFalse
        $row.PSObject.Properties.Name | Should -Not -Contain CertificatePEM
        Should -Invoke Get-VIMachineCertificate -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $VCenterOnly }
        @(& "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter -AsOf $asOf -ExpiringWithinDays 2).Count | Should -Be 0
    }
    It 'Reports expired and not-yet-valid certificates accurately by date' {
        $data.certificate.NotValidAfter=[datetime]'2026-10-17T00:00:00Z'
        $row=& "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter -Scope VCenter -AsOf $asOf
        $row.DateStatus | Should -Be Expired
        $data.certificate.NotValidBefore=[datetime]'2026-10-18T00:00:00Z'
        $data.certificate.NotValidAfter=[datetime]'2026-10-20T00:00:00Z'
        $row=& "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter -Scope VCenter -AsOf $asOf
        $row.DateStatus | Should -Be NotYetValid
    }
    It 'Rejects absent, duplicate and invalid certificate responses' {
        Mock Get-VIMachineCertificate { @() }
        { & "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter } | Should -Throw
        Mock Get-VIMachineCertificate { $data.certificate;$data.certificate }
        { & "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter } | Should -Throw
        Mock Get-VIMachineCertificate { $data.certificate }
        $data.certificate.NotValidAfter=$data.certificate.NotValidBefore
        { & "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter } | Should -Throw
    }
    It 'Blocks direct ESXi certificates and incompatible filters before provider access' {
        { & "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType ESXi } | Should -Throw
        { & "$root/scripts/Security/Get-VMCertificateExpiry.ps1" -Server $fakeConnection -EndpointType vCenter -Scope VCenter -Name '*' } | Should -Throw
        Should -Invoke Get-VMHost -Times 0
        Should -Invoke Get-VIMachineCertificate -Times 0
    }
    It 'Discards provider rows preceding a permission failure' {
        Mock Get-View { $data.vmViews[0]; throw [UnauthorizedAccessException]::new('fixture-private-partial') }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & "$root/scripts/Reporting/Get-VMwareToolsStatus.ps1" -Server $fakeConnection | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $captured.Count | Should -Be 0
        $failure.Exception.Message | Should -Not -Match fixture-private-partial
    }
    It 'Sanitizes secondary snapshot, NTP and certificate query failures' {
        Mock Get-Snapshot { throw [UnauthorizedAccessException]::new('fixture-private-secondary') }
        Mock Get-VMHostNtpServer { throw [UnauthorizedAccessException]::new('fixture-private-secondary') }
        Mock Get-VIMachineCertificate { throw [UnauthorizedAccessException]::new('fixture-private-secondary') }
        foreach ($case in @(
            @{Path='Reporting/Get-OldSnapshots';Args=@{AsOf=$asOf}},
            @{Path='Network/Get-VMHostNtpConfiguration';Args=@{}},
            @{Path='Security/Get-VMCertificateExpiry';Args=@{EndpointType='vCenter'}}
        )) {
            $captured=[Collections.Generic.List[object]]::new();$failure=$null
            $parameters=$case.Args
            try { & "$root/scripts/$($case.Path).ps1" -Server $fakeConnection @parameters | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception.Message | Should -Not -Match fixture-private-secondary
            $captured.Count | Should -Be 0
        }
    }
    It 'Rejects missing mandatory runtime and unexpected optional property types' {
        $data.vmViews[0].Guest.ToolsVersion=123
        { & "$root/scripts/Reporting/Get-VMwareToolsStatus.ps1" -Server $fakeConnection } | Should -Throw
        $data.hostViews[0].PSObject.Properties.Remove('Runtime')
        { & "$root/scripts/Health/Get-VMHostHealth.ps1" -Server $fakeConnection } | Should -Throw
    }
    It 'Preserves the existing default snapshot output while identity is opt-in' {
        $rows=@(& "$root/scripts/Reporting/Get-SnapshotReport.ps1" -Server $fakeConnection)
        $rows[0].PSObject.Properties.Name | Should -Not -Contain VMId
        $rows[0].PSObject.Properties.Name | Should -Not -Contain SnapshotId
        $rows=@(& "$root/scripts/Reporting/Get-SnapshotReport.ps1" -Server $fakeConnection -IncludeIdentity)
        $rows[0].VMId | Should -Be $data.vms[0].Id
        $rows[0].SnapshotId | Should -Be $data.snapshots[0].Id
    }
    It 'Contains only explicitly scoped provider reads and no connection or mutation commands' {
        $paths=@('Reporting/Get-VMwareToolsStatus','Health/Get-VMHostHealth','Storage/Get-DatastoreCapacity','Reporting/Get-OldSnapshots','Network/Get-VMHostNtpConfiguration','Security/Get-VMCertificateExpiry')
        $providers=@('Get-View','Get-Datastore','Get-VMHost','Get-VMHostNtpServer','Get-VIMachineCertificate')
        foreach ($path in $paths) {
            $tokens=$null;$parseErrors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile("$root/scripts/$path.ps1",[ref]$tokens,[ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
            $commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
            foreach ($command in $commands) {
                $name=$command.GetCommandName()
                $name | Should -Not -Match '^(Connect-|Disconnect-|Set-VM|New-VM|Remove-|Invoke-RestMethod|Invoke-WebRequest)'
                if ($name -in $providers) {
                    @($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Server' }).Count | Should -Be 1
                }
            }
        }
    }
    It 'Sanitizes projection getter failures' {
        $data.stores[1].Accessible=$true
        $data.stores[1] | Add-Member -MemberType ScriptProperty -Name CapacityGB -Value { throw 'fixture-private-getter' }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & "$root/scripts/Storage/Get-DatastoreCapacity.ps1" -Server $fakeConnection | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -Not -Match fixture-private-getter
        $captured.Count | Should -Be 0
    }
}
