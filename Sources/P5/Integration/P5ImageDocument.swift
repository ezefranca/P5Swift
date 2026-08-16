import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Failures produced while reading or writing a native image document.
public enum P5ImageDocumentError: Error, Sendable, Hashable, LocalizedError {
    /// The selected Uniform Type Identifier is not a supported image representation.
    case unsupportedContentType(String)
    /// The file wrapper does not contain regular-file bytes.
    case missingFileContents

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .unsupportedContentType(let identifier):
            "The image document type '\(identifier)' is not supported."
        case .missingFileContents:
            "The image document does not contain regular-file data."
        }
    }
}

/// A value document for SwiftUI `DocumentGroup` and `fileExporter` workflows.
public struct P5ImageDocument: FileDocument, @unchecked Sendable {
    /// Image representations accepted by SwiftUI document groups.
    public static let readableContentTypes: [UTType] = [.png, .jpeg, .heic]

    /// Image representations offered by native file panels.
    public static let writableContentTypes: [UTType] = readableContentTypes

    /// Immutable image represented by this document.
    public let image: P5Image
    /// Representation used when the host does not select another supported type.
    public let format: P5ImageFormat
    /// Lossy compression quality in `0...1`.
    public let quality: CGFloat

    /// Creates a native image document.
    ///
    /// - Precondition: `quality` is finite and belongs to `0...1`.
    public init(image: P5Image, format: P5ImageFormat = .png, quality: CGFloat = 0.9) {
        precondition(quality.isFinite && (0...1).contains(quality))
        self.image = image
        self.format = format
        self.quality = quality
    }

    /// Reads and decodes a file selected by a native importer.
    public init(configuration: ReadConfiguration) throws {
        try self.init(contentType: configuration.contentType, file: configuration.file)
    }

    init(contentType: UTType, file: FileWrapper) throws {
        guard let format = P5ImageFormat(contentType: contentType) else {
            throw P5ImageDocumentError.unsupportedContentType(
                contentType.identifier
            )
        }
        guard file.isRegularFile, let data = file.regularFileContents else {
            throw P5ImageDocumentError.missingFileContents
        }
        self.init(image: try P5Image.decode(data), format: format)
    }

    /// Encodes the image for a native exporter.
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try fileWrapper(contentType: configuration.contentType)
    }

    func fileWrapper(contentType: UTType) throws -> FileWrapper {
        let selectedFormat = P5ImageFormat(contentType: contentType) ?? format
        return FileWrapper(
            regularFileWithContents: try image.encoded(as: selectedFormat, quality: quality)
        )
    }
}

extension P5ImageFormat {
    init?(contentType: UTType) {
        if contentType.conforms(to: .png) {
            self = .png
        } else if contentType.conforms(to: .jpeg) {
            self = .jpeg
        } else if contentType.conforms(to: .heic) || contentType.conforms(to: .heif) {
            self = .heif
        } else {
            return nil
        }
    }
}
