# Offline VCF response contracts

Reviewed 2026-10-17. The four existing offline adapters were compared with the current official **SDDC Manager API** reference in addition to the previous VMware Cloud Foundation API reference. No VCF network transport, authentication or product discovery was executed. The code was not replaced with speculative calls.

| Model | Confirmed reference route/method | Fields used by projection | Representative fixtures |
|---|---|---|---|
| Inventory | GET /v1/domains | id, name, type, status; PageOf envelope | Two domains, ACTIVE/ERROR, nested vCenter/owner metadata omitted |
| Versions | GET /v1/sddc-managers | id, fqdn, version; PageOf envelope | Two managers; auth/username/IP metadata omitted |
| Health | GET /v1/system/health-summary | id, status, creationTimestamp; PageOf envelope | PENDING, IN_PROGRESS, COMPLETED_WITH_SUCCESS and COMPLETED_WITH_FAILURE; current health remains Unknown |
| Certificates | GET /v1/domains/{id}/resource-certificates | resourceName, resourceType, notAfter, expirationStatus, getCertificateError; PageOf envelope | ACTIVE, EXPIRED and retrieval failure; keys, PEM, SAN and raw errors omitted |

Official evidence: [domains](https://developer.broadcom.com/xapis/sddc-manager-api/latest/v1/domains/get/), [managers](https://developer.broadcom.com/xapis/sddc-manager-api/latest/v1/sddc-managers/get/), [health tasks](https://developer.broadcom.com/xapis/sddc-manager-api/latest/v1/system/health-summary/get/), [certificates](https://developer.broadcom.com/xapis/sddc-manager-api/latest/v1/domains/id/resource-certificates/get/). These references describe the fields/methods, not proof of deployment compatibility.

## Differences and limits

The newer domains reference documents pageNumber/pageSize and other filters, unlike an older generic reference. The offline adapters accept complete PageOf collections through -Pages or local files and make no pagination requests. -Response requires one complete page. Health task responses include an additional size field, ignored by the projection. Certificate resource types and renewal fields have evolved; unneeded fields remain excluded. Manager nested basicAuthDetails data is deliberately not exposed. No shared authentication assumption is made for VCF Operations; its separate offline alerts model is documented in [the API/profile matrix](VCF-API-MATRIX.md). Live authentication/transport remains unimplemented.

The vendor schema makes some fields optional and represents health timestamps as strings. Our deliberately stricter projection requires the documented subset, explicit elements arrays, self-consistent complete pagination metadata, and timestamps with a timezone. Valid vendor responses outside this profile can therefore be rejected. Synthetic tests demonstrate this profile only; they are not a complete JSON Schema/OpenAPI validator. Metadata consistency does not prove inventory completeness.

## Version matrix

| Target | Evidence | Status |
|---|---|---|
| PowerShell 7.6.7/Linux x64 | Local fixture execution | Verified offline runtime only |
| Current SDDC Manager API reference, alias latest | Fields and methods reviewed at the four URLs above | Projection model aligned with documented subset; product version unverified |
| VCF/SDDC Manager 5.2.x | Previous generic reference; no exact build contract acquired | NOT VERIFIED |
| VCF/SDDC Manager 9.0.x / 9.1.x | Version-specific 9.0 documentation pages unavailable in this review; latest and changelog do not reliably pin this subset to an installed build | NOT VERIFIED |
| VCF Operations / vCenter API | Not these four response models; Operations alerts have a separate offline profile | No live transport or functional compatibility claim |

The [official change log](https://developer.broadcom.com/xapis/sddc-manager-api/latest/changelog/) lists API changes but does not provide the missing build binding for this preparation. No compatible VCF product release is asserted. Obtain a versioned official OpenAPI/schema for the authorized lab build before live collection; record source URL, hash and build, then compare field optionality, enums, timestamps, authentication and pagination. Keep ContractVerifiedForProductVersion=false until that work and actual lab checks are complete.

## Fixture provenance and execution

The existing four fixtures are preserved. Four additional *-representative.json files use invented IDs, reserved example.invalid names and documentation addresses. Their source/mapping manifest is tests/fixtures/VCF-SOURCES.json. They include nested optional/unknown fields and multiple records; existing tests cover empty pages, malformed elements, incomplete pagination, typed/string UTC dates, errors and atomic output. No vendor sample identities, credentials, certificate material or captured corporate response was copied.

From the repository root, in the approved PowerShell test session:

```powershell
./tests/Invoke-Validation.ps1
$response = Get-Content ./tests/fixtures/vcf-health-representative.json -Raw | ConvertFrom-Json
./scripts/VCF/Get-VCFHealth.ps1 -Response $response -SourceVersion 'fixture-only'
```

Do not label fixture results as live health, certificate trust, complete VCF BOM or verified product compatibility. Continue to use VCF-API-MATRIX.md for the separate control-plane and live-transport gates.

## Error-model handling

The [official Error model](https://developer.broadcom.com/xapis/sddc-manager-api/latest/data-structures/Error/) defines errorCode/errorType/message and nested diagnostics. A strict shared guard now rejects these markers in a PageOf envelope/entry/metadata rather than accepting a mixed error/data object as an empty success. Empty/null error markers also cause rejection because the shape is ambiguous. Generic error/errors envelopes are conservatively rejected as well. This can reject future legitimate extensions with those names; it is an intentionally strict profile, not full API-schema validation. Documented per-certificate getCertificateError remains supported as retrieval failure/Unknown.

Synthetic fixtures vcf-error-only.json and vcf-error-mixed.json use invented values, not captured responses. Tests apply them to all four adapters, verify atomic failure, and reject nonfinite pagination. Versions 5.2.x/9.0.x/9.1.x remain unverified by exact official build contract and real execution. No assumed endpoint has been added.

## Offline export container extension — 2026-10-17

The toolkit accepts a local array of complete PageOf objects, validating totals, unique zero-based numbering and aggregate counts before projection. This is a toolkit file format, not a new API root contract. -Response retains the single-page rule. The four *-pages.json fixtures derive from existing representative fixtures; no additional field or product version is asserted. See tests/fixtures/CONTRACTS.md and docs/OFFLINE-DEVELOPMENT.md.
