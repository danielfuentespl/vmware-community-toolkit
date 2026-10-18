# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module PSScriptAnalyzer -ErrorAction Stop
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$root = Split-Path $PSScriptRoot -Parent
$findings = @(Invoke-ScriptAnalyzer -Path (Join-Path $root 'scripts') -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1'))
if ($findings.Count) {
    $findings | Format-Table RuleName, Severity, ScriptName, Line
    throw 'PSScriptAnalyzer reported findings.'
}
$result = Invoke-Pester -Path $PSScriptRoot -PassThru -Output Detailed
if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.SkippedCount -gt 0 -or $result.NotRunCount -gt 0) { throw 'Mocked tests did not pass.' }
