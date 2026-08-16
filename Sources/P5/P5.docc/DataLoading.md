# Data Loading and Tables

Load local files and HTTP resources with Swift concurrency, typed failures, and validated table
state.

## Load bytes and text

``P5DataLoader`` uses mapped Foundation reads for file URLs and the supplied `URLSession` for
other URLs:

```swift
let loader = P5DataLoader()

let bytes = try await loader.data(from: resourceURL)
let text = try await loader.text(from: resourceURL)
```

HTTP responses outside `200...299` produce ``P5DataError/invalidHTTPStatus(_:)``. Non-HTTP
responses are accepted. Text decoding defaults to UTF-8; pass another `String.Encoding` when the
source contract requires it. File, session, and decoding diagnostics remain typed
``P5DataError`` values.

Every asynchronous entry point checks task cancellation before and after I/O. JSON and table
loading also check after their synchronous parsing step, so cancellation requested during a large
decode is observed before a value is returned. URLSession cancels its underlying request according
to Foundation's normal structured-concurrency behavior.

## Decode JSON

Request any `Decodable & Sendable` result. A fresh `JSONDecoder` prevents shared mutable decoder
configuration from crossing tasks:

```swift
struct Configuration: Decodable, Sendable {
    let count: Int
    let title: String
}

let configuration: Configuration = try await loader.json(from: jsonURL)
```

Schema, type, and malformed-document failures are wrapped in
``P5DataError/jsonDecodingFailed(_:)`` with the decoder diagnostic. For custom date, key, or data
strategies, load bytes with `data(from:)` and use an application-owned decoder.

## Parse delimited tables

Load comma-separated values with a header by default:

```swift
let table = try await loader.table(from: csvURL)
let name = try table.value(row: 0, column: "name")
let score = try table.double(row: 0, column: "score")
```

``P5Table`` preserves column and row order, requires unique nonempty column names, and requires
every row to have the same number of fields. Access by index, name, row dictionary, or finite
Double conversion reports explicit bounds, column, and conversion errors.

Use ``P5TableParsingOptions`` for TSV, semicolon, or pipe data and headerless records:

```swift
let table = try await loader.table(
    from: valuesURL,
    options: P5TableParsingOptions(
        delimiter: .tab,
        hasHeader: false,
        trimsWhitespace: true
    )
)
```

Headerless columns receive stable `column1`, `column2`, and subsequent names. The parser supports
quoted delimiters, escaped double quotes, multiline fields, CR, LF, and CRLF records. It
normalizes newlines inside quoted fields to `\n`, ignores a leading Unicode byte-order mark, and
rejects unclosed or misplaced quotes. Whitespace trimming applies to all fields, including quoted
values, only when explicitly enabled.

Parse already-loaded or generated content synchronously with
``P5DataLoader/table(text:options:)``. Tables, delimiters, and parsing options are `Codable`, and
decoding a table revalidates its complete structure.
