# Performance baseline methodology

Performance checks are regression tripwires, not universal throughput claims. `Configuration/PerformanceBudgets.json` gives the deterministic P5 Metal rendering suite a broad 15-second wall-clock ceiling including test-process startup.

The 2026-08-16 Apple M4 reference completed the focused suite in 0.44 seconds with Apple Swift 6.3.2; a concurrent full-validation run completed it in 4.25 seconds. Release notes record hardware, OS, toolchain, thermal context, observed time, and budget result.

For tagged candidates, run `Scripts/run_instruments_audits.sh` with Time Profiler, Allocations, Leaks, Metal System Trace, and Power Profiler after granting the host's protected process-analysis permission. Record duration, workload, device, and findings; never commit trace archives. Deterministic lifetime tests, sanitizer jobs, resource statistics, and explicit cleanup remain CI gates even when privileged Instruments capture is unavailable.
