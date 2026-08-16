# Security policy

## Supported versions

Security fixes are applied to the latest tagged release and `main`. Pre-1.0 versions may receive source-compatible fixes where practical; a fix may require a minor-version API correction when safety demands it.

## Reporting

Report suspected vulnerabilities privately through GitHub Security Advisories for `ezefranca/p5.swift`. Include affected versions, platform/toolchain, reproduction, impact, and any proposed mitigation. Do not open a public issue before coordinated disclosure. Never include credentials or private media in reports or traces.

## Response

Maintainers will acknowledge a report, reproduce and assess it, prepare tests and a fix, coordinate disclosure, publish a checksummed release with provenance, and run post-release client/documentation/SPI verification. Compromised releases are documented and yanked according to `Documentation/Releasing.md`.

## Boundaries

P5 processes untrusted images, text/tables, OBJ data, media/network URLs, persisted values, native permissions, and GPU shader/resources. Validation, bounded allocation, cancellation, typed failures, HTTPS, Apple sandboxing, and resource cleanup reduce risk but do not make arbitrary media trustworthy. Host applications remain responsible for usage descriptions, entitlements, localized permission context, server trust, and content policy. The package contains no telemetry, analytics SDK, advertising identifier use, or credential storage.
