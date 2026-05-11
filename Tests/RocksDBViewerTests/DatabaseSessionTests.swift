import XCTest
@testable import RocksDBViewer

final class DatabaseSessionTests: XCTestCase {
    func testCreatePutGetDeleteInTemporaryDatabase() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DatabaseSession()
        let metadata = try await session.open(DatabaseOpenRequest(path: url.path, mode: .readWrite, createIfMissing: true, selectedColumnFamily: "default"))

        XCTAssertEqual(metadata.selectedColumnFamily, "default")
        XCTAssertTrue(metadata.columnFamilies.contains("default"))

        let key = Data("hello".utf8)
        let value = Data("world".utf8)
        try await session.put(columnFamily: "default", key: key, value: value)
        let fetched = try await session.get(columnFamily: "default", key: key)

        XCTAssertEqual(fetched, value)

        try await session.delete(columnFamily: "default", key: key)
        let missing = try await session.get(columnFamily: "default", key: key)

        XCTAssertNil(missing)
    }

    func testRangeAndPrefixScanAreBounded() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = DatabaseSession()
        _ = try await session.open(DatabaseOpenRequest(path: url.path, mode: .readWrite, createIfMissing: true, selectedColumnFamily: "default"))

        for index in 0..<20 {
            let key = Data(String(format: "user:%03d", index).utf8)
            let value = Data(repeating: UInt8(index), count: 8)
            try await session.put(columnFamily: "default", key: key, value: value)
        }
        try await session.put(columnFamily: "default", key: Data("system:000".utf8), value: Data("skip".utf8))

        let prefixRows = try await session.scanRows(ScanRequest(
            columnFamily: "default",
            mode: .prefix,
            lowerBound: nil,
            upperBound: nil,
            prefix: Data("user:".utf8),
            limit: 5,
            direction: .forward,
            snapshotID: nil,
            previewByteLimit: 4
        ))

        XCTAssertEqual(prefixRows.count, 5)
        XCTAssertTrue(prefixRows.allSatisfy { $0.keyPreview.text.hasPrefix("user:") })
        XCTAssertTrue(prefixRows.allSatisfy { $0.valuePreview.bytes.count == 4 && $0.valuePreview.isTruncated })

        let reverseRows = try await session.scanRows(ScanRequest(
            columnFamily: "default",
            mode: .range,
            lowerBound: Data("user:005".utf8),
            upperBound: Data("user:010".utf8),
            prefix: nil,
            limit: 10,
            direction: .reverse,
            snapshotID: nil,
            previewByteLimit: 8
        ))

        XCTAssertEqual(reverseRows.first?.keyPreview.text, "user:009")
        XCTAssertEqual(reverseRows.last?.keyPreview.text, "user:005")
    }

    func testIncludedFixtureCanBeOpenedReadOnlyWhenPresent() async throws {
        let fixturePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("jazz.rocksdb", isDirectory: true)
            .path

        guard FileManager.default.fileExists(atPath: fixturePath) else {
            throw XCTSkip("Local jazz.rocksdb fixture is not present.")
        }

        let session = DatabaseSession()
        let metadata = try await session.open(DatabaseOpenRequest(path: fixturePath, mode: .readOnly, createIfMissing: false, selectedColumnFamily: "default"))

        XCTAssertTrue(metadata.columnFamilies.contains("default"))
        XCTAssertEqual(metadata.openMode, .readOnly)
    }
}
