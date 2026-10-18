# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'VCF.Response.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Reporting.Support.psm1') -Scope Local -ErrorAction Stop
function ConvertTo-VCFObservation {
    param([AllowNull()][object]$Value,[string[]]$Allowed)
    if ($null -eq $Value) { return 'Unknown' }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw 'Invalid observation type.' }
    if ($Allowed -and $Value -cnotin $Allowed) { return 'Unknown' }
    $Value
}
function ConvertTo-VCFInteger {
    param([AllowNull()][object]$Value,[long]$Maximum=[int]::MaxValue,[long]$Minimum=0)
    if ($null -eq $Value) { return $null }
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum) { throw 'Invalid integer observation.' }
    $Value
}
function ConvertTo-VCFFlag {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'Unknown' }
    if ($Value -isnot [bool]) { throw 'Invalid boolean observation.' }
    $Value
}
function Read-VCFAlertCollection {
    param([Parameter(Mandatory)][object]$Export)
    $pages=if ($Export -is [array]) { $Export } else { @($Export) }
    if (-not $pages.Count -or $pages.Count -gt 10000) { throw 'Invalid page collection.' }
    $seen=[Collections.Generic.HashSet[long]]::new()
    $total=$null;$size=$null;$expected=$null
    $rows=[Collections.Generic.List[object]]::new()
    foreach ($page in $pages) {
        if ($page -isnot [pscustomobject]) { throw 'Invalid alerts envelope.' }
        Assert-VCFSuccessObject $page
        $alerts=Get-ReportValue $page alerts
        if ($alerts -isnot [array]) { throw 'Explicit alerts array required.' }
        $meta=Get-ReportValue $page pageInfo
        if ($null -eq $meta) { throw 'Complete pageInfo required by this offline profile.' }
        if ($meta -isnot [pscustomobject]) { throw 'Invalid pageInfo.' }
        Assert-VCFSuccessObject $meta
        $number=ConvertTo-VCFInteger (Get-ReportValue $meta page)
        $pageSize=ConvertTo-VCFInteger (Get-ReportValue $meta pageSize) -Minimum 1
        $count=ConvertTo-VCFInteger (Get-ReportValue $meta totalCount)
        if ($null -eq $number -or $null -eq $pageSize -or $null -eq $count) { throw 'Missing pageInfo values.' }
        if ($null -eq $total) { $total=$count;$size=$pageSize;$expected=[Math]::Max(1,[Math]::Ceiling($total/[double]$size)) }
        if ($count -ne $total -or $pageSize -ne $size -or $number -ge $expected -or -not $seen.Add($number)) { throw 'Inconsistent alert pages.' }
        $expectedRows=[Math]::Min($size,[Math]::Max(0,$total-($number*[long]$size)))
        if ($alerts.Count -ne $expectedRows) { throw 'Incomplete alert page.' }
        foreach ($entry in $alerts) {
            if ($entry -isnot [pscustomobject]) { throw 'Invalid alert.' }
            Assert-VCFSuccessObject $entry
        }
    }
    if ($pages.Count -ne $expected) { throw 'Missing alert pages.' }
    foreach ($page in ($pages | Sort-Object { $_.pageInfo.page })) { foreach ($entry in $page.alerts) { $rows.Add($entry) } }
    $rows.ToArray()
}
function Invoke-VCFOfflineAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Lifecycle','Alerts','Licensing')][string]$Kind,
        [Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$SourceVersion)
    $parsed=Read-VCFJson -Path $Path
    $source='SDDC Manager'
    $endpoint=switch ($Kind) { Lifecycle {'/v1/domains'} Alerts {'/suite-api/api/alerts'} Licensing {'/v1/licensing-info/system'} }
    if ($Kind -eq 'Alerts') { $source='VCF Operations';$entries=@(Read-VCFAlertCollection -Export $parsed) }
    elseif ($Kind -eq 'Lifecycle') { $entries=@(if ($parsed -is [array]) { Read-VCFCollection -Pages $parsed } else { Read-VCFPage -Response $parsed }) }
    else {
        # Current SDDC Manager documents a single LicensingInfo, unlike the older VCF API array.
        if ($parsed -isnot [pscustomobject]) { throw 'Single LicensingInfo object required.' }
        Assert-VCFSuccessObject $parsed
        Assert-VCFField -Element $parsed -Field resourceType
        if ($parsed.resourceType -cne 'SYSTEM') { throw 'System licensing scope required.' }
        $entries=@($parsed)
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rows=@(foreach ($entry in $entries) {
        $row=[ordered]@{Source=$source;SourceVersion=$SourceVersion;Endpoint=$endpoint;Mode='Offline';ContractVerifiedForProductVersion=$false;RealVmwareValidated=$false;Assessment='Unknown'}
        switch ($Kind) {
            Lifecycle {
                Assert-VCFField -Element $entry -Field id
                $identity=$entry.id
                $row.DomainId=$entry.id
                $row.Domain=ConvertTo-VCFObservation (Get-ReportValue $entry name)
                $row.DomainStatus=ConvertTo-VCFObservation (Get-ReportValue $entry status) -Allowed @('ACTIVE','ACTIVATING','UPGRADING','DISABLED','ERROR','SKIPPED','DEACTIVATING','EXPANDING','SHRINKING','CREATING')
                $row.UpgradeState=ConvertTo-VCFObservation (Get-ReportValue $entry upgradeState) -Allowed @('AVAILABLE','FAILED')
                $upgrade=Get-ReportValue $entry upgradeStatus
                if ($null -ne $upgrade) {
                    if ($upgrade -isnot [pscustomobject]) { throw 'Invalid upgrade observation.' }
                    Assert-VCFSuccessObject $upgrade
                }
                $row.UpgradeStatus=ConvertTo-VCFObservation (Get-ReportValue $upgrade status) -Allowed @('UP_TO_DATE','SCHEDULED','IN_PROGRESS','READY','AVAILABLE','BLOCKED')
                $row.CompletedResources=ConvertTo-VCFInteger (Get-ReportValue $upgrade completedResources)
                $row.TotalResources=ConvertTo-VCFInteger (Get-ReportValue $upgrade totalResources)
                if ($null -ne $row.CompletedResources -and $null -ne $row.TotalResources -and $row.CompletedResources -gt $row.TotalResources) { throw 'Inconsistent progress.' }
            }
            Alerts {
                Assert-VCFField -Element $entry -Field alertId
                $uuid=[guid]::Empty
                if (-not [guid]::TryParse($entry.alertId,[ref]$uuid)) { throw 'Invalid alert identity.' }
                $identity=$uuid.ToString()
                $row.AlertId=$identity
                $resource=Get-ReportValue $entry resourceId
                if ($null -ne $resource) {
                    if ($resource -isnot [string] -or -not [guid]::TryParse($resource,[ref]$uuid)) { throw 'Invalid resource identity.' }
                    $resource=$uuid.ToString()
                }
                $row.ResourceId=if ($null -eq $resource) {'Unknown'} else {$resource}
                $row.AlertLevel=ConvertTo-VCFObservation (Get-ReportValue $entry alertLevel) -Allowed @('UNKNOWN','NONE','INFORMATION','WARNING','IMMEDIATE','CRITICAL','AUTO')
                $row.AlertStatus=ConvertTo-VCFObservation (Get-ReportValue $entry status) -Allowed @('NEW','ACTIVE','UPDATED','CANCELED')
                $row.ControlState=ConvertTo-VCFObservation (Get-ReportValue $entry controlState) -Allowed @('OPEN','ASSIGNED','SUSPENDED','SUPPRESSED')
                # Units are not stated in the reviewed model: preserve int64, do not guess epoch units.
                $row.StartTimeRaw=ConvertTo-VCFInteger (Get-ReportValue $entry startTimeUTC) -Maximum ([long]::MaxValue)
                $row.UpdateTimeRaw=ConvertTo-VCFInteger (Get-ReportValue $entry updateTimeUTC) -Maximum ([long]::MaxValue)
                $row.TimestampUnit='Unknown'
            }
            Licensing {
                $identity='SYSTEM'
                $row.ResourceType='SYSTEM'
                $row.LicensingMode=ConvertTo-VCFObservation (Get-ReportValue $entry licensingMode) -Allowed @('SUBSCRIPTION','PERPETUAL','MIXED')
                $row.SubscriptionStatus=ConvertTo-VCFObservation (Get-ReportValue $entry subscriptionStatus) -Allowed @('UNSUBSCRIBED','ACTIVE','EXPIRED')
                $row.SubscribedState=ConvertTo-VCFObservation (Get-ReportValue $entry subscribedState) -Allowed @('UNSUBSCRIBED','PARTIALLY_SUBSCRIBED','SUBSCRIBED')
                $row.IsRegistered=ConvertTo-VCFFlag (Get-ReportValue $entry isRegistered)
                $row.IsSubscribed=ConvertTo-VCFFlag (Get-ReportValue $entry isSubscribed)
                $row.DaysRemainingToSubscribe=ConvertTo-VCFInteger (Get-ReportValue $entry daysRemainingToSubscribe) -Minimum ([int]::MinValue)
            }
        }
        if (-not $seen.Add($identity)) { throw 'Duplicate observation identity.' }
        [pscustomobject]$row
    })
    $rows
}
Export-ModuleMember -Function Invoke-VCFOfflineAnalysis
