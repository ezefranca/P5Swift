# 3D Geometry and Coordinates

Prepare cameras, transformations, meshes, primitives, and OBJ models independently
from a GPU renderer.

## Coordinate conventions

p5.swift 3D uses a right-handed world: positive x points right, positive y points up,
and an untransformed camera looks toward negative z. Matrices use column vectors and
column-major storage, matching Metal's `float4x4` memory layout. Clip-space depth is
Metal's `0...1` rather than OpenGL's `-1...1`.

``P5Matrix4x4`` composes transformations from right to left:

```swift
let model = P5Matrix4x4.translation(x: 2, y: 0, z: 0)
    * P5Matrix4x4.rotationY(.pi / 4)
    * P5Matrix4x4.scale(x: 2, y: 2, z: 2)

let worldPoint = model.transformPoint(P5Vector(x: 1, y: 0, z: 0))
```

Directions use a homogeneous w of zero, so translation does not affect them. Points
use a w of one and perform homogeneous division after projection.

## Cameras and projections

``P5Camera3D`` validates a position, distinct target, and nonparallel up direction.
Its view transform is combined with a ``P5Projection3D`` perspective or orthographic
matrix at render time, once the target aspect ratio is known.

```swift
let camera = try P5Camera3D(
    position: P5Vector(x: 0, y: 2, z: 6),
    target: .zero,
    projection: .perspective(
        verticalFieldOfView: .pi / 3,
        near: 0.1,
        far: 100
    )
)
```

Near planes must be positive for perspective projection and every far plane must be
beyond its near plane. Projection construction reports invalid state with
``P5Math3DError`` rather than emitting infinities.

## Meshes and primitives

``P5Mesh`` stores counterclockwise indexed triangles made from ``P5Vertex3D`` values.
Construction validates finite positions, normals, texture coordinates, colors,
complete triangle groups, and every index. Its ``P5Mesh/bounds`` are available before
uploading anything to Metal.

```swift
let plane = try P5Mesh.plane(width: 4, height: 3)
let box = try P5Mesh.box(width: 1, height: 2, depth: 1)
let sphere = try P5Mesh.sphere(radius: 1, segments: 32, rings: 20)
```

Use ``P5Mesh/calculatingNormals()`` when imported triangles have no normals. It
calculates smooth area-weighted normals and rejects zero-area triangles explicitly.

## OBJ loading

``P5OBJModelLoader`` parses Wavefront OBJ positions, texture coordinates, normals,
and polygon faces. It supports positive and negative indices, fan-triangulates
polygons, shares identical vertex references, normalizes supplied normals, and
generates missing normals.

```swift
let mesh = try await P5OBJModelLoader().load(from: modelURL)
```

Local reads and URLSession requests observe cooperative cancellation. Unsupported
geometry statements and malformed line references report ``P5Model3DError`` with a
stable line number. Object, group, smoothing, and material-library declarations are
accepted as metadata, but this loader deliberately returns one geometry mesh; the
host owns external material resolution.

## Topics

### Math and cameras

- ``P5Matrix4x4``
- ``P5Projection3D``
- ``P5Camera3D``
- ``P5Math3DError``

### Geometry

- ``P5Vertex3D``
- ``P5TextureCoordinate``
- ``P5Mesh``
- ``P5Bounds3D``
- ``P5MeshError``

### Models

- ``P5OBJModelLoader``
- ``P5Model3DError``
