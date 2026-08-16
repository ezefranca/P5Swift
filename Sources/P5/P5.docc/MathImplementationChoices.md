# Math Implementation Choices

Use deterministic scalar Swift implementations for creative-coding math and reserve
Apple acceleration frameworks for measured bulk workloads.

## Preserve portable results

``P5RandomGenerator`` uses SplitMix64, Box-Muller Gaussian sampling, and inverse-transform
exponential sampling. ``P5NoiseGenerator`` uses a seeded permutation table and scalar
Perlin interpolation. These algorithms intentionally avoid platform framework calls so a
given seed produces the same golden sequence across supported Apple devices and Swift
toolchains.

``P5Vector`` stores three `CGFloat` components and exposes value-semantic operations.
Swift's optimizer can use native scalar or SIMD instructions without changing the public
representation. Most sketch operations work on one vector at a time, where conversion to
an Accelerate buffer would cost more than the arithmetic it replaces.

## When Accelerate is appropriate

Accelerate becomes useful when an application already owns large contiguous numeric
buffers and performs the same transform over many elements. Keep that optimization in a
separate bulk algorithm, benchmark allocation and conversion costs, and compare results
against the scalar reference with an explicit tolerance.

BNNS is oriented toward neural-network primitives rather than individual p5-style vector,
random, or coherent-noise calls. ML5 uses Core ML and MPSGraph for the corresponding model
and training workloads while retaining deterministic CPU references for validation.

## Verify distributions

The tests pin exact SplitMix64 output and repeatability, then validate deterministic sample
means and moments for uniform, Gaussian, weighted, and exponential distributions. These
checks detect implementation regressions; they are not substitutes for application-level
simulation validation.

## See Also

- ``P5RandomGenerator``
- ``P5NoiseGenerator``
- ``P5Vector``
- <doc:TimingAndDeterminism>
