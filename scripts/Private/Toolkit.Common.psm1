# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
function Assert-ToolkitConnection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object] $Server)
    if ($null -eq $Server -or $Server -is [array] -or
        $null -eq $Server.PSObject.Properties['IsConnected'] -or
        $null -eq $Server.PSObject.Properties['Name'] -or
        $Server.IsConnected -isnot [bool] -or -not $Server.IsConnected -or
        [string]::IsNullOrWhiteSpace([string] $Server.Name)) {
        throw 'Provide one connected VIServer object from Connect-VIServer.'
    }
}
function ConvertTo-ToolkitDnsAddress {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Address)
    $parsed = $null
    if ($Address -ne $Address.Trim() -or -not [System.Net.IPAddress]::TryParse($Address, [ref] $parsed)) {
        throw 'DNS addresses must be valid IPv4 or IPv6 literals.'
    }
    if ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        if ($Address -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$' -or
            @($Address.Split('.') | Where-Object { $_.Length -gt 1 -and $_.StartsWith('0') }).Count -gt 0) {
            throw 'IPv4 addresses require four decimal octets without leading zeros.'
        }
    }
    $parsed.ToString()
}
function Get-ToolkitProperty {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object] $InputObject,
        [Parameter(Mandatory)][string] $Name, [switch] $Optional)
    if ($null -eq $InputObject) {
        if ($Optional) { return $null }
        throw 'Required object is missing.'
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        if ($Optional) { return $null }
        throw 'Required property is missing.'
    }
    $value = $property.Value
    if ($null -eq $value -and -not $Optional) { throw 'Required value is missing.' }
    $value
}
function ConvertTo-ToolkitText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()][object] $Value, [switch] $Optional)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        if ($Optional) { return 'Unknown' }
        throw 'Required text is missing.'
    }
    if ($Value -isnot [string] -and $Value -isnot [Enum]) { throw 'Unexpected text type.' }
    [string] $Value
}
function Assert-ToolkitUniqueIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]] $Seen,
        [Parameter(Mandatory)][object] $Id)
    $key = ConvertTo-ToolkitText -Value $Id
    if (-not $Seen.Add($key)) { throw 'Duplicate identity returned by provider.' }
}
function ConvertTo-ToolkitMeasurement {
    [CmdletBinding()]
    [OutputType([double])]
    param([Parameter(Mandatory)][AllowNull()][object] $Value)
    if ($null -eq $Value -or $Value -isnot [ValueType] -or $Value -is [bool] -or
        -not [double]::IsFinite([double] $Value) -or [double] $Value -lt 0) { throw 'Invalid measurement.' }
    [double] $Value
}
function ConvertTo-ToolkitInstant {
    [CmdletBinding()]
    [OutputType([datetimeoffset])]
    param([Parameter(Mandatory)][AllowNull()][object] $Value, [TimeZoneInfo] $UnspecifiedTimeZone)
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime() }
    if ($Value -isnot [datetime]) { throw 'Expected a typed timestamp.' }
    if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
        if ($null -eq $UnspecifiedTimeZone -or $UnspecifiedTimeZone.IsInvalidTime($Value) -or $UnspecifiedTimeZone.IsAmbiguousTime($Value)) {
            throw 'Timestamp needs an explicit unambiguous source time zone.'
        }
        return [datetimeoffset]::new([TimeZoneInfo]::ConvertTimeToUtc($Value, $UnspecifiedTimeZone))
    }
    ([datetimeoffset] $Value).ToUniversalTime()
}
Export-ModuleMember -Function Assert-ToolkitConnection, ConvertTo-ToolkitDnsAddress, Get-ToolkitProperty, ConvertTo-ToolkitText, Assert-ToolkitUniqueIdentity, ConvertTo-ToolkitMeasurement, ConvertTo-ToolkitInstant
