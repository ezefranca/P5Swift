import Foundation

/// Failures produced by native data loading and table access.
public enum P5DataError: Error, Sendable, Hashable, LocalizedError {
    /// File or network loading failed before a response could be validated.
    case loadingFailed(String)
    /// An HTTP server returned a status outside `200...299`.
    case invalidHTTPStatus(Int)
    /// Loaded bytes cannot be represented with the requested text encoding.
    case textDecodingFailed
    /// Loaded JSON does not match the requested Decodable type.
    case jsonDecodingFailed(String)
    /// A table source has no header or data record from which to infer columns.
    case emptyTable
    /// A table record is malformed or has an inconsistent number of fields.
    case malformedTable(row: Int, reason: String)
    /// A table contains the same column name more than once.
    case duplicateColumn(String)
    /// A requested column name is absent.
    case unknownColumn(String)
    /// A requested row index is outside the table.
    case rowOutOfBounds(Int)
    /// A cell cannot be represented as a finite Double.
    case numberParsingFailed(String)

    /// A localized description suitable for diagnostics and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .loadingFailed(let reason):
            "Data could not be loaded: \(reason)"
        case .invalidHTTPStatus(let status):
            "The server returned HTTP status \(status)."
        case .textDecodingFailed:
            "Loaded data is not valid text in the requested encoding."
        case .jsonDecodingFailed(let reason):
            "Loaded JSON could not be decoded: \(reason)"
        case .emptyTable:
            "The table does not contain any records."
        case .malformedTable(let row, let reason):
            "Table row \(row) is malformed: \(reason)"
        case .duplicateColumn(let name):
            "The table contains duplicate column \(name)."
        case .unknownColumn(let name):
            "The table does not contain column \(name)."
        case .rowOutOfBounds(let row):
            "Table row \(row) is outside the available rows."
        case .numberParsingFailed(let value):
            "Table value \(value) is not a finite number."
        }
    }
}

/// Supported single-character delimiters for ``P5Table`` parsing.
public enum P5TableDelimiter: String, Sendable, Hashable, Codable, CaseIterable {
    /// Comma-separated values.
    case comma
    /// Tab-separated values.
    case tab
    /// Semicolon-separated values.
    case semicolon
    /// Pipe-separated values.
    case pipe

    var character: Character {
        switch self {
        case .comma: ","
        case .tab: "\t"
        case .semicolon: ";"
        case .pipe: "|"
        }
    }
}

/// Controls delimited text parsing into ``P5Table``.
public struct P5TableParsingOptions: Sendable, Hashable, Codable {
    /// Field delimiter used outside quoted values.
    public let delimiter: P5TableDelimiter
    /// Whether the first record supplies column names.
    public let hasHeader: Bool
    /// Whether leading and trailing whitespace is removed from every field.
    public let trimsWhitespace: Bool

    /// Creates table parsing options.
    public init(
        delimiter: P5TableDelimiter = .comma,
        hasHeader: Bool = true,
        trimsWhitespace: Bool = false
    ) {
        self.delimiter = delimiter
        self.hasHeader = hasHeader
        self.trimsWhitespace = trimsWhitespace
    }
}

/// A validated, immutable table with stable column and row ordering.
public struct P5Table: Sendable, Hashable, Codable {
    private enum CodingKeys: String, CodingKey {
        case columns, rows
    }

    /// Ordered, unique, nonempty column names.
    public let columns: [String]
    /// Ordered rows whose field count matches `columns`.
    public let rows: [[String]]

    /// Number of data rows.
    public var rowCount: Int { rows.count }
    /// Number of fields in every row.
    public var columnCount: Int { columns.count }

    /// Creates a table while validating column and row structure.
    public init(columns: [String], rows: [[String]]) throws {
        guard columns.isEmpty == false else { throw P5DataError.emptyTable }
        guard columns.contains(where: \.isEmpty) == false else {
            throw P5DataError.malformedTable(row: 0, reason: "Column names cannot be empty.")
        }
        var seen = Set<String>()
        for column in columns where seen.insert(column).inserted == false {
            throw P5DataError.duplicateColumn(column)
        }
        for (index, row) in rows.enumerated() where row.count != columns.count {
            throw P5DataError.malformedTable(
                row: index,
                reason: "Expected \(columns.count) fields but found \(row.count)."
            )
        }
        self.columns = columns
        self.rows = rows
    }

    /// Decodes a table while preserving all structural invariants.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            columns: container.decode([String].self, forKey: .columns),
            rows: container.decode([[String]].self, forKey: .rows)
        )
    }

    /// Encodes columns and rows with stable field names.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
    }

    /// Returns a cell by zero-based row and column index.
    public func value(row: Int, column: Int) throws -> String {
        guard rows.indices.contains(row) else { throw P5DataError.rowOutOfBounds(row) }
        guard columns.indices.contains(column) else {
            throw P5DataError.unknownColumn(String(column))
        }
        return rows[row][column]
    }

    /// Returns a cell by zero-based row index and column name.
    public func value(row: Int, column: String) throws -> String {
        guard let columnIndex = columns.firstIndex(of: column) else {
            throw P5DataError.unknownColumn(column)
        }
        return try value(row: row, column: columnIndex)
    }

    /// Returns one row as a dictionary without discarding column ordering in the table itself.
    public func dictionary(row: Int) throws -> [String: String] {
        guard rows.indices.contains(row) else { throw P5DataError.rowOutOfBounds(row) }
        return Dictionary(uniqueKeysWithValues: zip(columns, rows[row]))
    }

    /// Parses a named cell as a finite Double.
    public func double(row: Int, column: String) throws -> Double {
        let text = try value(row: row, column: column)
        guard let number = Double(text), number.isFinite else {
            throw P5DataError.numberParsingFailed(text)
        }
        return number
    }
}

/// Sendable Foundation loader for local files, HTTP data, text, JSON, and tables.
public struct P5DataLoader: Sendable {
    private let runtime: P5DataLoadingRuntime

    /// Creates a loader backed by the supplied URL session and mapped local file reads.
    public init(session: URLSession = .shared) {
        runtime = P5DataLoadingRuntime(session: session)
    }

    init(runtime: P5DataLoadingRuntime) {
        self.runtime = runtime
    }

    /// Loads bytes from a local file or URLSession request.
    public func data(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        do {
            if url.isFileURL {
                let data = try await runtime.localData(url)
                try Task.checkCancellation()
                return data
            }
            let (data, response) = try await runtime.remoteData(url)
            try Task.checkCancellation()
            if let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode) == false
            {
                throw P5DataError.invalidHTTPStatus(response.statusCode)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as P5DataError {
            throw error
        } catch {
            throw P5DataError.loadingFailed(error.localizedDescription)
        }
    }

    /// Loads and decodes text with an explicit Foundation string encoding.
    public func text(from url: URL, encoding: String.Encoding = .utf8) async throws -> String {
        let data = try await data(from: url)
        guard let text = String(data: data, encoding: encoding) else {
            throw P5DataError.textDecodingFailed
        }
        try Task.checkCancellation()
        return text
    }

    /// Loads JSON and decodes a Sendable value with a fresh JSONDecoder.
    public func json<Value: Decodable & Sendable>(
        _ type: Value.Type = Value.self,
        from url: URL
    ) async throws -> Value {
        let data = try await data(from: url)
        let value: Value
        do {
            value = try JSONDecoder().decode(type, from: data)
        } catch {
            throw P5DataError.jsonDecodingFailed(String(describing: error))
        }
        try Task.checkCancellation()
        return value
    }

    /// Loads delimited text and parses it into a validated table.
    public func table(
        from url: URL,
        options: P5TableParsingOptions = P5TableParsingOptions()
    ) async throws -> P5Table {
        let loadedText = try await text(from: url)
        let table = try table(text: loadedText, options: options)
        try Task.checkCancellation()
        return table
    }

    /// Parses already-loaded delimited text into a validated table.
    public func table(
        text: String,
        options: P5TableParsingOptions = P5TableParsingOptions()
    ) throws -> P5Table {
        let records = try P5DelimitedTextParser.parse(
            text,
            delimiter: options.delimiter.character,
            trimsWhitespace: options.trimsWhitespace
        )
        guard let first = records.first else { throw P5DataError.emptyTable }
        if options.hasHeader {
            return try P5Table(columns: first, rows: Array(records.dropFirst()))
        }
        let columns = first.indices.map { "column\($0 + 1)" }
        return try P5Table(columns: columns, rows: records)
    }
}

struct P5DataLoadingRuntime: @unchecked Sendable {
    var localData: @Sendable (URL) async throws -> Data
    var remoteData: @Sendable (URL) async throws -> (Data, URLResponse)

    init(session: URLSession) {
        localData = { url in
            try await Task.detached {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
        remoteData = { try await session.data(from: $0) }
    }

    init(
        localData: @escaping @Sendable (URL) async throws -> Data,
        remoteData: @escaping @Sendable (URL) async throws -> (Data, URLResponse)
    ) {
        self.localData = localData
        self.remoteData = remoteData
    }
}

enum P5DelimitedTextParser {
    private enum State: Equatable {
        case unquoted
        case quoted
        case quoteClosed
    }

    static func parse(
        _ text: String,
        delimiter: Character,
        trimsWhitespace: Bool
    ) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var state = State.unquoted
        var index = text.startIndex
        var justEndedRecord = false

        if index < text.endIndex, text[index] == "\u{FEFF}" {
            index = text.index(after: index)
        }

        func completedField(_ value: String) -> String {
            trimsWhitespace ? value.trimmingCharacters(in: .whitespaces) : value
        }
        func finishField() {
            record.append(completedField(field))
            field = ""
        }
        func finishRecord() {
            finishField()
            records.append(record)
            record = []
            justEndedRecord = true
        }

        while index < text.endIndex {
            let character = text[index]
            let isNewline = character == "\n" || character == "\r" || character == "\r\n"
            switch state {
            case .unquoted:
                if character == delimiter {
                    finishField()
                    justEndedRecord = false
                } else if isNewline {
                    finishRecord()
                } else if character == "\"" {
                    guard field.isEmpty else {
                        throw P5DataError.malformedTable(
                            row: records.count,
                            reason: "A quote appeared inside an unquoted field."
                        )
                    }
                    state = .quoted
                    justEndedRecord = false
                } else {
                    field.append(character)
                    justEndedRecord = false
                }
            case .quoted:
                if character == "\"" {
                    state = .quoteClosed
                } else if isNewline {
                    field.append("\n")
                } else {
                    field.append(character)
                }
            case .quoteClosed:
                if character == "\"" {
                    field.append("\"")
                    state = .quoted
                } else if character == delimiter {
                    finishField()
                    state = .unquoted
                    justEndedRecord = false
                } else if isNewline {
                    finishRecord()
                    state = .unquoted
                } else {
                    throw P5DataError.malformedTable(
                        row: records.count,
                        reason: "Unexpected text followed a closing quote."
                    )
                }
            }
            index = text.index(after: index)
        }

        guard state != .quoted else {
            throw P5DataError.malformedTable(
                row: records.count,
                reason: "A quoted field was not terminated."
            )
        }
        if justEndedRecord == false,
            field.isEmpty == false || record.isEmpty == false || state == .quoteClosed
        {
            finishRecord()
        }
        return records
    }
}
