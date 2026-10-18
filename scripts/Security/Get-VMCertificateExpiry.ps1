# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report date validity of machine SSL certificates via an explicit vCenter connection.
.DESCRIPTION
Uses Get-VIMachineCertificate, not a TLS socket probe or a VM guest certificate scan.
Scope VMHost queries selected connected hosts; Scope VCenter queries the vCenter machine certificate.
Direct ESXi is blocked because this cmdlet contract is only verified for vCenter context.
No trust-chain, hostname, revocation or complete certificate-store evaluation is performed.
Read-only; requires VMware.VimAutomation.Core and one explicit existing connection.
No connection, credential, TLS policy or infrastructure setting is changed.
.PARAMETER Server
One connected VIServer object; every provider query explicitly supplies -Server.
.PARAMETER Name
Name wildcard filters, OR semantics. Defaults to all objects in this connection.
.PARAMETER EndpointType
Required declaration: vCenter or ESXi. ESXi is deliberately rejected before provider access.
.PARAMETER Scope
VMHost (default) or VCenter. Name filters apply only to VMHost scope.
.PARAMETER ExpiringWithinDays
Optional finite nonnegative expiry horizon; expired certificates are included.
.PARAMETER AsOf
Reference instant, default UTC now.
.PARAMETER UnspecifiedTimeZone
Explicit source zone for unspecified provider DateTime values; ambiguous/invalid times fail.
.EXAMPLE
./Get-VMCertificateExpiry.ps1 -Server $connection -EndpointType vCenter -Scope VCenter
.EXAMPLE
./Get-VMCertificateExpiry.ps1 -Server $connection -EndpointType vCenter -Name 'lab-*'
.INPUTS
None. Parameters are supplied explicitly; pipeline input is not accepted.
.OUTPUTS
System.Management.Automation.PSCustomObject. Buffered report rows; no rows on empty inventory.
.NOTES
New local implementation, no inherited code. PowerShell 7.4+ source target.
Limited real-lab observations are documented in docs/TOOL-VALIDATION-MATRIX.md. Coverage varies
by endpoint and tool; vendor-certified compatibility is not established.
Requires visibility/read permission for queried objects; exact roles remain unverified.
Provider errors and warnings stop the report with a sanitized stable error ID.
All records are buffered; failure emits zero success records. Memory scales with input.
Output names/identities can be sensitive; never commit real exports.
See docs/POWERCLI-CONTRACTS.md for contracts, endpoint limitations and semantics.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNull()][object] $Server,
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
    [string[]] $Name = @('*'),
    [Parameter(Mandatory)][ValidateSet('vCenter','ESXi')][string] $EndpointType,
    [ValidateSet('VMHost','VCenter')][string] $Scope='VMHost',
    [ValidateScript({ [double]::IsFinite($_) -and $_ -ge 0 -and $_ -le 365000 })][double] $ExpiringWithinDays,
    [datetimeoffset] $AsOf=[datetimeoffset]::UtcNow,
    [TimeZoneInfo] $UnspecifiedTimeZone
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows = @(
        if ($EndpointType -ne 'vCenter') { throw 'Direct ESXi certificate contract not verified.' }
        if ($Scope -eq 'VCenter' -and $PSBoundParameters.ContainsKey('Name')) { throw 'Name applies to VMHost scope only.' }
        $targets=@(if ($Scope -eq 'VCenter') { $Server } else { Get-VMHost -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop })
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($target in $targets) {
            $targetName=ConvertTo-ToolkitText -Value $target.Name
            if ($Scope -eq 'VMHost') { $targetId=ConvertTo-ToolkitText -Value $target.Id } else { $targetId='VCenter' }
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $targetId
            $certificates=@(if ($Scope -eq 'VCenter') {
                @(Get-VIMachineCertificate -Server $Server -VCenterOnly -ErrorAction Stop -WarningAction Stop)
            } else {
                @(Get-VIMachineCertificate -Server $Server -VMHost $target -ErrorAction Stop -WarningAction Stop)
            })
            if ($certificates.Count -ne 1) { throw 'Expected exactly one machine SSL certificate per target.' }
            $certificate=$certificates[0]
            $uid=ConvertTo-ToolkitText -Value $certificate.Uid
            $before=ConvertTo-ToolkitInstant -Value $certificate.NotValidBefore -UnspecifiedTimeZone $UnspecifiedTimeZone
            $after=ConvertTo-ToolkitInstant -Value $certificate.NotValidAfter -UnspecifiedTimeZone $UnspecifiedTimeZone
            if ($after -le $before) { throw 'Invalid certificate interval.' }
            $remaining=($after-$AsOf.ToUniversalTime()).TotalDays
            $state=if ($remaining -le 0) { 'Expired' } elseif ($before -gt $AsOf.ToUniversalTime()) { 'NotYetValid' } else { 'WithinDateWindow' }
            if (-not $PSBoundParameters.ContainsKey('ExpiringWithinDays') -or $remaining -le $ExpiringWithinDays) {
                [pscustomobject]@{
                    VIServer=$Server.Name; Entity=$targetName; Scope=$Scope; CertificateUid=$uid
                    NotBeforeUtc=$before; NotAfterUtc=$after; DaysToExpiry=$remaining
                    DateStatus=$state; TrustVerified=$false; AsOfUtc=$AsOf.ToUniversalTime()
                }
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Get-VMCertificateExpiry failed. No records were emitted.'),
        'Toolkit.VMCertificateExpiryFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
