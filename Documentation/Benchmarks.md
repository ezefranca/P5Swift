# Performance baseline methodology

Performance checks are regression tripwires, not universal throughput claims. `Configuration/PerformanceBudgets.json` gives the deterministic P5 Metal rendering suite a broad 15-second wall-clock ceiling including test-process startup.

The 2026-08-16 Apple M4 reference completed the focused suite in 0.44 seconds with Apple Swift 6.3.2; a concurrent full-validation run completed it in 4.25 seconds. Release notes record hardware, OS, toolchain, thermal context, observed time, and budget result.

For tagged candidates, run `Scripts/run_instruments_audits.sh` with Time Profiler,
Allocations, Leaks, and Metal System Trace. The script ad-hoc signs a temporary
audit executable with Apple's debug entitlement and deletes it afterward; it does
not change system security policy. Record duration, workload, device, and findings,
and never commit trace archives. Deterministic lifetime tests, sanitizer jobs,
resource statistics, and explicit cleanup remain CI gates.

## Current Instruments acceptance

On 2026-08-16, the release smoke workload completed readable 15.6-second Time
Profiler, Allocations, Leaks, and Metal System Trace archives on an Apple M4
Mac running macOS 26.6.1. `xctrace` reported no run issue for any archive; the
Leaks table contained no exported leak-row schema. Power Profiler explicitly
requires a physical iOS/iPadOS application target and remains a tagged-device
release check rather than a macOS package gate.
