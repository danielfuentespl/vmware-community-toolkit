# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $report = Join-Path $root 'scripts/Reporting'
    $setter = Join-Path $root 'scripts/Network/Set-VMHostDnsServers.ps1'
    function Get-VM { [CmdletBinding()] param($Server,$Name) throw 'Network prohibited' }
    function Get-Snapshot { [CmdletBinding()] param($Server,$VM) throw 'Network prohibited' }
    function Get-VMHost { [CmdletBinding()] param($Server,$Name) throw 'Network prohibited' }
    function Get-VMHostNetwork { [CmdletBinding()] param($Server,$VMHost) throw 'Network prohibited' }
    function Set-VMHostNetwork { [CmdletBinding(SupportsShouldProcess)] param($Network,$DnsAddress,$DnsFromDhcp) throw 'Network prohibited' }
}
Describe 'Atomic reporting and validation' {
    BeforeEach {
        $connection = [pscustomobject]@{Name='vcenter.example.invalid';IsConnected=$true}
        $seen = [System.Collections.Generic.List[object]]::new()
        Mock Get-VM { @([pscustomobject]@{Name='lab-a'},[pscustomobject]@{Name='lab-b'}) }
        Mock Get-Snapshot {
            if ($VM.Name -eq 'lab-b') { throw 'Simulated second-entity failure' }
            [pscustomobject]@{Name='snapshot';Created=[datetime]'2026-01-01';SizeGB=1}
        }
        Mock Get-VMHost { @([pscustomobject]@{Name='esxi-a.example.invalid'},[pscustomobject]@{Name='esxi-b.example.invalid'}) }
        Mock Get-VMHostNetwork {
            if ($VMHost.Name -eq 'esxi-b.example.invalid') { throw 'Simulated second-host failure' }
            [pscustomobject]@{DnsAddress=@('192.0.2.53');DomainName='example.invalid';SearchDomain=@()}
        }
    }
    It 'Emits no snapshot records when a later VM fails and uses a stable error ID' {
        try { & "$report/Get-SnapshotReport.ps1" -Server $connection | ForEach-Object { $seen.Add($_) } }
        catch { $_.FullyQualifiedErrorId | Should -BeLike 'Toolkit.SnapshotReportFailed*' }
        $seen.Count | Should -Be 0
        Should -Invoke Get-Snapshot -Times 2
    }
    It 'Emits no DNS records when a later host fails' {
        try { & "$report/Get-VMHostDnsReport.ps1" -Server $connection | ForEach-Object { $seen.Add($_) } } catch { }
        $seen.Count | Should -Be 0
        Should -Invoke Get-VMHostNetwork -Times 2
    }
    It 'Emits no VM records when projection fails on a later entity' {
        Mock Get-VM { @([pscustomobject]@{Name='lab-a';PowerState='On';NumCpu=2;MemoryGB=4;VMHost='esxi.example.invalid'},[pscustomobject]@{Name='lab-b'}) }
        try { & "$report/Get-VMInventory.ps1" -Server $connection | ForEach-Object { $seen.Add($_) } } catch { }
        $seen.Count | Should -Be 0
    }
    It 'Promotes nonterminating provider errors to a report failure' {
        Mock Get-VM { Write-Error 'Simulated nonterminating failure' }
        { & "$report/Get-VMInventory.ps1" -Server $connection } | Should -Throw '*inventory failed*'
    }
    It 'Rejects missing or nonboolean connection state before querying' {
        foreach ($server in @([pscustomobject]@{Name='lab'},[pscustomobject]@{Name='lab';IsConnected='true'},[pscustomobject]@{Name=' ';IsConnected=$true})) {
            { & "$report/Get-VMInventory.ps1" -Server $server } | Should -Throw '*connected VIServer*'
        }
        Should -Invoke Get-VM -Times 0
    }
    It 'Rejects blank names and missing mandatory parameters via metadata' {
        { & "$report/Get-VMInventory.ps1" -Server $connection -Name @(' ') } | Should -Throw
        foreach ($file in Get-ChildItem $report -Filter 'Get-*.ps1') {
            $command = Get-Command $file.FullName
            $command.Parameters.Server.Attributes.Mandatory | Should -Contain $true
        }
        Should -Invoke Get-VM -Times 0
    }
    It 'Rejects unavailable snapshot size instead of reporting false zero' {
        Mock Get-Snapshot { [pscustomobject]@{Name='snapshot';Created=[datetime]'2026-01-01';SizeGB=$null} }
        { & "$report/Get-SnapshotReport.ps1" -Server $connection } | Should -Throw '*datastore browse*'
    }
    It 'Rejects missing or ambiguous host network results' {
        Mock Get-VMHostNetwork { @() }
        { & "$report/Get-VMHostDnsReport.ps1" -Server $connection } | Should -Throw '*DNS report failed*'
    }
    It 'Does not leak provider error text through the terminating error message' {
        Mock Get-VM { throw 'SYNTHETIC_PRIVATE_MARKER' }
        try { & "$report/Get-VMInventory.ps1" -Server $connection } catch {
            $_.Exception.Message | Should -Not -Match 'SYNTHETIC_PRIVATE_MARKER'
            $_.CategoryInfo.Category | Should -Be 'ReadError'
        }
    }
}
Describe 'Explicit query and TLS invariants' {
    It 'Scopes every PowerCLI read to Server and promotes provider errors' {
        foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Recurse -Filter '*.ps1') {
            $commands=$file | ForEach-Object { (Get-Command $_.FullName).ScriptBlock.Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -in @('Get-VM','Get-VMHost','Get-Snapshot','Get-VMHostNetwork')
            }, $true) }
            foreach ($command in $commands) {
                $params=@($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object ParameterName)
                $params | Should -Contain 'Server'
                $params | Should -Contain 'ErrorAction'
            }
        }
    }
    It 'Does not alter connections, credentials or TLS policy in any tool' {
        foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Recurse -Include '*.ps1','*.psm1') {
            $commands=(Get-Content $file.FullName -Raw)
            $commands | Should -Not -Match 'Set-PowerCLIConfiguration|SkipCertificateCheck|ServerCertificateValidationCallback|Invoke-Expression'
        }
    }
}
