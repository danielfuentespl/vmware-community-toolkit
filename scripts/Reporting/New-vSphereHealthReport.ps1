# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Create a portable offline HTML report from allowlisted toolkit report data.
.DESCRIPTION
Makes no provider or network calls. Data requires ScopeId and CapturedAt, with optional
VMs, Tools, Snapshots, Datastores, Hosts, Ntp and Certificates arrays. Optional HostSecurity,
HostFirewall, HostSyslog, HostTime and HostAdvancedSettings arrays add configuration observations. Missing collections
are Unknown; empty arrays mean zero provided records. The report is not a health certification.
HTML is encoded, contains no JavaScript or remote assets, and does not serialize raw objects.
.PARAMETER Data
Structured offline envelope. Use only sanitized report models, never live connection objects.
Unknown properties are ignored; allowed values must have plain, documented types.
.PARAMETER OutputPath
New local HTML file in an existing trusted directory. Never overwrites an existing path.
.PARAMETER AsOf
Optional reference instant for snapshot age and certificate dates; defaults to Data.CapturedAt.
.INPUTS
None. Supply the Data parameter explicitly.
.OUTPUTS
PSCustomObject receipt only after a complete file write. WhatIf creates no file or receipt.
.EXAMPLE
./New-vSphereHealthReport.ps1 -Data $offlineData -OutputPath './health.html'
.EXAMPLE
./New-vSphereHealthReport.ps1 -Data $offlineData -OutputPath './health.html' -WhatIf
.NOTES
No PowerCLI installation needed. Static/offline validation only; no VMware compatibility
claim. Metadata and names can remain sensitive; fields are not anonymized. Never put
secrets in display labels. No overwrite switch exists; choose a new path for every report.
See docs/UNIFIED-REPORTING.md for schema, unknowns and future explicit collection design.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateNotNull()][object]$Data,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath,
    [datetimeoffset]$AsOf
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Reporting.Support.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Audit.Support.psm1') -Scope Local -ErrorAction Stop
function ConvertTo-HtmlCell {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'Unknown' }
    if ($Value -is [datetimeoffset]) { $Value=$Value.ToString('o',[cultureinfo]::InvariantCulture) }
    if ($Value -is [double]) { $Value=$Value.ToString('G17',[cultureinfo]::InvariantCulture) }
    [Net.WebUtility]::HtmlEncode([string]$Value)
}
try {
    $scope=ConvertTo-ReportText (Get-ReportValue $Data ScopeId) -Required
    $captured=ConvertTo-ReportInstant (Get-ReportValue $Data CapturedAt)
    if (-not $PSBoundParameters.ContainsKey('AsOf')) { $AsOf=$captured }
    $completeness=ConvertTo-ReportText (Get-ReportValue $Data Completeness)
    if ($completeness -cnotin @('Complete','Partial','Unknown')) { throw 'Invalid completeness label.' }
    $sections=@(
        @{Key='VMs';Title='Virtual machine inventory';Columns=@('VM','VMId','PowerState','NumCpu','MemoryGB','VMHost');Id=@('VMId')},
        @{Key='Tools';Title='VMware Tools (last known)';Columns=@('VM','VMId','PowerState','ToolsVersion','ToolsVersionStatus','ToolsRunningStatus');Id=@('VMId')},
        @{Key='Snapshots';Title='Snapshots and age';Columns=@('VM','VMId','Snapshot','SnapshotId','CreatedUtc','AgeDays','SizeGiB');Id=@('VMId','SnapshotId')},
        @{Key='Datastores';Title='Datastore capacity';Columns=@('Datastore','DatastoreId','Accessible','CapacityGiB','FreeGiB','UsedGiB','UsedPercent');Id=@('DatastoreId')},
        @{Key='Hosts';Title='ESXi host alarm summaries';Columns=@('VMHost','VMHostId','ConnectionState','InMaintenanceMode','AlarmStatus','HardwareHealth');Id=@('VMHostId')},
        @{Key='Ntp';Title='NTP configuration';Columns=@('VMHost','VMHostId','NtpServers','Synchronization');Id=@('VMHostId')},
        @{Key='Certificates';Title='Machine SSL certificate dates';Columns=@('Entity','Scope','CertificateUid','NotBeforeUtc','NotAfterUtc','DaysToExpiry','DateStatus','TrustVerified');Id=@('Entity','CertificateUid')}
    )
    $optionalSections=@(
        @{Key='VCFLifecycle';Title='SDDC Manager lifecycle observations (offline)';Columns=@('Source','SourceVersion','Endpoint','Domain','DomainId','DomainStatus','UpgradeState','UpgradeStatus','CompletedResources','TotalResources','Assessment');Id=@('DomainId')},
        @{Key='VCFOperationsAlerts';Title='VCF Operations alert observations (offline)';Columns=@('Source','SourceVersion','Endpoint','AlertId','ResourceId','AlertLevel','AlertStatus','ControlState','TimestampUnit','Assessment');Id=@('AlertId')},
        @{Key='VCFLicensing';Title='SDDC Manager licensing observations (offline)';Columns=@('Source','SourceVersion','Endpoint','ResourceType','LicensingMode','SubscriptionStatus','SubscribedState','IsRegistered','IsSubscribed','DaysRemainingToSubscribe','Assessment');Id=@('ResourceType')},
        @{Key='ToolkitExecution';Title='Toolkit execution status';Columns=@('Check','Requested','Status','State','RowCount','Reason');Id=@('Check')},
        @{Key='HostSecurity';Title='ESXi security configuration observations';Columns=@('VMHost','VMHostId','LockdownMode','ServiceKey','ServiceRunning','ServicePolicy','Assessment');Id=@('VMHostId','ServiceKey')},
        @{Key='HostFirewall';Title='ESXi firewall exception observations';Columns=@('VMHost','VMHostId','RuleUid','RuleName','Enabled','IncomingPorts','OutgoingPorts','Protocols','ServiceRunning','Observation','Assessment');Id=@('VMHostId','RuleUid')},
        @{Key='HostSyslog';Title='ESXi syslog configuration observations';Columns=@('VMHost','VMHostId','SettingName','SettingType','Value','ValueState','DeliveryVerified','Assessment');Id=@('VMHostId','SettingName')},
        @{Key='HostTime';Title='ESXi time configuration observations';Columns=@('VMHost','VMHostId','NtpServers','TimeZoneKey','GmtOffsetSeconds','ReportedProtocol','TimeServiceEnabled','ReportedServiceSync','LastSyncUtc','IndependentSyncVerified','Assessment');Id=@('VMHostId')},
        @{Key='HostAdvancedSettings';Title='ESXi advanced-setting observations';Columns=@('VMHost','VMHostId','SettingName','SettingType','Value','ValueState','Assessment');Id=@('VMHostId','SettingName')}
    )
    foreach ($definition in $optionalSections) {
        $present=if ($Data -is [Collections.IDictionary]) { $Data.Keys -contains $definition.Key } else { $null -ne $Data.PSObject.Properties[$definition.Key] }
        if ($present) { $sections+=,$definition }
    }
    $html=[Text.StringBuilder]::new()
    $null=$html.AppendLine('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; base-uri ''none''; form-action ''none''"><title>vSphere offline health report</title><style>*{box-sizing:border-box}body{font-family:system-ui,sans-serif;margin:0 auto;padding:2rem;max-width:1600px;color:#17243a;background:#fafbfd;line-height:1.5}table{border-collapse:separate;border-spacing:0;width:100%;font-size:.9rem}th,td{border-bottom:1px solid #cdd7e3;padding:.65rem;text-align:left;overflow-wrap:anywhere;min-width:8rem}th{background:#e4edf7;position:sticky;top:0}tbody tr:nth-child(even){background:#f0f4f9}section{margin:2rem 0;padding:1rem;background:white;border:1px solid #cdd7e3;border-radius:.5rem;scroll-margin-top:1rem}.table-scroll{overflow:auto;max-height:65vh;border:1px solid #cdd7e3}h1,h2{color:#12385d}.notice{padding:1rem;border-left:4px solid #557999;background:#edf3fa}nav ul{display:flex;flex-wrap:wrap;gap:.6rem;list-style:none;padding:0}a{color:#154c7c}nav a{display:block;background:#e4edf7;padding:.4rem .7rem;border-radius:.3rem}.summary{display:flex;flex-wrap:wrap;gap:1rem}.summary p{flex:1 1 12rem;background:#edf3fa;padding:1rem;margin:0}a:focus,.table-scroll:focus{outline:3px solid #154c7c;outline-offset:3px}@media(max-width:600px){body{padding:.8rem}h1{font-size:1.6rem}section{padding:.6rem}th,td{padding:.45rem}}@media print{.table-scroll{max-height:none;overflow:visible}nav{display:none}th{position:static}}</style></head><body><h1>vSphere offline health report</h1>')
    $null=$html.AppendLine('<p class="notice">Local data rendering only. Real VMware validation: Not performed. Alarm summaries do not certify hardware health; NTP configuration does not establish synchronization; certificate dates do not verify trust. Missing values are Unknown. Counts refer to provided rows.</p>')
    $null=$html.AppendLine("<p>Scope: $(ConvertTo-HtmlCell $scope)<br>Captured UTC: $(ConvertTo-HtmlCell $captured)<br>As of UTC: $(ConvertTo-HtmlCell $AsOf.ToUniversalTime())<br>Caller-declared completeness: $(ConvertTo-HtmlCell $completeness)</p>")
    $runOutcome=Get-ReportValue $Data ToolkitOutcome
    if ($null -ne $runOutcome) {
        $runOutcome=ConvertTo-ReportText $runOutcome
        if ($runOutcome -cnotin @('Completed','Incomplete','PartialFailure','Failed')) { $runOutcome='Unknown' }
        $null=$html.AppendLine("<p class=""notice"">Toolkit execution outcome: $(ConvertTo-HtmlCell $runOutcome). Execution is distinct from compliance or health. Failed, incomplete and not-run checks are listed below.</p>")
    }
    $available=0;$empty=0;$unknown=0
    foreach ($definition in $sections) {
        $collection=Get-ReportValue $Data $definition.Key
        if ($null -eq $collection) { $unknown++ } elseif (@(Get-ReportRecord $collection).Count -eq 0) { $empty++ } else { $available++ }
    }
    $null=$html.AppendLine("<h2>Executive summary</h2><div class=""summary""><p>Sections with provided rows: $available</p><p>Empty collections: $empty</p><p>Unknown collections: $unknown</p></div><p>Availability describes supplied collections, not completeness of individual fields or infrastructure health. Empty collections do not prove compliance.</p>")
    $execution=Get-ReportValue $Data ToolkitExecution
    if ($null -ne $execution) {
        $counts=@{Success=0;Failed=0;Unknown=0;NotRun=0}
        foreach ($entry in @(Get-ReportRecord $execution)) {
            $requested=Get-ReportValue $entry Requested
            if ($requested -isnot [bool] -or -not $requested) { continue }
            $status=ConvertTo-ReportText (Get-ReportValue $entry Status)
            $label=switch ($status) { Completed {'Success'} Empty {'Success'} Failed {'Failed'} NotRun {'NotRun'} default {'Unknown'} }
            $counts[$label]++
        }
        $null=$html.AppendLine("<p>Requested checks: Success $($counts.Success), Failed $($counts.Failed), Unknown $($counts.Unknown), NotRun $($counts.NotRun). Success describes execution only.</p>")
    }
    $null=$html.AppendLine('<nav aria-label="Report sections"><ul>')
    foreach ($definition in $sections) { $null=$html.AppendLine("<li><a href=""#section-$($definition.Key)"">$($definition.Title)</a></li>") }
    $null=$html.AppendLine('</ul></nav>')
    foreach ($section in $sections) {
        $raw=Get-ReportValue $Data $section.Key
        $null=$html.AppendLine("<section id=""section-$($section.Key)""><h2>$($section.Title)</h2>")
        if ($null -eq $raw) { $null=$html.AppendLine('<p>Unknown &mdash; collection not provided.</p></section>');continue }
        $rows=@(Get-ReportRecord $raw)
        $null=$html.AppendLine("<p>Provided rows: $($rows.Count)</p>")
        if (-not $rows.Count) { $null=$html.AppendLine('<p>No records in provided collection.</p></section>');continue }
        $null=$html.AppendLine("<div class=""table-scroll"" role=""region"" tabindex=""0"" aria-label=""$($section.Title) table""><table><thead><tr>")
        foreach ($column in $section.Columns) { $null=$html.AppendLine("<th scope=""col"">$column</th>") }
        $null=$html.AppendLine('</tr></thead><tbody>')
        $cpuTotal=0.0;$memoryTotal=0.0;$cpuKnown=$true;$memoryKnown=$true
        $states=@{PoweredOn=0;PoweredOff=0;Suspended=0;Unknown=0}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $rows) {
            $projected=[ordered]@{}
            foreach ($column in $section.Columns) { $projected[$column]=$null }
            # Only explicit text columns are read; unknown fields, credentials and nested data are never serialized.
            foreach ($column in @('VM','VMId','PowerState','VMHost','Snapshot','SnapshotId','ToolsVersion','ToolsVersionStatus','ToolsRunningStatus','Datastore','DatastoreId','VMHostId','ConnectionState','Entity','Scope','CertificateUid','ServiceKey','ServicePolicy','RuleUid','RuleName','IncomingPorts','OutgoingPorts','Protocols','Observation','SettingName','SettingType','TimeZoneKey','ReportedProtocol','Check','Reason')) {
                if ($projected.Contains($column)) { $projected[$column]=ConvertTo-ReportText (Get-ReportValue $row $column) }
            }
            switch ($section.Key) {
                {$_ -cin @('VCFLifecycle','VCFOperationsAlerts','VCFLicensing')} {
                    $expectedSource=if ($section.Key -eq 'VCFOperationsAlerts') {'VCF Operations'} else {'SDDC Manager'}
                    if ((Get-ReportValue $row Source) -cne $expectedSource) { throw 'Explicit VCF source required.' }
                    $projected.Source=$expectedSource
                    $projected.SourceVersion=ConvertTo-ReportText (Get-ReportValue $row SourceVersion) -Required
                    $projected.Endpoint=switch ($section.Key) { VCFLifecycle {'/v1/domains'} VCFOperationsAlerts {'/suite-api/api/alerts'} VCFLicensing {'/v1/licensing-info/system'} }
                    foreach ($field in @('Domain','DomainId','DomainStatus','UpgradeState','UpgradeStatus','AlertId','ResourceId','AlertLevel','AlertStatus','ControlState','ResourceType','LicensingMode','SubscriptionStatus','SubscribedState')) {
                        if ($projected.Contains($field)) { $projected[$field]=ConvertTo-ReportText (Get-ReportValue $row $field) }
                    }
                    foreach ($field in @('CompletedResources','TotalResources','DaysRemainingToSubscribe')) {
                        if ($projected.Contains($field)) { $projected[$field]=ConvertTo-AuditInteger (Get-ReportValue $row $field) -Signed:($field -eq 'DaysRemainingToSubscribe') }
                    }
                    if ($section.Key -eq 'VCFLifecycle' -and $projected.CompletedResources -is [int] -and $projected.TotalResources -is [int] -and $projected.CompletedResources -gt $projected.TotalResources) { throw 'Inconsistent lifecycle counters.' }
                    foreach ($field in @('IsRegistered','IsSubscribed')) {
                        if ($projected.Contains($field)) {
                            $flag=Get-ReportValue $row $field
                            $projected[$field]=if ($flag -is [string] -and $flag -ceq 'Unknown') {'Unknown'} else {ConvertTo-AuditBoolean $flag}
                        }
                    }
                    if ($projected.Contains('TimestampUnit')) { $projected.TimestampUnit='Unknown' }
                    $projected.Assessment='Unknown'
                }
                VMs {
                    $projected.NumCpu=ConvertTo-ReportNumber (Get-ReportValue $row NumCpu) -Positive -Integer
                    $projected.MemoryGB=ConvertTo-ReportNumber (Get-ReportValue $row MemoryGB) -Positive
                    if ($null -eq $projected.NumCpu) { $cpuKnown=$false } else { $cpuTotal+=$projected.NumCpu }
                    if ($null -eq $projected.MemoryGB) { $memoryKnown=$false } else { $memoryTotal+=$projected.MemoryGB }
                    if (-not [double]::IsFinite($cpuTotal) -or -not [double]::IsFinite($memoryTotal)) { throw 'Inventory aggregate overflow.' }
                    $state=$projected.PowerState
                    if ($states.ContainsKey($state) -and $state -ne 'Unknown') { $states[$state]++ } else { $states.Unknown++ }
                }
                Snapshots {
                    $date=Get-ReportValue $row CreatedUtc
                    if ($null -eq $date) { $date=Get-ReportValue $row Created }
                    if ($null -ne $date) {
                        $created=ConvertTo-ReportInstant $date
                        $age=($AsOf.ToUniversalTime()-$created).TotalDays
                        if ($age -lt 0) { throw 'Snapshot timestamp exceeds AsOf.' }
                        $projected.CreatedUtc=$created;$projected.AgeDays=$age
                    }
                    $size=Get-ReportValue $row SizeGiB
                    if ($null -eq $size) { $size=Get-ReportValue $row SizeGB }
                    $projected.SizeGiB=ConvertTo-ReportNumber $size
                }
                Datastores {
                    $accessible=Get-ReportValue $row Accessible
                    if ($null -ne $accessible -and $accessible -isnot [bool]) { throw 'Invalid accessibility.' }
                    $projected.Accessible=$accessible
                    if ($accessible -eq $true) {
                        $cap=ConvertTo-ReportNumber (Get-ReportValue $row CapacityGiB)
                        $free=ConvertTo-ReportNumber (Get-ReportValue $row FreeGiB)
                        $projected.CapacityGiB=$cap;$projected.FreeGiB=$free
                        if ($null -ne $cap -and $null -ne $free) {
                            if ($free -gt $cap) { throw 'Invalid datastore sizes.' }
                            $projected.UsedGiB=$cap-$free
                            if ($cap -gt 0) { $projected.UsedPercent=(($cap-$free)/$cap)*100 }
                        }
                    }
                }
                Hosts {
                    $maintenance=Get-ReportValue $row InMaintenanceMode
                    if ($null -ne $maintenance -and $maintenance -isnot [bool]) { throw 'Invalid maintenance state.' }
                    $projected.InMaintenanceMode=$maintenance
                    $alarm=ConvertTo-ReportText (Get-ReportValue $row AlarmStatus)
                    $projected.AlarmStatus=if ($alarm -cin @('green','yellow','red','gray')) { $alarm } else { 'Unknown' }
                    $projected.HardwareHealth='NotEvaluated'
                }
                Ntp {
                    $servers=Get-ReportValue $row NtpServers
                    if ($null -ne $servers) {
                        if ($servers -isnot [array]) { throw 'NTP servers must be an array.' }
                        $names=@(foreach ($serverName in $servers) { ConvertTo-ReportText $serverName -Required })
                        $projected.NtpServers=if ($names.Count) { $names -join ', ' } else { '(none configured)' }
                    }
                    $projected.Synchronization='NotEvaluated'
                }
                ToolkitExecution {
                    $status=ConvertTo-ReportText (Get-ReportValue $row Status)
                    $projected.Status=if ($status -cin @('Completed','Empty','Incomplete','Failed','NotRun')) { $status } else { 'Unknown' }
                     $projected.State=switch ($projected.Status) { Completed {'Success'} Empty {'Success'} Failed {'Failed'} NotRun {'NotRun'} default {'Unknown'} }
                    $projected.Requested=ConvertTo-AuditBoolean (Get-ReportValue $row Requested)
                    $projected.RowCount=ConvertTo-ReportNumber (Get-ReportValue $row RowCount) -Integer
                }
                HostSecurity {
                    $mode=ConvertTo-ReportText (Get-ReportValue $row LockdownMode)
                    $projected.LockdownMode=if ($mode -cin @('lockdownDisabled','lockdownNormal','lockdownStrict')) { $mode } else { 'Unknown' }
                    $flag=Get-ReportValue $row ServiceRunning
                    $projected.ServiceRunning=if ($flag -is [string] -and $flag -ceq 'Unknown') { 'Unknown' } else { ConvertTo-AuditBoolean $flag }
                    $projected.Assessment='NotEvaluated'
                }
                HostFirewall {
                    foreach ($field in @('Enabled','ServiceRunning')) {
                        $flag=Get-ReportValue $row $field
                        $projected[$field]=if ($flag -is [string] -and $flag -ceq 'Unknown') { 'Unknown' } else { ConvertTo-AuditBoolean $flag }
                    }
                    $projected.Assessment='NotEvaluated'
                }
                { $_ -cin @('HostSyslog','HostAdvancedSettings') } {
                    $state=ConvertTo-ReportText (Get-ReportValue $row ValueState)
                    if ($state -cnotin @('Unknown','Withheld','Reported')) { throw 'Invalid setting observation state.' }
                    $safe=if ($state -eq 'Reported') { Get-AuditSafeSetting -SettingName $projected.SettingName -Setting $row } else { [pscustomobject]@{Value=if ($state -eq 'Withheld') {'[Withheld]'} else {'Unknown'};ValueState=$state} }
                    $projected.ValueState=$safe.ValueState
                    $value=$safe.Value
                    if ($value -is [string] -and $value.Length -eq 0) { $value='(empty)' }
                    $projected.Value=$value
                    $projected.Assessment='NotEvaluated'
                    if ($section.Key -eq 'HostSyslog') { $projected.DeliveryVerified=$false }
                }
                HostTime {
                    $servers=Get-ReportValue $row NtpServers
                    if ($null -ne $servers) {
                        if ($servers -isnot [array]) { throw 'NTP servers must be an array.' }
                        $names=@(foreach ($serverName in $servers) { ConvertTo-ReportText $serverName -Required })
                        $projected.NtpServers=if ($names.Count) { $names -join ', ' } else { '(none configured)' }
                    }
                    $offset=Get-ReportValue $row GmtOffsetSeconds
                    $projected.GmtOffsetSeconds=if ($offset -is [string] -and $offset -ceq 'Unknown') { 'Unknown' } else { ConvertTo-AuditInteger $offset -Signed }
                    foreach ($field in @('TimeServiceEnabled','ReportedServiceSync')) {
                        $flag=Get-ReportValue $row $field
                        $projected[$field]=if ($flag -is [string] -and $flag -ceq 'Unknown') { 'Unknown' } else { ConvertTo-AuditBoolean $flag }
                    }
                    $last=Get-ReportValue $row LastSyncUtc
                    if ($null -ne $last) { $projected.LastSyncUtc=ConvertTo-ReportInstant $last }
                    $projected.IndependentSyncVerified=$false;$projected.Assessment='NotEvaluated'
                }
                Certificates {
                    $before=Get-ReportValue $row NotBeforeUtc;$after=Get-ReportValue $row NotAfterUtc
                    if ($null -ne $before) { $projected.NotBeforeUtc=ConvertTo-ReportInstant $before }
                    if ($null -ne $after) { $projected.NotAfterUtc=ConvertTo-ReportInstant $after }
                    if ($null -ne $before -and $null -ne $after) {
                        if ($projected.NotAfterUtc -le $projected.NotBeforeUtc) { throw 'Invalid certificate interval.' }
                        $remaining=($projected.NotAfterUtc-$AsOf.ToUniversalTime()).TotalDays
                        $projected.DaysToExpiry=$remaining
                        $projected.DateStatus=if ($remaining -le 0) { 'Expired' } elseif ($projected.NotBeforeUtc -gt $AsOf.ToUniversalTime()) { 'NotYetValid' } else { 'WithinDateWindow' }
                    }
                    $projected.TrustVerified=$false
                }
            }
            $identity=@(foreach ($field in $section.Id) { $projected[$field] })
            if ($identity -notcontains 'Unknown' -and $identity -notcontains $null) {
                $key=ConvertTo-Json -InputObject $identity -Compress
                if (-not $seen.Add($key)) { throw 'Duplicate report identity.' }
            }
            $null=$html.AppendLine('<tr>')
            foreach ($column in $section.Columns) { $null=$html.AppendLine("<td>$(ConvertTo-HtmlCell $projected[$column])</td>") }
            $null=$html.AppendLine('</tr>')
        }
        $null=$html.AppendLine('</tbody></table></div>')
        if ($section.Key -eq 'VMs') {
            $cpu=if ($cpuKnown) { $cpuTotal } else { $null }
            $memory=if ($memoryKnown) { $memoryTotal } else { $null }
            $null=$html.AppendLine("<p>Provided VM summary: CPU total $(ConvertTo-HtmlCell $cpu); memory total GiB $(ConvertTo-HtmlCell $memory). Power states: PoweredOn $($states.PoweredOn), PoweredOff $($states.PoweredOff), Suspended $($states.Suspended), Unknown $($states.Unknown). Totals are Unknown when any contributing value is missing.</p>")
        }
        $null=$html.AppendLine('</section>')
    }
    $null=$html.AppendLine('</body></html>')
    if ($PSCmdlet.ShouldProcess('new local HTML file','Create offline vSphere report')) {
        $path=Write-ReportFile -Path $OutputPath -Content $html.ToString()
        [pscustomobject]@{Path=$path;Mode='OfflineRendering';AsOfUtc=$AsOf.ToUniversalTime();RealVmwareValidated=$false}
    }
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('HTML report generation failed. No success receipt was emitted.'),'Toolkit.HealthReportFailed',[Management.Automation.ErrorCategory]::InvalidData,$null))
}
