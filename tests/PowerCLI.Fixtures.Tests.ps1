# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $report=Join-Path $root 'scripts/Reporting'
    $setter=Join-Path $root 'scripts/Network/Set-VMHostDnsServers.ps1'
    function Get-VM { [CmdletBinding()] param($Server,$Name) throw 'No live calls' }
    function Get-Snapshot { [CmdletBinding()] param($Server,$VM) throw 'No live calls' }
    function Get-VMHost { [CmdletBinding()] param($Server,$Name) throw 'No live calls' }
    function Get-VMHostNetwork { [CmdletBinding()] param($Server,$VMHost) throw 'No live calls' }
    function Set-VMHostNetwork { [CmdletBinding(SupportsShouldProcess)] param($Network,$DnsAddress,$DnsFromDhcp) throw 'No writes' }
}
Describe 'PowerCLI serialized projection fixtures (not vendor CLR objects)' {
    BeforeEach {
        $data=Get-Content (Join-Path $PSScriptRoot 'fixtures/powercli-projections.json') -Raw | ConvertFrom-Json
        $fakeConnection=$data.connection
        Mock Get-VM { $data.vms }
        Mock Get-Snapshot { $data.snapshot }
        Mock Get-VMHost { $data.hosts }
        Mock Get-VMHostNetwork { $data.network }
        Mock Set-VMHostNetwork { throw 'Mutation forbidden' }
    }
    It 'Simulates inventory, zero-sized snapshots and empty DNS lists' {
        @(& "$report/Get-VMInventory.ps1" -Server $fakeConnection).Count | Should -Be 2
        $snapshots=@(& "$report/Get-SnapshotReport.ps1" -Server $fakeConnection)
        $snapshots.Count | Should -Be 2
        $snapshots[0].SizeGB | Should -Be 0
        $dns=@(& "$report/Get-VMHostDnsReport.ps1" -Server $fakeConnection)
        $dns.Count | Should -Be 2
        @($dns[0].DnsAddress).Count | Should -Be 0
    }
    It 'Sanitizes permission failures for each read operation' {
        Mock Get-VM { throw [UnauthorizedAccessException]::new('fixture-private-permission') }
        Mock Get-VMHost { throw [UnauthorizedAccessException]::new('fixture-private-permission') }
        foreach ($tool in @('Get-VMInventory','Get-SnapshotReport','Get-VMHostDnsReport')) {
            try { & "$report/$tool.ps1" -Server $fakeConnection; throw 'Unexpected success' }
            catch { $_.Exception.Message | Should -Not -Match 'fixture-private-permission|Unexpected success' }
        }
    }
    It 'Rejects nonfinite or unavailable measurements atomically' {
        foreach ($value in @([double]::NaN,[double]::PositiveInfinity,$null,-1)) {
            $data.vms[1].MemoryGB=$value
            { & "$report/Get-VMInventory.ps1" -Server $fakeConnection } | Should -Throw
            $data.snapshot.SizeGB=$value
            { & "$report/Get-SnapshotReport.ps1" -Server $fakeConnection } | Should -Throw
        }
    }
    It 'Keeps WhatIf discovery explicit and never writes DNS' {
        Mock Get-VMHost { $data.hosts[0] }
        & $setter -Server $fakeConnection -VMHostName 'esxi01.example.invalid' -DnsAddress '192.0.2.53' -WhatIf
        Should -Invoke Get-VMHost -Times 1 -ParameterFilter { $Server -eq $fakeConnection }
        Should -Invoke Set-VMHostNetwork -Times 0 -Exactly
    }
}
