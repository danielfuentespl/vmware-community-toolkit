# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
function ConvertTo-ToolkitOldSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Snapshot,
        [ValidateScript({[double]::IsFinite($_) -and $_ -ge 0 -and $_ -le 365000})][double]$OlderThanDays=7,
        [datetimeoffset]$AsOf=[datetimeoffset]::UtcNow,[TimeZoneInfo]$UnspecifiedTimeZone)
    $rows=@(
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in $Snapshot) {
            $vmId=ConvertTo-ToolkitText $entry.VMId
            $snapshotId=ConvertTo-ToolkitText $entry.SnapshotId
            $key=ConvertTo-Json -InputObject @($vmId,$snapshotId) -Compress
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $key
            $created=ConvertTo-ToolkitInstant -Value $entry.Created -UnspecifiedTimeZone $UnspecifiedTimeZone
            $age=($AsOf.ToUniversalTime()-$created).TotalDays
            if ($age -lt 0) { throw 'Future snapshot timestamp.' }
            if ($age -gt $OlderThanDays) {
                [pscustomobject]@{VIServer=$entry.VIServer;VMId=$vmId;VM=$entry.VM;SnapshotId=$snapshotId;Snapshot=$entry.Snapshot;CreatedUtc=$created;AgeDays=$age;SizeGiB=$entry.SizeGB;AsOfUtc=$AsOf.ToUniversalTime()}
            }
        }
    )
    $rows
}
Export-ModuleMember -Function ConvertTo-ToolkitOldSnapshot
