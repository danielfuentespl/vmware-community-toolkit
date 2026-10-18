# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Reporting.Support.psm1') -Scope Local -ErrorAction Stop
function ConvertTo-AuditBoolean {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'Unknown' }
    if ($Value -isnot [bool]) { throw 'Invalid boolean observation.' }
    $Value
}
function ConvertTo-AuditInteger {
    [CmdletBinding()]
    param([AllowNull()][object]$Value,[switch]$Signed)
    if ($null -eq $Value) { return 'Unknown' }
    if ($Value -is [string]) {
        if ($Value -notmatch '^-?[0-9]+$') { throw 'Invalid integral setting.' }
    } elseif ($Value -isnot [ValueType] -or $Value -is [bool]) { throw 'Invalid integral observation.' }
    $number=[double]$Value
    if (-not [double]::IsFinite($number) -or $number % 1 -ne 0 -or $number -gt [int]::MaxValue -or
        $number -lt $(if ($Signed) { [int]::MinValue } else { 0 })) { throw 'Invalid integer range.' }
    [int]$number
}
function Get-AuditSafeSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SettingName,[AllowNull()][object]$Setting)
    if ($null -eq $Setting) { return [pscustomobject]@{Value='Unknown';ValueState='Unknown'} }
    # No generic setting dump: unknown names never even evaluate the Value property.
    $known=@('Syslog.global.logHost','Syslog.global.logDir','Syslog.global.logDirUnique','Syslog.global.defaultRotate','Syslog.global.defaultSize')
    if ($SettingName -cnotin $known) { return [pscustomobject]@{Value='[Withheld]';ValueState='Withheld'} }
    $value=Get-ReportValue $Setting Value
    if ($null -eq $value) { return [pscustomobject]@{Value='Unknown';ValueState='Unknown'} }
    switch -CaseSensitive ($SettingName) {
        'Syslog.global.logDirUnique' {
            if ($value -is [string] -and $value -cin @('true','false','0','1')) { $value=$value -cin @('true','1') }
            if ($value -is [int] -or $value -is [long]) {
                if ($value -notin @(0,1)) { throw 'Invalid boolean setting.' }
                $value=[bool]$value
            }
            $value=ConvertTo-AuditBoolean $value
        }
        { $_ -cin @('Syslog.global.defaultRotate','Syslog.global.defaultSize') } { $value=ConvertTo-AuditInteger $value }
        default {
            if ($value -isnot [string]) { throw 'Unexpected setting type.' }
            if ($value -match '(?i)://[^/\s]*@|(?:password|token|secret|credential)\s*[=:]|-----BEGIN .*PRIVATE KEY') {
                return [pscustomobject]@{Value='[Withheld]';ValueState='Withheld'}
            }
        }
    }
    [pscustomobject]@{Value=$value;ValueState='Reported'}
}
Export-ModuleMember -Function ConvertTo-AuditBoolean, ConvertTo-AuditInteger, Get-AuditSafeSetting
