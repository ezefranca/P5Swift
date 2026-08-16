import Foundation
import P5

@main
struct P5SmokeSample {
    static func main() async throws {
        let camera = try P5Camera3D()
        let mesh = try P5Mesh.sphere(segments: 12, rings: 8)
        let color = try P5Color(hex: "#33B5E5")

        guard P5MetalRenderer.isAvailable else {
            print("P5 is ready; Metal 3D is unavailable on this host.")
            return
        }
        let renderer = try P5MetalRenderer()
        let uploadedMesh = try await renderer.makeMesh(mesh)
        let material = try P5Material3D(
            baseColor: SIMD4(
                Float(color.red),
                Float(color.green),
                Float(color.blue),
                Float(color.alpha)
            )
        )
        let scene = P5Scene3D(
            camera: camera,
            instances: [P5MeshInstance3D(mesh: uploadedMesh, material: material)]
        )
        let target = try await renderer.makeRenderTarget(width: 64, height: 64)
        let statistics = try await renderer.render(scene, to: target)
        print("P5 rendered \(statistics.lastTriangleCount) triangles on \(renderer.deviceName).")
        if ProcessInfo.processInfo.environment["SWIFT_PACKAGE_INSTRUMENTS_HOLD"] == "1" {
            try await Task.sleep(for: .seconds(20))
        }
    }
}
