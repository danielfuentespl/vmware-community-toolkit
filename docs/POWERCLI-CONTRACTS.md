# PowerCLI reporting contracts and implementation boundaries

Reviewed 2026-10-17 before implementation. References are current `latest` documentation, not pinned VMware releases or execution evidence. No vendor code, examples or captures were copied. Core module cmdlets must exist in the user's approved installation; consult the [observed combinations](TOOL-VALIDATION-MATRIX.md) separately from these contract references. All six tools require an explicit Server, buffer output, sanitize query/projection errors, stop on provider warnings and perform no writes. Duplicate provider identities cause failure; distinct objects with equal display names remain distinct. Empty visible inventory is valid and does not prove account permissions or completeness.

## VMware Tools

[Get-View](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-view) supports explicit Server, ViewType and selective Property paths. [VirtualMachine](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.VirtualMachine.html) defines optional Guest information and its last-known nature. [GuestInfo](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.vm.GuestInfo.html) documents ToolsVersion, ToolsRunningStatus and ToolsVersionStatus2; the older status properties are deprecated. Get-VMwareToolsStatus uses those fields rather than guessing status from version numbers. Missing optional values become Unknown; unrecognized strings remain reported strings, not a health/compliance decision. A powered-off VM's guest fields may be stale. No guest credential or Tools upgrade is used.

[ManagedObjectReference](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vmodl.ManagedObjectReference.html) identifies objects by type/value; Get-View returns SDK views with MoRef. Type is checked and Value is used for identity. Wildcard Name filters are evaluated locally with OR semantics, avoiding regex interpretation by Get-View. This reads all visible projected VM/host views before local filtering; it is not a server-side scalability optimization.

Existing equivalent: Get-VMInventory reports CPU/memory/host, not Tools status. It is retained unchanged.

## Host alarm summary

[HostSystem](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.HostSystem.html), [HostListSummary](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.host.Summary.html) and [HostRuntimeInfo](https://developer.broadcom.com/xapis/vsphere-web-services-api/latest/vim.host.RuntimeInfo.html) support Summary.OverallStatus, Runtime.ConnectionState and Runtime.InMaintenanceMode. Get-VMHostHealth issues a selective Get-View retrieval, rather than relying on cached update notifications. AlarmStatus preserves green/yellow/red/gray; missing or future values are Unknown. HardwareHealth remains NotEvaluated even if alarm status is green. No sensor, CIM, hardware scan, refresh task or inferred healthy boolean is implemented. Runtime is required; maintenance must be boolean. Existing DNS report is unrelated.

## Datastores

[Get-Datastore](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-datastore) and [Datastore](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.datastoremanagement.datastore) document Id, Name, Accessible, CapacityGB and FreeSpaceGB. Get-DatastoreCapacity computes used space and percentage. Vendor GB fields use binary units; output labels are GiB. Inaccessible stores emit null measurements/Unknown, not a claim that stale capacity is current. Accessible zero-capacity stores have a null percentage; negative, nonfinite or inconsistent sizes fail the entire report. This is not vSAN physical usage, thin-provisioned demand or a capacity forecast. No existing datastore equivalent was present.

## Old snapshots

[Get-Snapshot](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-snapshot) and [Snapshot](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.vm.snapshot) provide Created, Id and SizeGB. Snapshot sizes require Datastore.Browse visibility. Get-OldSnapshots reuses Get-SnapshotReport with a new opt-in IncludeIdentity projection; the existing default output is preserved. The wrapper applies a strictly greater-than age threshold against one AsOf instant; one day means 24 elapsed hours. It never removes snapshots. Future timestamps fail. Typed DateTime/DateTimeOffset values are required. Unspecified DateTime needs explicit UnspecifiedTimeZone; ambiguous/nonexistent local times fail. Snapshot identity is scoped by VM identity. Identical display names are not treated as stable IDs.

## NTP configuration

[Get-VMHostNtpServer](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-vmhostntpserver) returns strings for explicit VMHost and Server. Get-VMHostNtpConfiguration first selects hosts, then returns configured ordered NtpServers. Empty lists are valid. Duplicate case-insensitive server strings fail; full DNS/IP equivalence is not inferred. No DNS lookup, NTP probe, service start, time adjustment or claim of synchronization is made. Service running state and PTP details are outside this implementation. Existing DNS utilities remain separate.

## Machine SSL certificate dates

[Get-VIMachineCertificate](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-vimachinecertificate) documents Server plus VMHost or VCenterOnly. [ViMachineCertificateInfo](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.certificates.vimachinecertificateinfo) provides Uid, NotValidBefore and NotValidAfter. Get-VMCertificateExpiry reads exactly one machine SSL certificate per selected target. A missing/multiple result fails rather than silently skipping it. It reports fractional DaysToExpiry and date status at AsOf, optionally retaining certificates within a horizon (including expired). TrustVerified is always false. No PEM, subject, issuer, private key or raw certificate object is returned.

The name refers to VMware machine SSL certificates; it does not inspect guest VM application certificates, trust stores, STS, solution users or VCF certificate inventories. The four existing VCF adapters consume offline exports from another contract and are not used as a substitute. Direct ESXi certificate access is blocked before querying: the consulted cmdlet reference describes a vCenter context; a supported direct-host path remains pending. Unspecified timestamps require an explicit zone, using the same helper as snapshot age.

## Endpoint and permission matrix

| Tool | Intended vCenter scope | Direct ESXi limitation | Read prerequisites to verify in a lab |
|---|---|---|---|
| Tools status | Visible VM views | Single host only; optional guest fields may be absent; no equivalence assumed | VM/property visibility; no guest login |
| Host alarm summary | Visible host views | Host-only alarm/runtime data; not a complete hardware health assessment | Host/property visibility |
| Datastore capacity | Visible datastores | Host-visible stores only; shared stores cannot be summed across endpoints blindly | Datastore visibility and accessible size data |
| Old snapshots | Visible VMs and snapshots | Single-host VM scope; size/permission behavior unverified | VM/snapshot visibility and Datastore.Browse for size |
| NTP configuration | Selected visible hosts | One host's configured servers only | Host/NTP configuration read access |
| Certificate expiry | vCenter machine SSL or selected managed host machine SSL | Deliberately blocked | Certificate read permission; exact role/version support unverified |

All endpoint entries are design scopes, not verified product compatibility. No exact minimal role or release is certified. Read-only mode does not bypass permissions. No REST endpoints, pagination arguments or refresh/write operations are invented. PowerCLI abstracts traversal; these reports do not implement raw API pagination.

## Synthetic evidence

`tests/fixtures/phase7-projections.json` is fabricated from the documented property subsets: two VMs (one missing Guest), two hosts (connected/green and disconnected/gray), one 100/25 datastore plus an inaccessible store, two NTP strings, snapshots aged 16 and exactly 7 days at 2026-10-17T00:00:00Z, and a machine certificate expiring three days later. Identifiers, example.invalid names and 192.0.2.0/24 addresses are fictional. Dates/numeric values are deterministic; the loader produces typed timestamps on the tested runtime. No JSON fixture is claimed to be a full API payload or real PowerCLI CLR serialization. Test faults are synthetic exceptions, not claimed vendor fault contracts.
