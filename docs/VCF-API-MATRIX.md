# Offline VCF API/profile matrix

Reviewed 2026-10-17. Documentation access only: no VMware infrastructure, transport or authentication. All implementations below process local UTF-8 JSON. `latest` is a mutable vendor alias, not a verified product/build. Version-specific 9.0.0 documentation routes could not be retrieved in this review; the current SDDC Manager and VCF Operations changelogs do not establish exact build binding. VCF 9.0.x, 9.1.x and later releases remain functionally and contract-version UNVERIFIED. Do not label an operator-supplied SourceVersion as proof.

## Evaluated capabilities

| Proposal | Source / verified reference method and route | Documented fields used | Decision / meaning |
|---|---|---|---|
| Get-VCFDomainHealth | SDDC Manager GET /v1/domains | id, name, type, status | No new tool: Get-VCFInventory already exposes these states. ACTIVE is an operational domain state, not global health. Current Get-VCFHealth projects historical health-task status, not present health. A domain-wide health verdict is blocked pending an evidenced aggregate contract and criteria. |
| Get-VCFLifecycleStatus | SDDC Manager GET /v1/domains | id, name, status, upgradeState, upgradeStatus.status/completedResources/totalResources | Implemented offline. Domain upgrade observations/counters, not upgrade readiness, patch compliance, latest available release or complete lifecycle health. |
| Get-VCFOperationsAlerts | VCF Operations GET /suite-api/api/alerts | alerts[].alertId/resourceId/alertLevel/status/controlState/startTimeUTC/updateTimeUTC; pageInfo.page/pageSize/totalCount | Implemented offline. Source alert state/severity, not aggregate infrastructure health. Owners, localized names, stat keys, links and extension data omitted. |
| Get-VCFLicensingReport | SDDC Manager GET /v1/licensing-info/system | resourceType, licensingMode, subscriptionStatus, subscribedState, isRegistered, isSubscribed, daysRemainingToSubscribe | Implemented offline single SYSTEM object. Registration and subscription remain separate; no compliance, legal entitlement or license validity verdict. Keys, resource IDs and entitlement details omitted. |
| Operations license info | VCF Operations GET /suite-api/api/product/licensing/info | licensed, expirationDate, licenseKey, licenseName | Reviewed, not implemented. Different source/model from SDDC subscription registration. Avoid exposing keys or equating a product licensed flag to entitlement. Expiration unit/semantics and exact product-version binding require verification. |
| Selected domain target release | Generic VCF GET /v1/releases/domains/{domainId} | domainId, targetVersion, targetSddcManagerVersion, patches, isCustomizedBom | Reviewed, deferred: selected target is not actual upgrade progress. Do not infer installed BOM or readiness. |

## Primary sources and version evidence

- [SDDC Manager domains response](https://developer.broadcom.com/xapis/sddc-manager-api/latest/v1/domains/get/): Domain/PageOfDomain including BLOCKED upgrade status and pageNumber/pageSize parameters. The [older generic VCF domains reference](https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/domains/get/) differs in filters and enum subset. Profiles are not interchangeable across all releases.
- [SDDC Manager system LicensingInfo](https://developer.broadcom.com/xapis/sddc-manager-api/latest/v1/licensing-info/system/get/) documents one object and optional resourceId for SYSTEM. The [generic VCF licensing endpoint](https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/licensing-info/system/get/) instead shows an array. We deliberately reject arrays rather than silently merge these contracts.
- [Operations Get Alerts](https://developer.broadcom.com/xapis/vcf-operations-api/latest/suite-api/api/alerts/get/), [alerts envelope](https://developer.broadcom.com/xapis/vcf-operations-api/latest/data-structures/alerts/), [alert model](https://developer.broadcom.com/xapis/vcf-operations-api/latest/data-structures/alert/) and [page-info](https://developer.broadcom.com/xapis/vcf-operations-api/latest/data-structures/page-info/) support the separate Operations projection and 0-based pages. Optional timestamps are int64 UTC values; the reviewed model does not specify units, so StartTimeRaw/UpdateTimeRaw preserve integers and TimestampUnit remains Unknown. No epoch conversion or time ordering inference is performed.
- [Operations product licensing](https://developer.broadcom.com/xapis/vcf-operations-api/latest/suite-api/api/product/licensing/info/get/) is intentionally separate from SDDC licensing.
- [Domain target release](https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/releases/domains/domainId/get/) and [upgrade API overview](https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/upgrades/) distinguish target selection and mutating upgrade workflows; none of those workflows is implemented or invoked.
- [SDDC Manager changes](https://developer.broadcom.com/xapis/sddc-manager-api/latest/changelog/) and [Operations changes](https://developer.broadcom.com/xapis/vcf-operations-api/latest/changelog/) were reviewed. Their rendered current/previous comparison did not pin these models to an exact 9.x build. No versioned URL or API endpoint was invented as functional.

## Strict offline profiles

All three scripts require Path and SourceVersion. Reused local JSON reader rejects network/UNC paths, network drives on Windows, symlink ancestors, invalid UTF-8, duplicate/case-colliding keys, comments, trailing commas, empty/over-16-MiB files and depth above 64. No remote links are followed. On Unix a mounted network filesystem may look local; operators must provide trusted local regular files. Filesystem checks do not sandbox hostile local races. Nothing is installed.

Lifecycle accepts one complete PageOfDomain or an array of complete pages using the existing shared reader. Identifiers must be unique; missing name/status/progress fields become Unknown or null. Numeric counters must be nonnegative int32 with completed <= total when both exist. Nonempty future enum strings become Unknown; incorrect types fail. Counters do not imply a percentage or an outcome. A zero total remains zero rather than an invented success.

Alerts requires explicit alerts arrays and full pageInfo even though vendor fields are optional. This intentionally rejects otherwise valid partial/unpaged exports when completeness cannot be checked. Accept one page object or an array of complete pages, at most 10000. Require page>=0, pageSize>=1, nonnegative int32 totalCount; matching totals/page sizes; exactly the expected rows per page; all pages present once; unique canonical UUID alert identities. Missing optional resourceId is Unknown; present resourceId must be UUID. Raw time fields are optional nonnegative int64; numbers encoded as strings are rejected. No timestamp units are guessed. Links never determine completeness or trigger requests. Counts validate the supplied export, not point-in-time consistency or complete server visibility; collection changes between page captures remain undetectable.

Licensing accepts one SYSTEM object only; no pagination is evidenced or implemented. Missing optional strings/flags are Unknown and absent integer is null. Booleans must be JSON booleans; days use signed int32 because the model does not document a nonnegative constraint. Unknown enums remain Unknown. SYSTEM resourceId is not required or returned. Array exports from the differing generic reference require separate future contract work.

Relevant API error markers at envelopes, entries and nested progress/page metadata are rejected, including mixed error/data responses. All projections buffer until validation finishes, produce no partial success records and use fixed error text/identifiers without raw payload/path/exception details. Raw unknown properties are ignored, not serialized. This is a strict projection profile, not a complete OpenAPI/JSON Schema validator or a scrubber for arbitrary secrets placed inside valid text fields. Protect real exports, version labels, IDs and outputs outside Git.

Each row labels Source, Endpoint, SourceVersion, Mode=Offline, ContractVerifiedForProductVersion=false, RealVmwareValidated=false and Assessment=Unknown. Empty collections yield no observations and never healthy/compliant evidence. There is no cross-source correlation or vCenter join.

## HTML and reproducible example

Optional envelope keys VCFLifecycle, VCFOperationsAlerts and VCFLicensing accept arrays returned by their corresponding tools. Old inputs remain unchanged. Source must explicitly match its section. HTML escapes allowlisted fields, derives fixed endpoint/source labels, forces Assessment=Unknown and omits raw timestamp values, owner data, links and license keys. These sections are not central PowerCLI checks and are never collected implicitly.

```powershell
$lifecycle = @(./scripts/VCF/Get-VCFLifecycleStatus.ps1 -Path ./tests/fixtures/vcf-lifecycle-phase12.json -SourceVersion 'fictional-unverified')
$alerts = @(./scripts/VCF/Get-VCFOperationsAlerts.ps1 -Path ./tests/fixtures/vcf-alerts-phase12.json -SourceVersion 'fictional-unverified')
$licensing = @(./scripts/VCF/Get-VCFLicensingReport.ps1 -Path ./tests/fixtures/vcf-licensing-phase12.json -SourceVersion 'fictional-unverified')
$data = [pscustomobject]@{ScopeId='fictional-review';CapturedAt='2026-10-17T00:00:00Z';VCFLifecycle=$lifecycle;VCFOperationsAlerts=$alerts;VCFLicensing=$licensing}
./scripts/Reporting/New-vSphereHealthReport.ps1 -Data $data -OutputPath $newLocalHtmlPath
```

Supply an existing trusted output directory and a new filename. Capture time is caller-declared, not a date recovered from exports. Missing vSphere collections stay Unknown. Fixtures are original invented projections, not captured exports or copies of vendor sample identities. See tests/fixtures/VCF-PHASE12-SOURCES.json.

## Before any future functional claim

Obtain the exact product/build's official versioned OpenAPI, record its URL/hash privately, compare required/optional fields, statuses, pagination and time units, then test separately authorized exports against the UI at the same scope and capture time. VCF 9.x, SDDC Manager and Operations build combinations all remain unverified. No live transport, authentication, readiness decision, domain health aggregate or entitlement evaluator is prepared by this phase.
