# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Set static DNS server addresses for one explicitly named ESXi host.
.DESCRIPTION
Requires an existing connection and host network configuration privileges.
Phase 3 permits -WhatIf only; real writes are disabled. The operation affects management DNS and is not transactional.
.PARAMETER Server
One connected VIServer object from Connect-VIServer.
.PARAMETER VMHostName
Exact host name. Wildcards are rejected. Exactly one matching host is required.
.PARAMETER DnsAddress
One or more IPv4 or IPv6 addresses. IPv4 shorthand/leading zeros and canonical duplicates are rejected.
.EXAMPLE
./Set-VMHostDnsServers.ps1 -Server $connection -VMHostName 'esxi01.example.invalid' -DnsAddress '192.0.2.53' -WhatIf
.NOTES
New implementation generated for this toolkit; no source script code is copied.
PowerShell 7.4+ target. PowerCLI/vSphere compatibility needs laboratory validation.
WhatIf queries inventory but does not invoke the setter. There is no automatic rollback.
Success is emitted only after a fresh read confirms ordered DNS addresses and DHCP DNS disabled.
Read-back failure may follow a completed write; recover manually, never retry blindly.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object] $Server,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ -notmatch '[*?\[\]]' -and $_ -eq $_.Trim() -and -not [string]::IsNullOrWhiteSpace($_) })]
    [string] $VMHostName,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $DnsAddress
)
Set-StrictMode -Version Latest
# Phase 3/4 safety gate: no runtime invocation can reach a real DNS write.
if (-not $WhatIfPreference) {
    throw 'DNS writes are disabled during Phase 3/4. Invoke with -WhatIf only.'
}
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
$canonical = @($DnsAddress | ForEach-Object { ConvertTo-ToolkitDnsAddress -Address $_ })
if (@($canonical | Sort-Object -Unique).Count -ne $canonical.Count) {
    throw 'Duplicate DNS addresses are not permitted, including equivalent IPv6 representations.'
}
try {
    $hosts = @(Get-VMHost -Server $Server -Name $VMHostName -ErrorAction Stop)
    if ($hosts.Count -ne 1 -or $hosts[0].Name -ne $VMHostName) {
        throw 'Exactly one host with the requested exact name is required.'
    }
    $network = @(Get-VMHostNetwork -Server $Server -VMHost $hosts[0] -ErrorAction Stop)
    if ($network.Count -ne 1 -or $null -eq $network[0]) { throw 'Exactly one host network object is required.' }
    if ($PSCmdlet.ShouldProcess($VMHostName, 'Replace DNS server addresses and disable DHCP DNS')) {
        # Bind the object selected through the explicit connection; this cmdlet has no Server parameter.
        $null = Set-VMHostNetwork -Network $network[0] -DnsFromDhcp $false -DnsAddress $canonical -Confirm:$false -ErrorAction Stop
        $after = @(Get-VMHostNetwork -Server $Server -VMHost $hosts[0] -ErrorAction Stop)
        if ($after.Count -ne 1 -or $null -eq $after[0]) { throw 'DNS read-back unavailable.' }
        $actual = @($after[0].DnsAddress | ForEach-Object { ConvertTo-ToolkitDnsAddress -Address $_ })
        if (($actual -join '|') -cne ($canonical -join '|') -or
            $after[0].DnsFromDhcp -isnot [bool] -or $after[0].DnsFromDhcp) {
            throw 'DNS read-back did not match the requested static configuration.'
        }
        [pscustomobject]@{
            VIServer = $Server.Name
            VMHost = $hosts[0].Name
            DnsAddress = $actual
            DnsFromDhcp = $false
            Verification = 'ReadBackMatched'
        }
    }
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('DNS update failed. Configuration may have changed; verify it before retrying; no rollback was attempted.'),
        'Toolkit.DnsUpdateFailed', [System.Management.Automation.ErrorCategory]::OperationStopped, $null))
}
