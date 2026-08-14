import CoreGraphics

struct TestPixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    static let clear = TestPixel(red: 0, green: 0, blue: 0, alpha: 0)
    static let white = TestPixel(red: 255, green: 255, blue: 255, alpha: 255)
    static let red = TestPixel(red: 255, green: 0, blue: 0, alpha: 255)
    static let green = TestPixel(red: 0, green: 255, blue: 0, alpha: 255)
}

final class TestBitmap {
    let context: CGContext

    private let bytes: UnsafeMutablePointer<UInt8>
    private let width: Int
    private let height: Int

    init?(width: Int, height: Int) {
        let bytesPerRow = width * 4
        let bytes = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bytesPerRow * height
        )
        bytes.initialize(repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            bytes.deallocate()
            return nil
        }

        self.context = context
        self.bytes = bytes
        self.width = width
        self.height = height
    }

    func pixel(atX x: Int, y: Int) -> TestPixel {
        precondition((0..<width).contains(x) && (0..<height).contains(y))

        let memoryRow = height - 1 - y
        let offset = (memoryRow * width + x) * 4
        return TestPixel(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }

    deinit {
        bytes.deallocate()
    }
}
