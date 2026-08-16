import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import P5

private final class P5ImageURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "p5-image.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/status" {
            let response =
                HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
                ?? URLResponse(
                    url: url,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
        } else {
            let response: URLResponse =
                if url.path == "/non-http" {
                    URLResponse(
                        url: url,
                        mimeType: "image/png",
                        expectedContentLength: Self.pngData.count,
                        textEncodingName: nil
                    )
                } else {
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )
                        ?? URLResponse(
                            url: url,
                            mimeType: "image/png",
                            expectedContentLength: Self.pngData.count,
                            textEncodingName: nil
                        )
                }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.pngData)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static let pngData: Data = {
        let pixels = P5PixelBuffer(
            width: 1,
            height: 1,
            bytes: [255, 0, 0, 255]
        )
        return (try? P5Image(pixelBuffer: pixels).encoded(as: .png)) ?? Data()
    }()
}

@Suite("P5 images, pixels, and offscreen graphics", .serialized)
struct P5ImageGraphicsTests {
    @Test("RGBA pixels are mutable, serializable, and round-trip through Core Graphics")
    func pixelsAndNativeImageRoundTrip() throws {
        var pixels = P5PixelBuffer(
            width: 2,
            height: 2,
            pixelDensity: 2,
            bytes: [
                255, 0, 0, 255,
                0, 255, 0, 128,
                90, 80, 70, 0,
                0, 0, 255, 255,
            ]
        )
        #expect(pixels.size == CGSize(width: 1, height: 1))
        #expect(pixels.color(x: 0, y: 0) == P5Color(red: 1, green: 0, blue: 0))
        pixels.setColor(P5Color(red: 1, green: 1, blue: 0, alpha: 0.5), x: 1, y: 1)
        #expect(pixels.bytes.suffix(4) == [255, 255, 0, 128])
        #expect(
            try JSONDecoder().decode(
                P5PixelBuffer.self,
                from: JSONEncoder().encode(pixels)
            ) == pixels
        )

        let image = try P5Image(pixelBuffer: pixels)
        #expect(image.pixelWidth == 2)
        #expect(image.pixelHeight == 2)
        #expect(image.width == 1)
        #expect(image.height == 1)
        #expect(image.size == CGSize(width: 1, height: 1))
        let restored = try image.pixelBuffer()
        #expect(restored.width == pixels.width)
        #expect(restored.height == pixels.height)
        #expect(restored.color(x: 0, y: 0).red == 1)
        #expect(restored.color(x: 1, y: 0).alpha > 0.49)
        #expect(restored.color(x: 0, y: 1).alpha == 0)
    }

    @Test("ImageIO encodes, decodes, loads, writes, and reports typed failures")
    func imageIO() async throws {
        let image = try P5Image(
            pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [12, 34, 56, 255])
        )
        #expect(P5ImageFormat.allCases == [.png, .jpeg, .heif])
        let png = try image.encoded(as: .png)
        let jpeg = try image.encoded(as: .jpeg, quality: 0.5)
        _ = try? image.encoded(as: .heif)
        #expect(try P5Image.decode(png, pixelDensity: 2).pixelDensity == 2)
        #expect(try P5Image.decode(jpeg).pixelWidth == 1)
        #expect(throws: P5ImageError.decodingFailed) {
            _ = try P5Image.decode(Data("not an image".utf8))
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("pixel.png")
        try image.write(to: file, format: .png)
        #expect(try await P5Image.load(from: file).pixelWidth == 1)

        let bundleURL = directory.appendingPathComponent("Images.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let bundleInfo: [String: String] = [
            "CFBundleIdentifier": "dev.p5.swift.image-tests",
            "CFBundleName": "Images",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1",
        ]
        let plist = try PropertyListSerialization.data(
            fromPropertyList: bundleInfo,
            format: .xml,
            options: 0
        )
        try plist.write(to: bundleURL.appendingPathComponent("Info.plist"))
        try png.write(to: bundleURL.appendingPathComponent("pixel.png"))
        let bundle = try #require(Bundle(url: bundleURL))
        #expect(
            try P5Image.loadResource(named: "pixel", withExtension: "png", in: bundle)
                .pixelWidth == 1
        )
        #expect(throws: P5ImageError.resourceNotFound("missing")) {
            _ = try P5Image.loadResource(named: "missing", in: bundle)
        }

        let cancelledLoad = Task {
            withUnsafeCurrentTask { task in task?.cancel() }
            return try await P5Image.load(from: file)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledLoad.value
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [P5ImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let remote = try #require(URL(string: "https://p5-image.test/image"))
        #expect(try await P5Image.load(from: remote, session: session).pixelWidth == 1)
        let nonHTTP = try #require(URL(string: "https://p5-image.test/non-http"))
        #expect(try await P5Image.load(from: nonHTTP, session: session).pixelWidth == 1)
        let status = try #require(URL(string: "https://p5-image.test/status"))
        await #expect(throws: P5ImageError.invalidHTTPStatus(404)) {
            _ = try await P5Image.load(from: status, session: session)
        }

        #expect(P5ImageError.decodingFailed.errorDescription?.contains("supported") == true)
        #expect(
            P5ImageError.encodingFailed(.jpeg).errorDescription?.contains("JPEG") == true
        )
        #expect(P5ImageError.bitmapAllocationFailed.errorDescription?.contains("bitmap") == true)
        #expect(P5ImageError.resourceNotFound("cat").errorDescription?.contains("cat") == true)
        #expect(P5ImageError.invalidHTTPStatus(503).errorDescription?.contains("503") == true)

        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try P5Image(pixelBuffer: try image.pixelBuffer()) { _, _, _ in nil }
        }
        #expect(P5RasterColorSpace.preferred(makeSRGB: { nil }).model == .rgb)
        #expect(
            P5Image.makeImage(
                [0, 0, 0, 0],
                width: 1,
                height: 1,
                makeProvider: { _ in nil }
            ) == nil
        )
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try image.pixelBuffer { _, _, _, _ in nil }
        }
        #expect(throws: P5ImageError.encodingFailed(.png)) {
            _ = try image.encoded(
                as: .png,
                quality: 1,
                createDestination: { _, _, _, _ in nil },
                finalize: { _ in true }
            )
        }
        #expect(throws: P5ImageError.encodingFailed(.png)) {
            _ = try image.encoded(
                as: .png,
                quality: 1,
                createDestination: CGImageDestinationCreateWithData,
                finalize: { _ in false }
            )
        }
    }

    @Test("Images crop, resize, mask, filter, sample, and expose typed failures")
    func imageProcessing() throws {
        let image = try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2,
                height: 2,
                bytes: [
                    255, 0, 0, 255,
                    0, 255, 0, 255,
                    0, 0, 255, 255,
                    255, 255, 255, 255,
                ]
            )
        )
        #expect(try image.color(x: 0, y: 0).red == 1)
        let crop = try image.cropped(to: CGRect(x: 1, y: 0, width: 1, height: 1))
        #expect(crop.size == CGSize(width: 1, height: 1))
        #expect(try crop.color(x: 0, y: 0).green == 1)

        #expect(P5ImageInterpolation.allCases == [.none, .low, .medium, .high])
        for interpolation in P5ImageInterpolation.allCases {
            let resized = try image.resized(
                to: CGSize(width: 4, height: 3),
                pixelDensity: 2,
                interpolation: interpolation
            )
            #expect(resized.pixelWidth == 8)
            #expect(resized.pixelHeight == 6)
            #expect(resized.size == CGSize(width: 4, height: 3))
        }
        #expect(try image.resized(to: CGSize(width: 1, height: 1)).pixelDensity == 1)

        let mask = try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2,
                height: 2,
                bytes: [
                    0, 0, 0, 255,
                    0, 0, 0, 0,
                    0, 0, 0, 255,
                    0, 0, 0, 0,
                ]
            )
        )
        let masked = try image.masked(with: mask)
        #expect(try masked.color(x: 0, y: 0).alpha == 1)
        #expect(try masked.color(x: 1, y: 0).alpha == 0)

        let filters: [P5ImageFilter] = [
            .invert,
            .grayscale,
            .sepia(intensity: 0.6),
            .gaussianBlur(radius: 1),
            .posterize(levels: 4),
        ]
        for filter in filters {
            let decoded = try JSONDecoder().decode(
                P5ImageFilter.self,
                from: JSONEncoder().encode(filter)
            )
            #expect(decoded == filter)
            #expect(try image.applying(filter).size == image.size)
        }
        #expect(try image.applying(.gaussianBlur(radius: 0)).size == image.size)

        #expect(throws: P5ImageError.processingFailed("crop")) {
            _ = try image.cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _ in nil }
        }
        #expect(throws: P5ImageError.processingFailed("filter")) {
            _ = try image.applying(.invert) { _, _ in nil }
        }
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try P5Image.renderBitmap(
                width: 1,
                height: 1,
                makeContext: { _, _ in nil },
                makeImage: { $0.makeImage() },
                draw: { _ in }
            )
        }
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try P5Image.renderBitmap(
                width: 1,
                height: 1,
                makeContext: P5ImageProcessingRuntime.makeContext,
                makeImage: { _ in nil },
                draw: { _ in }
            )
        }
        #expect(P5ImageError.processingFailed("mask").errorDescription?.contains("mask") == true)
    }

    @Test("Offscreen canvases persist pixels and draw whole, cropped, and tinted images")
    @MainActor
    func offscreenGraphicsAndDrawing() throws {
        let source = try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2,
                height: 1,
                bytes: [255, 0, 0, 255, 0, 255, 0, 255]
            )
        )
        let graphics = try P5Graphics(size: CGSize(width: 12, height: 8))
        graphics.noStroke()
        graphics.fill(P5Color(red: 0, green: 0, blue: 1))
        graphics.rect(0, 0, 2, 2)
        var snapshot = try graphics.snapshot()
        #expect(try snapshot.pixelBuffer().color(x: 1, y: 1).blue == 1)

        graphics.image(source, 2, 0, 4, 2)
        graphics.image(source, 0, 6)
        graphics.imageMode(.center)
        graphics.tint(P5Color(red: 0, green: 0, blue: 1, alpha: 1))
        graphics.image(source, 8, 1, 4, 2)
        graphics.noTint()
        graphics.tint(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        graphics.noTint()
        graphics.imageMode(.corners)
        graphics.image(
            source,
            destinationX: 2,
            destinationY: 4,
            destinationWidth: 6,
            destinationHeight: 6,
            sourceX: 1,
            sourceY: 0,
            sourceWidth: 1,
            sourceHeight: 1
        )
        graphics.image(
            source,
            destinationX: 10,
            destinationY: 7,
            destinationWidth: 1,
            destinationHeight: 1,
            sourceX: 0,
            sourceY: 0,
            sourceWidth: 0,
            sourceHeight: 1
        )
        snapshot = try graphics.snapshot()
        let pixels = try snapshot.pixelBuffer()
        #expect(pixels.color(x: 2, y: 0).red == 1)
        #expect(pixels.color(x: 5, y: 0).green == 1)
        #expect(pixels.color(x: 7, y: 1).blue == 1)
        #expect(pixels.color(x: 3, y: 4).green == 1)
        graphics.copy(
            source,
            source: CGRect(x: 0, y: 0, width: 2, height: 1),
            destination: CGRect(x: 0, y: 6, width: 2, height: 1)
        )
        for mode in P5BlendMode.allCases {
            graphics.blend(
                source,
                source: CGRect(x: 0, y: 0, width: 2, height: 1),
                destination: CGRect(x: 2, y: 6, width: 2, height: 1),
                mode: mode
            )
        }
        #expect(try graphics.snapshot().pixelBuffer().color(x: 0, y: 6).red == 1)

        var edited = try graphics.loadPixels()
        edited.setColor(P5Color(red: 1, green: 0, blue: 1), x: 0, y: 0)
        try graphics.updatePixels(edited)
        #expect(try graphics.snapshot().pixelBuffer().color(x: 0, y: 0).red == 1)
        graphics.translate(4, 4)
        graphics.clear()
        #expect(try graphics.snapshot().pixelBuffer().color(x: 0, y: 0).alpha == 0)

        let sketch = P5Sketch(size: CGSize(width: 4, height: 4))
        sketch.pixelDensity(2)
        let inherited = try sketch.createGraphics(2, 2)
        #expect(try inherited.snapshot().pixelDensity == 2)
        let explicit = try sketch.createGraphics(2, 2, pixelDensity: 1)
        #expect(try explicit.snapshot().pixelDensity == 1)
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try P5Graphics(
                size: CGSize(width: 1, height: 1),
                pixelDensity: 1,
                makeContext: { _, _ in nil }
            )
        }
        #expect(throws: P5ImageError.bitmapAllocationFailed) {
            _ = try explicit.snapshot(makeImage: { _ in nil })
        }
    }

    @Test("Invalid image and pixel arguments terminate at public boundaries")
    func invalidInputsTerminateTheProcess() async {
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PixelBuffer(width: 0, height: 1, bytes: [])
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PixelBuffer(width: 1, height: 0, bytes: [])
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PixelBuffer(width: 1, height: 1, pixelDensity: 0, bytes: [0, 0, 0, 0])
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PixelBuffer(width: 1, height: 1, bytes: [])
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0]).color(x: -1, y: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                var pixels = P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                pixels.setColor(P5Color(gray: 0), x: 0, y: 1)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = P5Image(cgImage: image.cgImage, pixelDensity: .nan)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                _ = try! P5Image.decode(P5ImageURLProtocol.pngData, pixelDensity: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.encoded(as: .png, quality: 2)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = try! P5Graphics(size: CGSize(width: 0, height: 1))
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    _ = try! P5Graphics(size: CGSize(width: 1, height: 1), pixelDensity: 0)
                }
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.color(x: -1, y: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.cropped(to: CGRect(x: 0, y: 0, width: 0, height: 1))
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.cropped(to: CGRect(x: 1, y: 0, width: 1, height: 1))
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.resized(to: CGSize(width: CGFloat.nan, height: 1))
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.resized(to: CGSize(width: 1, height: 1), pixelDensity: 0)
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.applying(.sepia(intensity: .nan))
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.applying(.gaussianBlur(radius: -1))
            }
        #endif
        #if os(macOS)
            await #expect(processExitsWith: .failure) {
                let image = try! P5Image(
                    pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
                )
                _ = try! image.applying(.posterize(levels: 1))
            }
        #endif
    }
}
