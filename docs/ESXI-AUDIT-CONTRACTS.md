# ESXi configuration observation contracts

Official references reviewed 2026-10-17 before implementation. References to `latest` are contract evidence, not a verified product release. These contract descriptions do not establish release support; actual observed combinations are in [the compatibility matrix](TOOL-VALIDATION-MATRIX.md). All provider calls use an explicit mandatory Server, ErrorAction Stop and WarningAction Stop. New audit queries suppress the warning stream while terminating on warnings, so raw provider warning text is not forwarded. Results buffer until every query/projection succeeds. Authentication, permissions and other query failures are not reclassified as unsupported or successful empty data.

## Existing functionality and reuse

The existing host DNS reports/setter are unchanged; writes remain locked. Get-VMHostHealth is an alarm summary, not this security audit. Get-VMHostNtpConfiguration already reads configured NTP servers, so Get-VMHostTimeConfiguration reuses it and adds SDK time observations. Get-VMHostSyslogConfiguration reuses the new advanced-setting reader with a fixed five-key profile. The HTML renderer remains offline and reuses these plain output rows; no new collector, login, HTTP endpoint or live lab-runner path is introduced.

## Security configuration: lockdown plus services

[Get-View](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-view) supplies the selected host's Config.LockdownMode. [HostConfigInfo](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.host.ConfigInfo.html) makes that field optional, introduced at API 6.0. Its predecessor adminDisabled is deprecated and is only supported in VirtualCenter; the API says to ignore its direct-host value. The implementation never queries or falls back to adminDisabled.

[HostLockdownMode](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.host.HostAccessManager.LockdownMode.html) documents lockdownDisabled, lockdownNormal and lockdownStrict. Missing or unrecognized values are Unknown. [Get-VMHostService](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-vmhostservice) and [HostService](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.host.hostservice) supply Key, Running and Policy for one explicit host. One row is emitted per service with the host lockdown observation repeated. An empty service result emits one host placeholder with Unknown service fields. No service key is assumed to mean SSH/Shell; no refresh is requested.

No baseline is bundled to declare a mode or running service vulnerable. Secure Boot, TPM, authentication policy, accounts, permissions and exception-user lists are not audited. Assessment is always NotEvaluated.

## Firewall exception report

[Get-VMHostFirewallException](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-vmhostfirewallexception) supports explicit VMHost/Server and Name filters. [VMHostFirewallException](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.host.vmhostfirewallexception) documents Uid, Name, Enabled, IncomingPorts, OutgoingPorts, Protocols and ServiceRunning. These are projected into one row per exception. RuleName filters exceptions independently of host Name filters. Port/protocol fields are strings, not invented numeric API ranges. Optional absence is Unknown; invalid boolean types fail.

An empty exception query emits a placeholder Observation=NoMatchingExceptions, with Unknown rule attributes. This does not mean the firewall blocks all traffic or that the account can see every rule. This implementation does not retrieve default policy, allowed-source IP lists, dynamic rules, effective packet filtering or network reachability. No enabled/disabled state is labeled a vulnerability without a separately reviewed versioned policy.

## Advanced settings and disclosure profile

[Get-AdvancedSetting](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-advancedsetting) accepts VMHost entities, explicit Server and setting names. [AdvancedSetting](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.advancedsetting) documents Name, Type and an Object Value. Get-VMHostAdvancedSettings requires exact nonblank SettingName keys, rejects wildcard syntax and duplicate requested/returned keys, and never does an unrestricted dump. Each requested key gets a row; missing returned keys have ValueState=Unknown. If PowerCLI reports an error for an absent key rather than an empty query, the entire report fails; no error is silently interpreted as version absence.

Only the five canonical syslog keys below can expose values. Other keys return ValueState=Withheld and never evaluate their Value getter; metadata only. There is no unsafe override. Canonical key spelling is required for value disclosure. Null values are Unknown. Known text settings preserve reported empty strings; numeric settings require finite nonnegative Int32 integers, while the boolean profile accepts actual bool or canonical true/false/0/1 forms. Invalid types fail atomically. No implied product defaults are substituted.

## Syslog

Broadcom's [syslog configuration article 318939](https://knowledge.broadcom.com/external/article/318939/configuring-syslog-on-vmware-vsphere-esx.html) documents Syslog.global.logHost (remote destinations), logDir (storage location), logDirUnique (boolean), defaultRotate (local retained count), and defaultSize (local size threshold, KB per reference). Get-VMHostSyslogConfiguration delegates those exact keys and emits the same typed/state-bearing observations plus DeliveryVerified=false.

A reported empty logHost denotes no configured forwarding destination according to that reference, not a vulnerability verdict. Unknown is not an empty string. Retention values do not prove remote retention. Nothing tests delivery or reloads syslog. Strings resembling URI userinfo or secret assignments/private-key headers are withheld. This is a conservative safeguard, not a general secret detector; labels/paths can remain private and must be reviewed outside Git.

TLS-certificate policy settings for syslog differ across versions and are outside the five-key profile. The tool never changes them and does not claim that an ssl:// destination validates certificates or is reachable. Do not infer missing settings are disabled or unsupported. Any future expansion requires version-specific official evidence and disclosure review.

## Time configuration

The existing NTP reader is reused. [HostDateTimeInfo](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.host.DateTimeInfo.html) supplies optional SystemClockProtocol (since API 7.0) and Enabled, ServiceSync and LastSyncTime (since 7.0.3.0). They are read only when present. ReportedProtocol is plain reported text; no missing protocol is inferred from configured NTP servers. ReportedServiceSync is the SDK observation, never an independent synchronization test. Missing LastSyncTime stays null/Unknown rather than implying never synchronized, because availability/version/visibility is not established offline.

[HostDateTimeSystemTimeZone](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.host.DateTimeSystem.TimeZone.html) defines Key and signed Int32 GmtOffset seconds. The current offset is reported, not used as a permanent zone or drift calculation. Typed timestamps normalize to UTC through the existing helper; unspecified DateTime needs an explicitly established UnspecifiedTimeZone and ambiguous/invalid local times fail. PTP details, current host-clock queries, delay, drift and independent time-source availability are not implemented. IndependentSyncVerified=false always.

## Version, scope and permissions

| Tool | Intended read visibility | Direct ESXi versus vCenter / pending checks |
|---|---|---|
| Security configuration | Host config/property and service read access | Only visible selected hosts; no adminDisabled fallback; lockdown field optional |
| Firewall exceptions | Host firewall read access | Host/exception visibility differs; not a complete effective policy |
| Syslog / advanced settings | Selected host advanced-setting read access | Requested keys and representations may differ by build; explicit errors abort |
| Time configuration | Host NTP and configuration read access | Optional fields added in different API releases; no release support inferred |

Exact minimum roles, installed cmdlet availability, API versions, host licensing and direct-host behavior are unverified. No lab result or product compatibility claim is added. Unsupported fields returned absent are Unknown; an unsupported Property/query error fails with a sanitized stable ID. Broadcom documenting a field's introduction is not a test of that release. Never bypass permission or TLS failures to obtain a report.

All five require one connected VIServer and explicit Server on every read, including reused scripts. Duplicate hosts and nested service/rule/setting identities fail. Identity keys are scoped by host. All tools are read-only and buffer output; no partial successes are published when later reads fail. Missing optional boolean values are the string Unknown; known flags remain bool. Setting ValueState differentiates Reported (including false/zero/empty), Unknown and Withheld. No IsVulnerable or compliance pass/fail field exists.

## Optional HTML sections

Supply any of HostSecurity, HostFirewall, HostSyslog, HostTime and HostAdvancedSettings as explicit arrays in the existing offline envelope. They are omitted when their property is absent; present null is Unknown, and an empty array indicates zero supplied rows. Existing seven-section inputs remain unchanged. The renderer allowlists fields, encodes text, forces Assessment=NotEvaluated/verification flags=false, and reapplies the setting-value disclosure profile rather than trusting a caller's Reported assertion. It never exports arbitrary advanced-setting values. Existing file safety, CSP and no-network behavior remain in effect. See UNIFIED-REPORTING.md for the base envelope and filesystem limits.

## Fixtures and reproduction

esxi-audit-projections.json is fabricated from documented fields; fixture service/rule IDs do not claim real vendor identities or enums. esxi-audit-report.json is a toolkit output fixture for offline HTML examples, not an API response. No production capture, credentials, vendor example code or inherited script is included. Tests cover unknown/missing optional fields, no-match evidence, duplicates, malformed scalar values, permissions, lost sessions, warning suppression, secondary query failure, unsafe-value withholding and HTML escaping/backward compatibility.

Run `Invoke-Pester ./tests/EsxiAudit.Tests.ps1` with existing approved Pester, or `./examples/Invoke-EsxiAuditOfflineExample.ps1 -OutputPath '<new-private-local-file.html>'` using only bundled fictional output. No provider is imported or contacted by that example. Future lab use needs separate authorization and the exact modules/roles/versions recorded privately; all six historical credential occurrences remain open and unrelated to passing these tests.
