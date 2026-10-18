# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Run reproducible synthetic VCF examples without PowerCLI or network access.
#>
[CmdletBinding()]
param()
$root=Split-Path $PSScriptRoot -Parent
foreach ($pair in @(@('Inventory','domains'),@('Health','health'),@('Versions','managers'),@('Certificates','certificates'))) {
    $rows=@(& (Join-Path $root "scripts/VCF/Get-VCF$($pair[0]).ps1") -Path (Join-Path $root "tests/fixtures/vcf-$($pair[1])-pages.json") -SourceVersion 'unverified-synthetic-fixture')
    [pscustomobject]@{ Tool=$pair[0]; Validation='Simulation'; Records=$rows.Count; RealVmwareValidated=$false }
}
