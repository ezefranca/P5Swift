import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import P5

@Suite("P5 native image documents", .serialized)
struct P5ImageDocumentTests {
    @Test("Native file documents read and write every supported representation")
    func readAndWrite() throws {
        let image = try P5Image(
            pixelBuffer: P5PixelBuffer(
                width: 2,
                height: 1,
                bytes: [255, 0, 0, 255, 0, 255, 0, 255]
            )
        )
        #expect(P5ImageDocument.readableContentTypes == [.png, .jpeg, .heic])
        #expect(P5ImageDocument.writableContentTypes == [.png, .jpeg, .heic])

        let contentTypes: [(UTType, P5ImageFormat)] = [
            (.png, .png), (.jpeg, .jpeg), (.heic, .heif), (.heif, .heif),
        ]
        for (contentType, expectedFormat) in contentTypes {
            let document = P5ImageDocument(image: image, format: expectedFormat, quality: 0.8)
            #expect(document.image.pixelWidth == 2)
            #expect(document.format == expectedFormat)
            #expect(document.quality == 0.8)

            let wrapper = try document.fileWrapper(contentType: contentType)
            let protocolWrapper = try document.fileWrapper(
                configuration: try writeConfiguration(contentType: contentType)
            )
            let data = try #require(wrapper.regularFileContents)
            #expect(data.isEmpty == false)
            #expect(protocolWrapper.regularFileContents == data)

            let decoded = try P5ImageDocument(contentType: contentType, file: wrapper)
            let protocolDecoded = try P5ImageDocument(
                configuration: try readConfiguration(contentType: contentType, file: wrapper)
            )
            #expect(decoded.image.pixelWidth == 2)
            #expect(decoded.format == expectedFormat)
            #expect(protocolDecoded.format == expectedFormat)
        }

        let fallback = P5ImageDocument(image: image, format: .png)
        let wrapper = try fallback.fileWrapper(contentType: .data)
        let source = try #require(wrapper.regularFileContents)
        #expect(try P5Image.decode(source).pixelWidth == 2)
    }

    @Test("Malformed native documents report typed failures")
    func malformedDocuments() throws {
        let regularFile = FileWrapper(regularFileWithContents: Data([1, 2, 3]))
        #expect(throws: P5ImageDocumentError.unsupportedContentType(UTType.data.identifier)) {
            _ = try P5ImageDocument(contentType: .data, file: regularFile)
        }
        #expect(throws: P5ImageDocumentError.missingFileContents) {
            _ = try P5ImageDocument(
                contentType: .png,
                file: FileWrapper(directoryWithFileWrappers: [:])
            )
        }

        let errors: [P5ImageDocumentError] = [
            .unsupportedContentType("public.unknown"), .missingFileContents,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Invalid document quality terminates at the public boundary")
    func invalidQualityTerminatesTheProcess() async {
        await #expect(processExitsWith: .failure) {
            let image = try! P5Image(
                pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
            )
            _ = P5ImageDocument(image: image, quality: .nan)
        }
        await #expect(processExitsWith: .failure) {
            let image = try! P5Image(
                pixelBuffer: P5PixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
            )
            _ = P5ImageDocument(image: image, quality: 2)
        }
    }

    private func readConfiguration(
        contentType: UTType,
        file: FileWrapper
    ) throws -> FileDocumentReadConfiguration {
        struct Layout {
            let contentType: UTType
            let file: FileWrapper
        }
        try #require(
            MemoryLayout<Layout>.size == MemoryLayout<FileDocumentReadConfiguration>.size
        )
        return unsafeBitCast(
            Layout(contentType: contentType, file: file),
            to: FileDocumentReadConfiguration.self
        )
    }

    private func writeConfiguration(
        contentType: UTType
    ) throws -> FileDocumentWriteConfiguration {
        struct Layout {
            let contentType: UTType
            let existingFile: FileWrapper?
        }
        try #require(
            MemoryLayout<Layout>.size == MemoryLayout<FileDocumentWriteConfiguration>.size
        )
        return unsafeBitCast(
            Layout(contentType: contentType, existingFile: nil),
            to: FileDocumentWriteConfiguration.self
        )
    }
}
