# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Reporting.Support.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Snapshot.Support.psm1') -Scope Local -ErrorAction Stop
function Get-ToolkitReadCatalog {
    # Fixed local scripts only. Never add a path parameter or a modifying tool.
    [ordered]@{
        VMInventory=@{Path='Reporting/Get-VMInventory.ps1';Key='VMs';Identity=@('VMId');Evidence=@('VM','NumCpu','MemoryGB','PowerState')}
        Tools=@{Path='Reporting/Get-VMwareToolsStatus.ps1';Key='Tools';Identity=@('VMId');Evidence=@('ToolsVersion','ToolsVersionStatus','ToolsRunningStatus')}
        Snapshots=@{Path='Reporting/Get-SnapshotReport.ps1';Key='Snapshots';Identity=@('VMId','SnapshotId');Evidence=@('Created','SizeGB')}
        OldSnapshots=@{Path='Reporting/Get-OldSnapshots.ps1';Key='';Identity=@('VMId','SnapshotId');Evidence=@('CreatedUtc','AgeDays','SizeGiB')}
        Datastores=@{Path='Storage/Get-DatastoreCapacity.ps1';Key='Datastores';Identity=@('DatastoreId');Evidence=@('CapacityGiB','FreeGiB','UsedGiB')}
        HostHealth=@{Path='Health/Get-VMHostHealth.ps1';Key='Hosts';Identity=@('VMHostId');Evidence=@('AlarmStatus','ConnectionState')}
        Dns=@{Path='Reporting/Get-VMHostDnsReport.ps1';Key='';Identity=@('VMHost');Evidence=@('DomainName')}
        Ntp=@{Path='Network/Get-VMHostNtpConfiguration.ps1';Key='Ntp';Identity=@('VMHostId');Evidence=@('NtpServers')}
        Certificates=@{Path='Security/Get-VMCertificateExpiry.ps1';Key='Certificates';Identity=@('Scope','Entity','CertificateUid');Evidence=@('NotBeforeUtc','NotAfterUtc')}
        HostSecurity=@{Path='Security/Get-VMHostSecurityConfiguration.ps1';Key='HostSecurity';Identity=@('VMHostId','ServiceKey');Evidence=@('LockdownMode','ServiceRunning','ServicePolicy')}
        Firewall=@{Path='Network/Get-VMHostFirewallReport.ps1';Key='HostFirewall';Identity=@('VMHostId','RuleUid');Evidence=@('Enabled','Protocols')}
        Syslog=@{Path='Logging/Get-VMHostSyslogConfiguration.ps1';Key='HostSyslog';Identity=@('VMHostId','SettingName');Evidence=@('ValueState')}
        Time=@{Path='Network/Get-VMHostTimeConfiguration.ps1';Key='HostTime';Identity=@('VMHostId');Evidence=@('TimeZoneKey','ReportedProtocol','TimeServiceEnabled','ReportedServiceSync')}
        AdvancedSettings=@{Path='Security/Get-VMHostAdvancedSettings.ps1';Key='HostAdvancedSettings';Identity=@('VMHostId','SettingName');Evidence=@('ValueState')}
    }
}
function Get-ToolkitProfileCatalog {
    $catalog=Get-ToolkitReadCatalog
    [ordered]@{
        Inventory=@('VMInventory','Tools','Datastores')
        Operations=@('VMInventory','Tools','Snapshots','OldSnapshots','Datastores','HostHealth','Dns','Ntp','Time')
        Security=@('Certificates','HostSecurity','Firewall','Syslog','Time','AdvancedSettings')
        All=@($catalog.Keys)
    }
}
function Get-ToolkitDiscovery {
    param([ValidateSet('Checks','Profiles')][string]$Kind)
    if ($Kind -eq 'Profiles') {
        $profiles=Get-ToolkitProfileCatalog
        foreach ($name in $profiles.Keys) { [pscustomobject]@{Profile=$name;Checks=@($profiles[$name]);ReadOnly=$true} }
    } else {
        $catalog=Get-ToolkitReadCatalog
        foreach ($name in $catalog.Keys) { [pscustomobject]@{Check=$name;ReportKey=$catalog[$name].Key;ReadOnly=$true;DirectESXi=($name -ne 'Certificates')} }
    }
}
function Add-ToolkitStatePresentation {
    param([object[]]$States)
    foreach ($item in $States) {
        $state=switch ($item.Status) { Completed {'Success'} Empty {'Success'} Failed {'Failed'} NotRun {'NotRun'} default {'Unknown'} }
        $message=switch ($item.Reason) {
            UnsupportedEndpoint {'This check requires vCenter; direct ESXi is unsupported.'}
            StoppedAfterFailure {'Not executed because an earlier check failed.'}
            NotSelected {'Not selected.'}
            RowLimitExceeded {'Row budget exceeded; narrow filters or review the configured limits.'}
            {$_ -in @('CheckFailed','SharedSourceFailed')} {'Check failed; verify connection, permissions and required commands privately.'}
            default { switch ($item.Status) {
                Empty {'No rows returned. Inventory visibility remains unverified.'}
                Incomplete {'Some fields are missing, unknown or withheld.'}
                default {'Read completed. This does not establish health or compliance.'}
            } }
        }
        $item | Add-Member -NotePropertyName State -NotePropertyValue $state -Force
        $item | Add-Member -NotePropertyName Message -NotePropertyValue $message -Force
    }
}
function Resolve-ToolkitReadPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $root=Split-Path $PSScriptRoot -Parent
    $path=[IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)) { throw 'Toolkit.UntrustedPath' }
    $file=[IO.FileInfo]::new($path)
    if (-not $file.Exists) { throw 'Toolkit.ScriptUnavailable' }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Toolkit.UntrustedPath' }
    $parent=$file.Directory
    while ($null -ne $parent) {
        if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Toolkit.UntrustedPath' }
        $parent=$parent.Parent
    }
    $path
}
function Invoke-ToolkitReadCheck {
    param([Parameter(Mandatory)][string]$Check,[Parameter(Mandatory)][hashtable]$Arguments,[Parameter(Mandatory)][int]$Limit)
    $catalog=Get-ToolkitReadCatalog
    if (-not $catalog.Contains($Check)) { throw 'Toolkit.UnknownCheck' }
    $path=Resolve-ToolkitReadPath $catalog[$Check].Path
    $buffer=[Collections.Generic.List[object]]::new()
    & $path @Arguments 3>$null 4>$null 5>$null 6>$null | ForEach-Object {
        if ($buffer.Count -ge $Limit) { throw 'Toolkit.RowLimitExceeded' }
        if ($null -eq $_ -or $_ -isnot [pscustomobject]) { throw 'Toolkit.InvalidResult' }
        $buffer.Add($_)
    }
    $buffer.ToArray()
}
function Get-ToolkitObservationStatus {
    param([string]$Check,[AllowEmptyCollection()][object[]]$Rows,[hashtable]$Definition)
    if (-not $Rows.Count) { return 'Empty' }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $incomplete=$false
    foreach ($row in $Rows) {
        if ($null -eq $row -or $row -isnot [pscustomobject]) { throw 'Toolkit.InvalidResult' }
        foreach ($property in $row.PSObject.Properties) {
            $value=$property.Value
            if ($value -is [pscredential] -or $value -is [Security.SecureString]) { throw 'Toolkit.InvalidResult' }
            if (($value -is [double] -or $value -is [single]) -and -not [double]::IsFinite([double]$value)) { throw 'Toolkit.InvalidResult' }
            if ($null -eq $value -or ($value -is [string] -and $value -ceq 'Unknown')) { $incomplete=$true }
        }
        $ids=@(foreach ($field in $Definition.Identity) { Get-ReportValue $row $field })
        foreach ($id in $ids) {
            if ($null -eq $id -or ($id -is [string] -and [string]::IsNullOrWhiteSpace($id))) { $incomplete=$true }
            elseif ($id -isnot [string]) { throw 'Toolkit.InvalidResult' }
        }
        if ($ids -notcontains $null -and $ids -cnotcontains 'Unknown') {
            $identity=ConvertTo-Json -InputObject $ids -Compress
            if (-not $seen.Add($identity)) { throw 'Toolkit.DuplicateResult' }
        } else { $incomplete=$true }
        foreach ($field in $Definition.Evidence) {
            $value=Get-ReportValue $row $field
            if ($null -eq $value -or ($value -is [string] -and ($value -ceq 'Unknown' -or [string]::IsNullOrWhiteSpace($value)))) { $incomplete=$true }
        }
        if ($Check -in @('Syslog','AdvancedSettings') -and (Get-ReportValue $row ValueState) -ne 'Reported') { $incomplete=$true }
    }
    if ($incomplete) { 'Incomplete' } else { 'Completed' }
}
function Invoke-ToolkitRun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][object]$Server,[Parameter(Mandatory)][ValidateSet('vCenter','ESXi')][string]$EndpointType,
        [Parameter(Mandatory)][string]$ScopeId,[Alias('Profile')][ValidateSet('Inventory','Operations','Security','All')][string]$CheckProfile='Inventory',
        [string[]]$Checks,[string[]]$VMName=@('*'),[string[]]$VMHostName=@('*'),[string[]]$DatastoreName=@('*'),[string[]]$RuleName=@('*'),
        [string[]]$SettingName=@('Syslog.global.logHost','Syslog.global.logDir','Syslog.global.logDirUnique','Syslog.global.defaultRotate','Syslog.global.defaultSize'),
        [ValidateSet('VMHost','VCenter')][string]$CertificateScope='VMHost',[double]$OlderThanDays=7,[datetimeoffset]$AsOf=[datetimeoffset]::UtcNow,[TimeZoneInfo]$UnspecifiedTimeZone,
        [int]$MaxRowsPerCheck=10000,[int]$MaxTotalRows=50000,[switch]$ContinueOnError,[string]$HtmlPath
    )
    Assert-ToolkitConnection $Server
    $catalog=Get-ToolkitReadCatalog
    $profiles=Get-ToolkitProfileCatalog
    $selection=if ($PSBoundParameters.ContainsKey('Checks')) { $Checks } else { $profiles[$CheckProfile] }
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($check in $selection) { if (-not $catalog.Contains($check) -or -not $selected.Add($check)) { throw 'Select unique allowlisted checks.' } }
    $started=[datetimeoffset]::UtcNow
    $syslogKeys=@('Syslog.global.logHost','Syslog.global.logDir','Syslog.global.logDirUnique','Syslog.global.defaultRotate','Syslog.global.defaultSize')
    $cache=@{};$sourceErrors=@{};$states=[ordered]@{};$retained=0;$sourceCalls=0;$halted=$false
    foreach ($check in $catalog.Keys) {
        $states[$check]=[pscustomobject]@{Check=$check;Requested=$selected.Contains($check);Status='NotRun';RowCount=0;Reason='NotSelected';Source=$check}
    }
    foreach ($check in $catalog.Keys) {
        if (-not $selected.Contains($check)) { continue }
        $state=$states[$check]
        if ($check -eq 'Certificates' -and $EndpointType -eq 'ESXi') { $state.Reason='UnsupportedEndpoint';continue }
        if ($halted -and -not $cache.ContainsKey($check)) { if ($state.Status -eq 'NotRun') { $state.Reason='StoppedAfterFailure' };continue }
        $source=$check
        if ($check -eq 'OldSnapshots') { $source='Snapshots' }
        if ($check -eq 'Ntp' -and $selected.Contains('Time')) { $source='Time' }
        if ($check -eq 'Syslog' -or $check -eq 'AdvancedSettings') { $source='AdvancedSettings' }
        $state.Source=$source
        try {
            if ($sourceErrors.ContainsKey($source)) { throw 'Toolkit.DependencyFailed' }
            if (-not $cache.ContainsKey($source)) {
                $invokeParameters=@{Server=$Server;ErrorAction='Stop';WarningAction='Stop'}
                switch ($source) {
                    {$_ -in @('VMInventory','Snapshots')} { $invokeParameters.Name=$VMName;$invokeParameters.IncludeIdentity=$true }
                    Tools { $invokeParameters.Name=$VMName }
                    Datastores { $invokeParameters.Name=$DatastoreName }
                    default { $invokeParameters.Name=$VMHostName }
                }
                if ($source -eq 'Certificates') { $invokeParameters.EndpointType=$EndpointType;$invokeParameters.Scope=$CertificateScope;$invokeParameters.AsOf=$AsOf;$invokeParameters.UnspecifiedTimeZone=$UnspecifiedTimeZone;if ($CertificateScope -eq 'VCenter') { $invokeParameters.Remove('Name') } }
                if ($source -eq 'Firewall') { $invokeParameters.RuleName=$RuleName }
                if ($source -eq 'Time') { $invokeParameters.UnspecifiedTimeZone=$UnspecifiedTimeZone }
                if ($source -eq 'AdvancedSettings') {
                    $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    if ($selected.Contains('Syslog')) { foreach ($key in $syslogKeys) { $null=$keys.Add($key) } }
                    if ($selected.Contains('AdvancedSettings')) { foreach ($key in $SettingName) { $null=$keys.Add($key) } }
                    $invokeParameters.SettingName=@($keys)
                }
                if ($retained -ge $MaxTotalRows) { throw 'Toolkit.RowLimitExceeded' }
                $sourceCalls++
                $sourceRows=@(Invoke-ToolkitReadCheck -Check $source -Arguments $invokeParameters -Limit ([Math]::Min($MaxRowsPerCheck,[Math]::Max(1,$MaxTotalRows-$retained))))
                if ($sourceRows.Count -gt $MaxRowsPerCheck -or $sourceRows.Count+$retained -gt $MaxTotalRows) { throw 'Toolkit.RowLimitExceeded' }
                if ($source -eq 'Snapshots') {
                    $sourceRows=@(foreach ($row in $sourceRows) {
                        $created=Get-ReportValue $row Created
                        if ($null -ne $created) { $created=ConvertTo-ToolkitInstant -Value $created -UnspecifiedTimeZone $UnspecifiedTimeZone }
                        [pscustomobject]@{VIServer=Get-ReportValue $row VIServer;VMId=Get-ReportValue $row VMId;VM=Get-ReportValue $row VM;SnapshotId=Get-ReportValue $row SnapshotId;Snapshot=Get-ReportValue $row Snapshot;Created=$created;SizeGB=Get-ReportValue $row SizeGB}
                    })
                }
                $sourceStatus=Get-ToolkitObservationStatus -Check $source -Rows $sourceRows -Definition $catalog[$source]
                $cache[$source]=$sourceRows;$retained+=$sourceRows.Count
                if (-not $states[$source].Requested) {
                    $states[$source].Status=$sourceStatus;$states[$source].RowCount=$sourceRows.Count;$states[$source].Reason='Dependency'
                }
            }
            $rows=$cache[$source]
            if ($check -eq 'OldSnapshots') {
                $rows=@(ConvertTo-ToolkitOldSnapshot -Snapshot $rows -OlderThanDays $OlderThanDays -AsOf $AsOf -UnspecifiedTimeZone $UnspecifiedTimeZone)
            } elseif ($check -eq 'Ntp' -and $source -eq 'Time') {
                $rows=@(foreach ($row in $rows) { [pscustomobject]@{VIServer=$row.VIServer;VMHostId=$row.VMHostId;VMHost=$row.VMHost;NtpServers=$row.NtpServers;Synchronization='NotEvaluated'} })
            } elseif ($check -eq 'Syslog') {
                $rows=@(foreach ($row in $rows) { if ($row.SettingName -in $syslogKeys) { [pscustomobject]@{VIServer=$row.VIServer;VMHostId=$row.VMHostId;VMHost=$row.VMHost;SettingName=$row.SettingName;SettingType=$row.SettingType;Value=$row.Value;ValueState=$row.ValueState;Assessment='NotEvaluated';DeliveryVerified=$false} } })
            } elseif ($check -eq 'AdvancedSettings') { $rows=@($rows | Where-Object { $_.SettingName -in $SettingName }) }
            if ($check -ne $source) {
                if ($rows.Count -gt $MaxRowsPerCheck -or $rows.Count+$retained -gt $MaxTotalRows) { throw 'Toolkit.RowLimitExceeded' }
                if ($check -ne $source) { $retained+=$rows.Count }
            }
            $state.Status=Get-ToolkitObservationStatus -Check $check -Rows $rows -Definition $catalog[$check]
            $state.RowCount=$rows.Count;$state.Reason='Observed'
            # Cache selected results separately to avoid replacing a shared union/source.
            $cache["Result:$check"]=$rows
        } catch {
            $state.Status='Failed';$state.RowCount=0
            $state.Reason=if ($_.Exception.Message -eq 'Toolkit.RowLimitExceeded') { 'RowLimitExceeded' } else { 'CheckFailed' }
            if (-not $cache.ContainsKey($source)) {
                $sourceErrors[$source]=$true
                if ($source -ne $check) { $states[$source].Status='Failed';$states[$source].Reason='SharedSourceFailed';$states[$source].RowCount=0 }
            }
            if (-not $ContinueOnError) { $halted=$true }
        }
    }
    Add-ToolkitStatePresentation -States @($states.Values)
    $requestedStates=@($states.Values | Where-Object Requested)
    $failed=@($requestedStates | Where-Object Status -eq Failed).Count
    $observed=@($requestedStates | Where-Object { $_.Status -in @('Completed','Empty','Incomplete') }).Count
    $outcome=if ($failed) { if ($observed) { 'PartialFailure' } else { 'Failed' } } elseif (@($requestedStates | Where-Object { $_.Status -notin @('Completed','Empty') }).Count) { 'Incomplete' } else { 'Completed' }
    $data=[ordered]@{ScopeId=$ScopeId;CapturedAt=$started;Completeness='Unknown';ToolkitOutcome=$outcome;ToolkitExecution=@($states.Values)}
    foreach ($check in $catalog.Keys) {
        if (-not $selected.Contains($check)) { continue }
        $key=$catalog[$check].Key
        if ($check -eq 'OldSnapshots' -and -not $selected.Contains('Snapshots')) { $key='Snapshots' }
        if (-not $key) { continue }
        if ($cache.ContainsKey("Result:$check")) { $data[$key]=$cache["Result:$check"] } else { $data[$key]=$null }
    }
    $report=[pscustomobject]@{Status='NotRequested';Path=$null;Reason='NotRequested'}
    if ($PSBoundParameters.ContainsKey('HtmlPath')) {
        if ($PSCmdlet.ShouldProcess('new local HTML file','Create central toolkit report')) {
            try {
                $path=Resolve-ToolkitReadPath 'Reporting/New-vSphereHealthReport.ps1'
                $receipt=& $path -Data ([pscustomobject]$data) -OutputPath $HtmlPath -AsOf $AsOf -ErrorAction Stop -Confirm:$false 3>$null 4>$null 5>$null 6>$null
                if ($null -eq $receipt -or $receipt.Mode -ne 'OfflineRendering') { throw 'Toolkit.ReportFailed' }
                $report.Status='Completed';$report.Path=$receipt.Path;$report.Reason='Written'
            } catch { $report.Status='Failed';$report.Reason='ReportFailed';$outcome=if ($observed) {'PartialFailure'} else {'Failed'} }
        } else { $report.Status='NotRun';$report.Reason='NotApproved';if ($outcome -eq 'Completed') { $outcome='Incomplete' } }
    }
    $data.ToolkitOutcome=$outcome
    $results=[ordered]@{}
    foreach ($check in $catalog.Keys) {
        if ($selected.Contains($check)) {
            if ($cache.ContainsKey("Result:$check")) { $results[$check]=$cache["Result:$check"] } else { $results[$check]=$null }
        }
    }
    [pscustomobject]@{State=$(if ($outcome -eq 'Completed') {'Success'} elseif ($outcome -in @('Failed','PartialFailure')) {'Failed'} else {'Unknown'});Outcome=$outcome;ExecutionCompleted=($outcome -ceq 'Completed');Checks=@($states.Values);Results=[pscustomobject]$results;Data=[pscustomobject]$data;Report=$report;StartedUtc=$started;FinishedUtc=[datetimeoffset]::UtcNow;SourceExecutions=$sourceCalls;RetainedRows=$retained;MaxRowsPerCheck=$MaxRowsPerCheck;MaxTotalRows=$MaxTotalRows;RealVmwareValidated=$false}
}
Export-ModuleMember -Function Invoke-ToolkitRun,Get-ToolkitDiscovery
