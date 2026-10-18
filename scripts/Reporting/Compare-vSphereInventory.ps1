# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Compare two offline inventories within one explicitly identified scope.
.DESCRIPTION
No provider calls. Accepts envelopes containing ScopeId, IdentityKind, SelectionId,
CapturedAt, Completeness and VMs arrays. IdentityKind must be PowerCliId or MoRefValue.
Never matches by VM name. Partial collections cannot prove additions/removals.
.PARAMETER Baseline
Earlier envelope. ScopeId identifies the same persistent endpoint/identity namespace.
.PARAMETER Current
Later envelope with the same scope, identity kind and selection definition.
.PARAMETER CsvPath
Optional new local CSV file. Existing paths are never overwritten. Formula-like text
is prefixed with an apostrophe in CSV only; returned objects retain original text.
.INPUTS
None. Supply both envelopes explicitly.
.OUTPUTS
PSCustomObject per change or noncomparable field; unchanged comparable fields emit no row.
.EXAMPLE
./Compare-vSphereInventory.ps1 -Baseline $before -Current $after
.EXAMPLE
./Compare-vSphereInventory.ps1 -Baseline $before -Current $after -CsvPath './changes.csv' -WhatIf
.NOTES
Offline local validation only. No VMware release compatibility claim. Scope/selection
and completeness labels are caller assertions. Protect real output outside Git.
See docs/UNIFIED-REPORTING.md. All results buffer before emission or CSV creation.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateNotNull()][object]$Baseline,
    [Parameter(Mandatory)][ValidateNotNull()][object]$Current,
    [ValidateNotNullOrEmpty()][string]$CsvPath
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Reporting.Support.psm1') -Scope Local -ErrorAction Stop
try {
    foreach ($field in @('ScopeId','IdentityKind','SelectionId')) {
        $left=ConvertTo-ReportText -Value (Get-ReportValue $Baseline $field) -Required
        $right=ConvertTo-ReportText -Value (Get-ReportValue $Current $field) -Required
        if ($left -cne $right) { throw 'Incompatible inventory namespaces or selections.' }
    }
    $scope=ConvertTo-ReportText (Get-ReportValue $Baseline ScopeId) -Required
    $kind=ConvertTo-ReportText (Get-ReportValue $Baseline IdentityKind) -Required
    if ($kind -cnotin @('PowerCliId','MoRefValue')) { throw 'Unsupported identity namespace.' }
    $beforeTime=ConvertTo-ReportInstant (Get-ReportValue $Baseline CapturedAt)
    $afterTime=ConvertTo-ReportInstant (Get-ReportValue $Current CapturedAt)
    if ($afterTime -lt $beforeTime) { throw 'Current capture precedes baseline.' }
    $maps=@();$complete=@()
    foreach ($envelope in @($Baseline,$Current)) {
        $status=ConvertTo-ReportText (Get-ReportValue $envelope Completeness) -Required
        if ($status -cnotin @('Complete','Partial','Unknown')) { throw 'Invalid completeness assertion.' }
        $complete+=($status -ceq 'Complete')
        $inputRows=Get-ReportValue $envelope VMs
        if ($null -eq $inputRows) { throw 'Explicit VMs array is required, including empty inventories.' }
        $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($row in @(Get-ReportRecord $inputRows)) {
            $id=ConvertTo-ReportText (Get-ReportValue $row VMId) -Required
            if ($map.ContainsKey($id)) { throw 'Duplicate VM identity.' }
            $map.Add($id,[pscustomobject]@{
                VM=ConvertTo-ReportText (Get-ReportValue $row VM)
                NumCpu=ConvertTo-ReportNumber (Get-ReportValue $row NumCpu) -Positive -Integer
                MemoryGB=ConvertTo-ReportNumber (Get-ReportValue $row MemoryGB) -Positive
                PowerState=ConvertTo-ReportText (Get-ReportValue $row PowerState)
            })
        }
        $maps+=,$map
    }
    $ids=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($map in $maps) { foreach ($id in $map.Keys) { $null=$ids.Add($id) } }
    $results=@(
        foreach ($id in $ids) {
            $hasBefore=$maps[0].ContainsKey($id); $hasAfter=$maps[1].ContainsKey($id)
            $name=if ($hasAfter) { $maps[1][$id].VM } else { $maps[0][$id].VM }
            if (-not $hasBefore -or -not $hasAfter) {
                $change=if (-not $hasBefore -and $complete[0]) { 'Added' } elseif (-not $hasAfter -and $complete[1]) { 'Removed' } else { 'PresenceUnknown' }
                [pscustomobject]@{ScopeId=$scope;VMId=$id;VM=$name;Change=$change;Field='Presence';Before=$hasBefore;After=$hasAfter;BaselineCapturedAt=$beforeTime;CurrentCapturedAt=$afterTime}
                continue
            }
            foreach ($field in @('NumCpu','MemoryGB','PowerState')) {
                $old=$maps[0][$id].$field; $new=$maps[1][$id].$field
                $comparable=$null -ne $old -and $null -ne $new
                if ($field -eq 'PowerState') { $comparable=$old -in @('PoweredOn','PoweredOff','Suspended') -and $new -in @('PoweredOn','PoweredOff','Suspended') }
                if (-not $comparable -or $old -ne $new) {
                    $change=if ($comparable) { 'Changed' } else { 'NotComparable' }
                    [pscustomobject]@{ScopeId=$scope;VMId=$id;VM=$name;Change=$change;Field=$field;Before=$old;After=$new;BaselineCapturedAt=$beforeTime;CurrentCapturedAt=$afterTime}
                }
            }
        }
    )
    if ($PSBoundParameters.ContainsKey('CsvPath') -and $PSCmdlet.ShouldProcess('new local CSV file','Create inventory comparison')) {
        $csvRows=@(foreach ($result in $results) {
            $safe=[ordered]@{}
            foreach ($property in $result.PSObject.Properties) {
                $value=$property.Value
                if ($value -is [datetimeoffset]) { $value=$value.ToString('o',[cultureinfo]::InvariantCulture) }
                if ($value -is [double]) { $value=$value.ToString('G17',[cultureinfo]::InvariantCulture) }
                if ($value -is [string] -and $value -match '^[\s\p{C}]*[=+@-]') { $value="'$value" }
                $safe[$property.Name]=$value
            }
            [pscustomobject]$safe
        })
        $csv=if ($csvRows.Count) { ($csvRows | ConvertTo-Csv -NoTypeInformation) -join "`n" } else { '"ScopeId","VMId","VM","Change","Field","Before","After","BaselineCapturedAt","CurrentCapturedAt"' }
        $null=Write-ReportFile -Path $CsvPath -Content ($csv+"`n")
    }
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('Inventory comparison failed. No results were emitted.'),'Toolkit.InventoryComparisonFailed',[Management.Automation.ErrorCategory]::InvalidData,$null))
}
$results
