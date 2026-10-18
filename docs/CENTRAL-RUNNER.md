# Central read-only executor

Limited real observations and their constraints are summarized in [the compatibility matrix](TOOL-VALIDATION-MATRIX.md). Examples and public demo data remain fictional. Use a separately authorized explicit connection and trusted TLS for any future lab run. Native runner Completed/Success means query execution, not complete functional coverage, compliance or health. Empty objects can leave validation PARTIAL; package-wide RealVmwareValidated remains false.

`./scripts/Invoke-VMwareToolkit.ps1` orchestrates existing PowerCLI report scripts. It never creates or chooses a connection, prompts for credentials, installs modules, changes TLS configuration or modifies infrastructure. One explicit connected Server, EndpointType (vCenter or ESXi) and caller-established opaque ScopeId are mandatory. Limited real profile execution is recorded in the compatibility matrix. Least-privilege roles remain unverified; offline mocks continue to provide regression coverage.

## Selection

Use `-Profile` (alias for the canonical parameter CheckProfile), or `-Checks`, never both. The alias avoids overwriting PowerShell's automatic PROFILE variable.

| Profile | Requested checks |
|---|---|
| Inventory (default) | VMInventory, Tools, Datastores |
| Operations | VMInventory, Tools, Snapshots, OldSnapshots, Datastores, HostHealth, Dns, Ntp, Time |
| Security | Certificates, HostSecurity, Firewall, Syslog, Time, AdvancedSettings |
| All | All fourteen checks above |

Explicit Checks accepts only those fourteen canonical names. No paths, command expressions, wildcard check selection or plugins are accepted. Duplicate checks are rejected. Set-VMHostDnsServers.ps1 is explicitly excluded, including its WhatIf mode. VCF offline analyzers and Compare-vSphereInventory are separate offline tools, not provider checks. The HTML renderer is the only optional local output action.

HostName/VMName selection is independent: use VMName, VMHostName, DatastoreName and RuleName filters. SettingName selects exact advanced keys and defaults to the five reviewed syslog keys; value withholding remains enforced by the existing tool. CertificateScope defaults to VMHost (selected managed hosts); VCenter selects only the vCenter machine SSL certificate and does not forward a host Name filter. Direct-ESXi certificates remain NotRun/UnsupportedEndpoint; All on such an endpoint is consequently Incomplete. EndpointType is a caller declaration, not an authenticated build check.

## Results and meaning

The command returns one object with:

- Outcome and ExecutionCompleted: overall execution state, never health/compliance.
- Checks: all fourteen named checks, Requested flag, Status, RowCount, fixed Reason and physical Source name.
- Results: arrays for every requested check; failed/not-run results are null. This preserves DNS and OldSnapshots data even when no separate HTML section exists.
- Data: the existing HTML envelope, plus ToolkitOutcome and ToolkitExecution. Completeness remains Unknown; query completion cannot prove visibility. ScopeId and capture timing are caller/context labels, not new VMware contracts.
- Report: NotRequested, Completed (file written), Failed or NotRun, with a path only after success. A completed file does not imply all checks completed.
- SourceExecutions and RetainedRows: root toolkit-script invocations and retained row accounting, not server API call counts or bytes.

| Check status | Interpretation |
|---|---|
| Completed | Selected observations returned without known missing evidence; not a health assessment |
| Empty | The source executed and returned zero rows; no compliance/visibility inference |
| Incomplete | Missing/null/Unknown evidence, required fields absent, or withheld setting values |
| Failed | Read, projection, invalid/duplicate result, dependency or row-budget failure; dataset discarded |
| NotRun | Not selected, stopped after failure or unsupported endpoint |

Reasons are fixed strings, not exception messages or connection details. Source observations with credential/secure-string objects or nonfinite floating-point values are rejected. Source records are trusted toolkit DTOs, not a public arbitrary-object execution interface. A shared dependency may execute even when not directly requested; its row is labeled Dependency or SharedSourceFailed rather than falsely NotRun. Already cached selected work may be reported after a later failure without issuing another read.

Outcome is Completed only when every requested check is Completed/Empty and requested HTML was written. Known missing data or a skipped requested check yields Incomplete. Failures with some observed requested results yield PartialFailure; with none, Failed. ExecutionCompleted is false for all three. Successful earlier datasets remain available explicitly alongside these failure states; this is not an atomic cross-check snapshot.

Expected check failures return a structured object instead of throwing away all diagnostic status. Invalid arguments/connection shape still throw. Do not rely on PowerShell process exit code or ErrorAction Stop alone to gate automation:

```powershell
$result = ./scripts/Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'authorized-scope' -Profile Inventory
if (-not $result.ExecutionCompleted) { throw 'Toolkit execution was incomplete; inspect sanitized check statuses privately.' }
# A completed execution is still not a security or health pass.
```

## Reuse and limits

Execution is sequential, with no background jobs, retries or provider command interception. All chooses at most eleven fixed source-script invocations:

- Snapshots is collected once with identity, then the same pure age projection used by Get-OldSnapshots derives old rows. The standalone tool's public contract/output is unchanged.
- If Time and Ntp are selected together, Time invokes the existing NTP reader once and supplies both models. A Time failure cannot salvage un-emitted internal NTP rows; it is not retried automatically.
- Syslog and AdvancedSettings use one exact-key union read. Requested advanced results are filtered back to the requested key set; syslog is projected from its five keys. No unrestricted setting dump is introduced.

Whole-script results are cached only during this invocation. Repeated VM/host enumeration inside different existing tools remains possible. SourceExecutions is not the number of Get-VMHost/Get-View calls or remote requests. No global functions, PowerCLI sessions, defaults or caches are modified to intercept them.

MaxRowsPerCheck defaults to 10,000 and MaxTotalRows to 50,000 (positive, up to 1,000,000). Limits apply to retained source/derived records; source failures publish no rows, and exhausted retention budget prevents starting another source. Derived rows also consume budget. Filters, smaller selections and sequential execution reduce load. Existing scripts buffer upstream before yielding, so limits cannot cap their initial query size, total PowerCLI memory, byte size, request duration or underlying per-host API calls. This limitation remains pending lab/scale validation; do not claim an absolute memory bound or snapshot consistency.

Default behavior stops new work after the first failed check. ContinueOnError permits independent checks to continue; a failed shared source is not retried. Incomplete observations continue without being called complete. Earlier source buffers may remain retained for dependencies; the accounting is conservative and does not measure actual heap usage.

AsOf defaults to invocation time for snapshot/certificate calculations. UnspecifiedTimeZone is forwarded only for timestamp handling that requires it; never guess the source zone. Snapshots are normalized to UTC for HTML. Capture time and evaluation time need not be identical, and concurrent changes can make records inconsistent or future-relative to AsOf; those existing date guards remain in force.

## HTML integration and file safety

Optional HtmlPath calls the existing New-vSphereHealthReport with the compatible envelope, including execution outcome and a new optional ToolkitExecution table. Old report inputs add no execution section and retain previous behavior. Failed/not-run collections remain null/Unknown, while executed empty collections remain explicit arrays. Array identity is preserved for one-row and empty results.

All original output protections apply: encoded allowlisted fields, bounded setting disclosure, no JavaScript/CDN/telemetry, no raw connection or credential serialization, new local file only, no overwrite and restricted Unix permissions. A write failure changes overall Outcome and never claims a report path. WhatIf/declined confirmation suppresses HTML only: read-only provider checks still execute; an ungenerated requested file makes Outcome Incomplete. WhatIf is not permission to use an unauthorized VMware endpoint.

Only fixed repository-relative scripts are resolved. Selected script/ancestor symlinks and missing files are rejected. No user script-path parameter exists. The local checkout and imported internal helpers must be trusted; this is not cryptographic code attestation or a sandbox against concurrent/malicious checkout replacement. No untrusted downloaded or inherited code is executed.

Results still contain infrastructure names, IDs, settings and addresses. Keep them and generated HTML outside Git with appropriate ACLs. Errors use fixed reasons, provider warning/verbose/debug/information streams are suppressed, and no arguments or raw provider exceptions are logged by the runner. Do not pass secrets as labels/filters or log the entire result; arbitrary strings cannot be classified infallibly as secrets.

## Future authorized laboratory procedure

Offline development does not use infrastructure. Do not invoke the production runner with fabricated connections as an offline test; use the Pester seam below. Before real use, obtain authorization for endpoint, time window, read scope, exact checks/filters, credential privileges and private output location. Installation/import approval is separate. Follow [setup](GETTING-STARTED.md) and [community testing](COMMUNITY-TESTING.md); validate existing official modules/cmdlets, trust chain/hostname and a single explicit existing connection. The runner performs no login or certificate-policy changes.

```powershell
# Future authorized lab only; $connection already holds one approved VIServer.
$result = ./scripts/Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'authorized-scope' -Profile Operations -VMName 'lab-*' -VMHostName 'esxi*.example.invalid' -MaxRowsPerCheck 1000 -MaxTotalRows 5000 -HtmlPath '<new-private-local-report.html>'
$result.Checks | Select-Object Check,Requested,Status,RowCount,Reason,Source
```

Use opaque persistent ScopeId, not a hostname that might be reused. The result does not automatically satisfy the comparison envelope's SelectionId/completeness requirements. Before cross-capture comparison establish an equivalent visibility/filter policy; never infer Complete from this runner's Completed.

Read prerequisites are the union of existing tool contracts: VM/property inventory visibility; datastore visibility plus Datastore.Browse for snapshot sizes; host config/network/service/firewall/advanced-setting reads; and machine-certificate reads for the chosen scope. Exact least-privilege roles, licensing, module versions, timeout behavior and ESXi/vCenter build compatibility remain unverified. Permissions denied by a child cannot be accurately classified beyond generic failure after its sanitized error contract; no causal guess is returned.

## Offline reproduction

With the approved existing test tools:

```powershell
./tests/Invoke-Validation.ps1
Invoke-Pester -Path ./tests/Runner.Tests.ps1 -Output Detailed
```

Runner.Tests replaces only the private source-script invocation seam with fabricated runner-results.json DTOs. The public runner, profile/dependency planning, statuses, budgets, shared age projection and actual HTML generation run locally. No PowerCLI is imported and no network call occurs. The existing tool suites separately exercise mocked provider behavior. These are automated local integration/simulation results, not real VMware functional validation.

## Offline discovery and readable state

`./scripts/Invoke-VMwareToolkit.ps1 -ListProfiles` lists actual profile membership; `-ListChecks` lists the fixed read-only catalog. Neither requires a connection or runs checks. Discovery is mutually exclusive with execution selection. Get-Help -Full documents both options and all four memberships.

Per-check State supplements legacy Status: Completed/Empty → Success, Incomplete → Unknown, Failed → Failed, NotRun → NotRun. Empty means no rows returned, not complete inventory visibility. Fixed Message gives guidance without raw exceptions. Root State maps Completed to Success, Incomplete to Unknown and PartialFailure/Failed to Failed. Continue to inspect Outcome, ExecutionCompleted and Report; structured failures are not terminating PowerShell errors. Returned Results/Data can contain private infrastructure metadata.

## Recorded real observations

See [TOOL-VALIDATION-MATRIX.md](TOOL-VALIDATION-MATRIX.md). Operations completed with real snapshots on VC8 and ESXi8 using explicit OlderThanDays=0.00001; the default remains 7. Security/All retain Incomplete when optional fields are Unknown or direct certificates are unsupported. Twelve HTML outputs were matched to source counts and states. This does not alter runner contracts or turn Completed into a health verdict. Other builds, scale and vCenter least-privilege roles remain pending.
