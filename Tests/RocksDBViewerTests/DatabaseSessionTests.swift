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
