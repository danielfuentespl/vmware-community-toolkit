# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $report = Join-Path $root 'scripts/Reporting'
    $setter = Join-Path $root 'scripts/Network/Set-VMHostDnsServers.ps1'
    # Local doubles expose the vendor parameter names; PowerCLI is never imported.
    function Get-VM { [CmdletBinding()] param($Server, $Name) throw 'Unexpected live query' }
    function Get-Snapshot { [CmdletBinding()] param($Server, $VM) throw 'Unexpected live query' }
    function Get-VMHost { [CmdletBinding()] param($Server, $Name) throw 'Unexpected live query' }
    function Get-VMHostNetwork { [CmdletBinding()] param($Server, $VMHost) throw 'Unexpected live query' }
    function Set-VMHostNetwork {
        [CmdletBinding(SupportsShouldProcess)] param($Network, $DnsAddress, $DnsFromDhcp)
        throw 'Unexpected live mutation'
    }
}
Describe 'Read-only reports' {
    BeforeEach {
        $connection = [pscustomobject]@{Name = 'vcenter.example.invalid'; IsConnected = $true}
        Mock Get-VM { [pscustomobject]@{Name='lab-vm01';PowerState='PoweredOn';NumCpu=2;MemoryGB=4;VMHost='esxi01.example.invalid'} }
        Mock Get-Snapshot { [pscustomobject]@{Name='lab-checkpoint';Created=[datetime]'2026-01-01';SizeGB=1} }
        Mock Get-VMHost { [pscustomobject]@{Name='esxi01.example.invalid'} }
        Mock Get-VMHostNetwork { [pscustomobject]@{DnsAddress=@('192.0.2.53');DomainName='example.invalid';SearchDomain=@('example.invalid')} }
        Mock Set-VMHostNetwork { }
    }
    It 'Returns structured inventory and scopes the connection' {
        $rows = @(& "$report/Get-VMInventory.ps1" -Server $connection -Name 'lab-*')
        $rows.Count | Should -Be 1
        $rows[0].NumCpu | Should -Be 2
        $rows[0].VIServer | Should -Be $connection.Name
        Should -Invoke Get-VM -Times 1 -Exactly -ParameterFilter { $Server -eq $connection -and $Name -eq 'lab-*' }
        Should -Invoke Set-VMHostNetwork -Times 0
    }
    It 'Returns snapshot records with VM identity' {
        $rows = @(& "$report/Get-SnapshotReport.ps1" -Server $connection)
        $rows[0].VM | Should -Be 'lab-vm01'
        $rows[0].SizeGB | Should -Be 1
        Should -Invoke Get-Snapshot -Times 1 -ParameterFilter { $Server -eq $connection -and $VM.Name -eq 'lab-vm01' }
    }
    It 'Returns DNS arrays' {
        $row = & "$report/Get-VMHostDnsReport.ps1" -Server $connection
        $row.DnsAddress[0] | Should -Be '192.0.2.53'
        Should -Invoke Get-VMHostNetwork -Times 1 -ParameterFilter { $Server -eq $connection -and $VMHost.Name -eq 'esxi01.example.invalid' }
    }
    It 'Handles an empty inventory' {
        Mock Get-VM { @() }
        @(& "$report/Get-VMInventory.ps1" -Server $connection).Count | Should -Be 0
        @(& "$report/Get-SnapshotReport.ps1" -Server $connection).Count | Should -Be 0
        Should -Invoke Get-Snapshot -Times 0
    }
    It 'Handles hosts with no matches' {
        Mock Get-VMHost { @() }
        @(& "$report/Get-VMHostDnsReport.ps1" -Server $connection).Count | Should -Be 0
        Should -Invoke Get-VMHostNetwork -Times 0
    }
    It 'Sanitizes provider warning from <Provider> in <File> without records' -ForEach @(
        @{File='Get-VMInventory.ps1';Provider='Get-VM'},
        @{File='Get-SnapshotReport.ps1';Provider='Get-VM'},
        @{File='Get-SnapshotReport.ps1';Provider='Get-Snapshot'},
        @{File='Get-VMHostDnsReport.ps1';Provider='Get-VMHost'},
        @{File='Get-VMHostDnsReport.ps1';Provider='Get-VMHostNetwork'}
    ) {
        Mock $Provider { Write-Warning 'fixture-private-provider-warning' }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & "$report/$File" -Server $connection 3>&1 | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -Match 'Toolkit\..*Failed'
        $failure.ToString() | Should -Not -Match 'fixture-private-provider-warning'
        $captured.Count | Should -Be 0
    }
    It 'Stops on VM query failure' {
        Mock Get-VM { throw 'Synthetic failure' }
        { & "$report/Get-VMInventory.ps1" -Server $connection } | Should -Throw '*inventory failed*'
        { & "$report/Get-SnapshotReport.ps1" -Server $connection } | Should -Throw '*report failed*'
    }
    It 'Stops on snapshot query failure' {
        Mock Get-Snapshot { throw 'Synthetic failure' }
        { & "$report/Get-SnapshotReport.ps1" -Server $connection } | Should -Throw '*report failed*'
    }
    It 'Stops on host network failure' {
        Mock Get-VMHostNetwork { throw 'Synthetic failure' }
        { & "$report/Get-VMHostDnsReport.ps1" -Server $connection } | Should -Throw '*DNS report failed*'
    }
    It 'Rejects disconnected connections in all reports' {
        $connection.IsConnected = $false
        foreach ($file in Get-ChildItem $report -Filter 'Get-*.ps1') {
            { & $file.FullName -Server $connection } | Should -Throw '*connected VIServer*'
        }
        Should -Invoke Get-VM -Times 0
        Should -Invoke Get-VMHost -Times 0
    }
    It 'Rejects multiple connections' {
        foreach ($file in Get-ChildItem $report -Filter 'Get-*.ps1') {
            { & $file.FullName -Server @($connection,$connection) } | Should -Throw '*connected VIServer*'
        }
    }
    It 'Labels a direct ESXi connection generically instead of claiming it is vCenter' {
        $connection.Name='esxi.example.invalid'
        $row=& "$report/Get-VMInventory.ps1" -Server $connection
        $row.VIServer | Should -Be 'esxi.example.invalid'
        $row.PSObject.Properties.Name | Should -Not -Contain 'VCenter'
    }

}
