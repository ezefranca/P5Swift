import Foundation
import Testing

@testable import P5

private final class P5DataURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "p5-data.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let data: Data
        switch url.path {
        case "/json":
            data = Data(#"{"name":"Ada","count":3}"#.utf8)
        case "/table":
            data = Data("name,value\nalpha,1\nbeta,2\n".utf8)
        case "/invalid-text":
            data = Data([0xFF])
        default:
            data = Data("remote".utf8)
        }
        let response: URLResponse
        if url.path == "/non-http" {
            response = URLResponse(
                url: url,
                mimeType: "text/plain",
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
        } else {
            response =
                HTTPURLResponse(
                    url: url,
                    statusCode: url.path == "/status" ? 503 : 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
                ?? URLResponse(
                    url: url,
                    mimeType: nil,
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("P5 native data loading", .serialized)
struct P5DataLoadingTests {
    @Test("Default local and URLSession loaders decode bytes, text, JSON, and tables")
    func nativeLoading() async throws {
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5Data-\(UUID().uuidString).txt"
        )
        defer { try? FileManager.default.removeItem(at: localURL) }
        try Data("local".utf8).write(to: localURL)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [P5DataURLProtocol.self]
        let loader = P5DataLoader(session: URLSession(configuration: configuration))
        #expect(try await loader.data(from: localURL) == Data("local".utf8))
        #expect(try await loader.text(from: localURL) == "local")

        let remote = try #require(URL(string: "https://p5-data.test/data"))
        #expect(try await loader.data(from: remote) == Data("remote".utf8))
        let nonHTTP = try #require(URL(string: "https://p5-data.test/non-http"))
        #expect(try await loader.text(from: nonHTTP) == "remote")
        let status = try #require(URL(string: "https://p5-data.test/status"))
        await #expect(throws: P5DataError.invalidHTTPStatus(503)) {
            _ = try await loader.data(from: status)
        }
        let invalidText = try #require(URL(string: "https://p5-data.test/invalid-text"))
        await #expect(throws: P5DataError.textDecodingFailed) {
            _ = try await loader.text(from: invalidText)
        }

        let jsonURL = try #require(URL(string: "https://p5-data.test/json"))
        let value: LoadedValue = try await loader.json(from: jsonURL)
        #expect(value == LoadedValue(name: "Ada", count: 3))
        await #expect(throws: P5DataError.self) {
            let _: [String] = try await loader.json(from: jsonURL)
        }

        let tableURL = try #require(URL(string: "https://p5-data.test/table"))
        let table = try await loader.table(from: tableURL)
        #expect(table.columns == ["name", "value"])
        #expect(table.rowCount == 2)
        #expect(try table.double(row: 1, column: "value") == 2)
    }

    @Test("Loading preserves typed failures, native diagnostics, and cancellation")
    func loadingFailures() async throws {
        let fileURL = URL(fileURLWithPath: "/missing-data")
        let remoteURL = try #require(URL(string: "https://missing.test/data"))

        var runtime = P5DataLoadingRuntime(
            localData: { _ in throw StubDataError.load },
            remoteData: { _ in throw StubDataError.load }
        )
        let failed = P5DataLoader(runtime: runtime)
        await #expect(throws: P5DataError.loadingFailed("load")) {
            _ = try await failed.data(from: fileURL)
        }
        await #expect(throws: P5DataError.loadingFailed("load")) {
            _ = try await failed.data(from: remoteURL)
        }

        runtime.localData = { _ in throw P5DataError.emptyTable }
        runtime.remoteData = { _ in throw P5DataError.textDecodingFailed }
        let typed = P5DataLoader(runtime: runtime)
        await #expect(throws: P5DataError.emptyTable) {
            _ = try await typed.data(from: fileURL)
        }
        await #expect(throws: P5DataError.textDecodingFailed) {
            _ = try await typed.data(from: remoteURL)
        }

        runtime.localData = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return Data()
        }
        runtime.remoteData = { url in
            withUnsafeCurrentTask { $0?.cancel() }
            return (
                Data(),
                URLResponse(
                    url: url,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            )
        }
        let cancelledAfterLoading = P5DataLoader(runtime: runtime)
        let cancelledLocal = Task {
            try await cancelledAfterLoading.data(from: fileURL)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledLocal.value
        }
        let cancelledRemote = Task {
            try await cancelledAfterLoading.data(from: remoteURL)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledRemote.value
        }

        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await P5DataLoader(runtime: runtime).data(from: fileURL)
        }
        await #expect(throws: CancellationError.self) { _ = try await preCancelled.value }
    }

    @Test("Delimited parsing covers quoting, line endings, delimiters, and inferred headers")
    func parsing() throws {
        let loader = P5DataLoader()
        let source =
            " name ,note,value\r\nalpha,\"hello, world\",1\rbeta,\"line 1\r\nline 2\",2\n"
            + "gamma,\"a \"\"quote\"\"\",3"
        let csv = try loader.table(
            text: source,
            options: P5TableParsingOptions(trimsWhitespace: true)
        )
        #expect(csv.columns == ["name", "note", "value"])
        #expect(csv.rows[0] == ["alpha", "hello, world", "1"])
        #expect(csv.rows[1][1] == "line 1\nline 2")
        #expect(csv.rows[2][1] == "a \"quote\"")

        for delimiter in P5TableDelimiter.allCases {
            let separator = String(delimiter.character)
            let table = try loader.table(
                text: "a\(separator)b\n1\(separator)2",
                options: P5TableParsingOptions(delimiter: delimiter)
            )
            #expect(table.rows == [["1", "2"]])
        }

        let inferred = try loader.table(
            text: "a\tb\n\"\"\t2\n",
            options: P5TableParsingOptions(delimiter: .tab, hasHeader: false)
        )
        #expect(inferred.columns == ["column1", "column2"])
        #expect(inferred.rows == [["a", "b"], ["", "2"]])

        let trailing = try loader.table(
            text: "a,b,\n1,2,\n",
            options: P5TableParsingOptions(hasHeader: false)
        )
        #expect(trailing.columns == ["column1", "column2", "column3"])
        #expect(trailing.rows == [["a", "b", ""], ["1", "2", ""]])

        let quotedLines = try loader.table(
            text: "\"a\"\n\"b\"\n",
            options: P5TableParsingOptions(hasHeader: false)
        )
        #expect(quotedLines.rows == [["a"], ["b"]])

        let byteOrderMarked = try loader.table(text: "\u{FEFF}name,value\nalpha,1")
        #expect(byteOrderMarked.columns == ["name", "value"])
    }

    @Test("Malformed delimited text reports stable row diagnostics")
    func malformedParsing() throws {
        let loader = P5DataLoader()
        #expect(throws: P5DataError.emptyTable) { _ = try loader.table(text: "") }
        #expect(throws: P5DataError.self) { _ = try loader.table(text: "\n") }
        #expect(throws: P5DataError.self) { _ = try loader.table(text: "a,b\n1") }
        #expect(throws: P5DataError.self) { _ = try loader.table(text: "a,a\n1,2") }
        #expect(throws: P5DataError.self) { _ = try loader.table(text: "a,b\nva\"lue,2") }
        #expect(throws: P5DataError.self) { _ = try loader.table(text: "a,b\n\"value\"x,2") }
        #expect(throws: P5DataError.self) { _ = try loader.table(text: "a,b\n\"value,2") }
    }

    @Test("Table state, accessors, and decoding preserve structural invariants")
    func tableValues() throws {
        let table = try P5Table(
            columns: ["name", "value"],
            rows: [["alpha", "1.5"], ["beta", "nan"]]
        )
        #expect(table.rowCount == 2)
        #expect(table.columnCount == 2)
        #expect(try table.value(row: 0, column: 0) == "alpha")
        #expect(try table.value(row: 0, column: "value") == "1.5")
        #expect(try table.dictionary(row: 0) == ["name": "alpha", "value": "1.5"])
        #expect(try table.double(row: 0, column: "value") == 1.5)
        #expect(
            try JSONDecoder().decode(
                P5Table.self,
                from: JSONEncoder().encode(table)
            ) == table
        )

        #expect(throws: P5DataError.rowOutOfBounds(2)) {
            _ = try table.value(row: 2, column: 0)
        }
        #expect(throws: P5DataError.unknownColumn("2")) {
            _ = try table.value(row: 0, column: 2)
        }
        #expect(throws: P5DataError.unknownColumn("missing")) {
            _ = try table.value(row: 0, column: "missing")
        }
        #expect(throws: P5DataError.rowOutOfBounds(-1)) {
            _ = try table.dictionary(row: -1)
        }
        #expect(throws: P5DataError.numberParsingFailed("nan")) {
            _ = try table.double(row: 1, column: "value")
        }

        #expect(throws: P5DataError.emptyTable) { _ = try P5Table(columns: [], rows: []) }
        #expect(throws: P5DataError.self) { _ = try P5Table(columns: [""], rows: []) }
        #expect(throws: P5DataError.duplicateColumn("a")) {
            _ = try P5Table(columns: ["a", "a"], rows: [])
        }
        #expect(throws: P5DataError.self) {
            _ = try P5Table(columns: ["a", "b"], rows: [["1"]])
        }

        let invalidJSON = [
            #"{"columns":[],"rows":[]}"#,
            #"{"columns":["a","a"],"rows":[]}"#,
            #"{"columns":["a","b"],"rows":[["1"]]}"#,
        ]
        for json in invalidJSON {
            #expect(throws: P5DataError.self) {
                _ = try JSONDecoder().decode(P5Table.self, from: Data(json.utf8))
            }
        }
    }

    @Test("Options and errors provide stable serialized and diagnostic values")
    func supportValues() throws {
        for delimiter in P5TableDelimiter.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5TableDelimiter.self,
                    from: JSONEncoder().encode(delimiter)
                ) == delimiter
            )
        }
        let options = P5TableParsingOptions(
            delimiter: .semicolon,
            hasHeader: false,
            trimsWhitespace: true
        )
        #expect(
            try JSONDecoder().decode(
                P5TableParsingOptions.self,
                from: JSONEncoder().encode(options)
            ) == options
        )
        let errors: [P5DataError] = [
            .loadingFailed("reason"),
            .invalidHTTPStatus(500),
            .textDecodingFailed,
            .jsonDecodingFailed("reason"),
            .emptyTable,
            .malformedTable(row: 2, reason: "reason"),
            .duplicateColumn("name"),
            .unknownColumn("name"),
            .rowOutOfBounds(2),
            .numberParsingFailed("value"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

private struct LoadedValue: Sendable, Equatable, Codable {
    let name: String
    let count: Int
}

private enum StubDataError: String, Error, LocalizedError {
    case load

    var errorDescription: String? { rawValue }
}
