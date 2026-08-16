# The Nature of Code Compatibility

Use P5, Matter, and ML5 as native building blocks for Daniel Shiffman's
*The Nature of Code* without treating the book as bundled source.

## Scope

The API requirements were audited against
[`nature-of-code/noc-book-2`](https://github.com/nature-of-code/noc-book-2) at
commit `03b9a7eea3b56be8dfaef324736cf56455a2c5e4`. The audit guides reusable
library capabilities: vectors, forces, randomness, noise, drawing, physics,
training, inference, and neuroevolution.

The project intentionally does not ship exhaustive ports of the book's examples.
Examples, text, and artwork remain governed by their upstream licenses and
attribution. This independent project is not affiliated with or endorsed by
Daniel Shiffman, The Coding Train, p5.js, Matter.js, or ml5.js.

## Native mapping

| Book need | Native package |
| --- | --- |
| Sketch lifecycle, visualization, input, media, math, and 3D | P5 |
| Bodies, contacts, constraints, forces, runners, and queries | Matter |
| Datasets, preprocessing, dense training, inference, and neuroevolution | ML5 |

JavaScript examples require Swift type declarations, explicit error handling,
actor hops for mutable engines and datasets, and permission handling for native
resources. Cross-package integration belongs in an application target; the three
libraries do not depend on one another.
