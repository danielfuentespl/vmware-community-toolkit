# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
function Get-ReportValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Object,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return ,$Object[$Name] }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return ,$property.Value }
}
function ConvertTo-ReportText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][object]$Value,[switch]$Required)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        if ($Required) { throw 'Required text missing.' }
        return 'Unknown'
    }
    if ($Value -isnot [string] -and $Value -isnot [Enum]) { throw 'Expected plain text.' }
    [string]$Value
}
function ConvertTo-ReportInstant {
    [CmdletBinding()]
    [OutputType([datetimeoffset])]
    param([Parameter(Mandatory)][AllowNull()][object]$Value)
    if ($Value -is [string]) {
        $parsed=[datetimeoffset]::MinValue
        if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$' -or
            -not [datetimeoffset]::TryParse($Value,[cultureinfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)) { throw 'Timestamp requires an offset.' }
        return $parsed.ToUniversalTime()
    }
    ConvertTo-ToolkitInstant -Value $Value
}
function ConvertTo-ReportNumber {
    [CmdletBinding()]
    param([AllowNull()][object]$Value,[switch]$Positive,[switch]$Integer)
    if ($null -eq $Value) { return $null }
    $number=ConvertTo-ToolkitMeasurement -Value $Value
    if (($Positive -and $number -le 0) -or ($Integer -and $number % 1 -ne 0)) { throw 'Invalid measurement.' }
    $number
}
function Get-ReportRecord {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return }
    if ($Value -isnot [array]) { throw 'Collections must be explicit arrays.' }
    foreach ($row in $Value) {
        if ($null -eq $row -or ($row -isnot [pscustomobject] -and $row -isnot [System.Collections.IDictionary])) { throw 'Expected structured records.' }
        $row
    }
}
function Write-ReportFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    if ($Path -match '^(?:\\\\|//|[a-z]+://)') { throw 'Local paths only.' }
    $full=[IO.Path]::GetFullPath($Path)
    $directory=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($full))
    if (-not $directory.Exists) { throw 'Output parent directory must exist.' }
    while ($null -ne $directory) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Symlink output paths are forbidden.' }
        $directory=$directory.Parent
    }
    if ($IsWindows -and [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full)).DriveType -eq [IO.DriveType]::Network) { throw 'Local output required.' }
    $options=[IO.FileStreamOptions]::new()
    $options.Mode=[IO.FileMode]::CreateNew; $options.Access=[IO.FileAccess]::Write; $options.Share=[IO.FileShare]::None
    if (-not $IsWindows) { $options.UnixCreateMode=[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite }
    $stream=[IO.FileStream]::new($full,$options)
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Content)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } catch {
        $stream.Dispose()
        [IO.File]::Delete($full)
        throw
    } finally { $stream.Dispose() }
    $full
}
Export-ModuleMember -Function Get-ReportValue, ConvertTo-ReportText, ConvertTo-ReportInstant, ConvertTo-ReportNumber, Get-ReportRecord, Write-ReportFile
