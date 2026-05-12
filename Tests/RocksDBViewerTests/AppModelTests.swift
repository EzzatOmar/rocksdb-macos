import XCTest
@testable import RocksDBViewer

@MainActor
final class AppModelTests: XCTestCase {
    func testOpenFixturePopulatesVisibleRows() async throws {
        let fixturePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("jazz.rocksdb", isDirectory: true)
            .path

        guard FileManager.default.fileExists(atPath: fixturePath) else {
            throw XCTSkip("Local jazz.rocksdb fixture is not present.")
        }

        let model = AppModel()
        model.openPlaceholder(path: fixturePath, mode: .readOnly)

        let hasRows = await model.waitForRows(path: fixturePath, timeout: 5)

        XCTAssertTrue(hasRows)
        XCTAssertEqual(model.activeDatabasePath, fixturePath)
        XCTAssertFalse(model.rows.isEmpty)
        XCTAssertFalse(model.rows[0].keyPreview.bytes.isEmpty)
    }

    func testCreateIfMissingOpenAddsHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-app-model-\(UUID().uuidString)", isDirectory: true)
        let historyURL = root.appendingPathComponent("history/recent.json")
        let dbURL = root.appendingPathComponent("created.rocksdb", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(historyStore: HistoryStore(fileURL: historyURL))
        let message = await model.openDatabase(
            path: dbURL.path,
            mode: .readWrite,
            createIfMissing: true,
            selectedColumnFamily: "default",
            backupDirectory: root.appendingPathComponent("backups", isDirectory: true).path
        )

        XCTAssertNil(message)
        XCTAssertEqual(model.activeDatabasePath, dbURL.path)
        XCTAssertEqual(model.recentDatabases.first?.path, dbURL.path)
        XCTAssertEqual(model.recentDatabases.first?.backupDirectory, root.appendingPathComponent("backups", isDirectory: true).path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
    }

    func testFailedOpenDoesNotAddHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-failed-open-\(UUID().uuidString)", isDirectory: true)
        let historyURL = root.appendingPathComponent("history/recent.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(historyStore: HistoryStore(fileURL: historyURL))
        let message = await model.openDatabase(
            path: root.appendingPathComponent("missing.rocksdb", isDirectory: true).path,
            mode: .readOnly,
            createIfMissing: false,
            selectedColumnFamily: "default",
            backupDirectory: nil
        )

        XCTAssertNotNil(message)
        XCTAssertNil(model.activeDatabasePath)
        XCTAssertTrue(model.recentDatabases.isEmpty)
    }

    func testRecentHistoryCanSeedReopen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-recent-\(UUID().uuidString)", isDirectory: true)
        let historyURL = root.appendingPathComponent("history/recent.json")
        let dbURL = root.appendingPathComponent("recent.rocksdb", isDirectory: true)
        let backupURL = root.appendingPathComponent("backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var firstModel: AppModel? = AppModel(historyStore: HistoryStore(fileURL: historyURL))
        let firstOpenMessage = await firstModel!.openDatabase(path: dbURL.path, mode: .readWrite, createIfMissing: true, selectedColumnFamily: "default", backupDirectory: backupURL.path)
        XCTAssertNil(firstOpenMessage)
        firstModel = nil

        let secondModel = AppModel(historyStore: HistoryStore(fileURL: historyURL))
        let recent = try XCTUnwrap(secondModel.recentDatabases.first)
        XCTAssertEqual(recent.backupDirectory, backupURL.path)

        let message = await secondModel.openDatabase(
            path: recent.path,
            mode: recent.openMode,
            createIfMissing: false,
            selectedColumnFamily: recent.selectedColumnFamily,
            backupDirectory: recent.backupDirectory
        )

        XCTAssertNil(message)
        XCTAssertEqual(secondModel.activeDatabasePath, dbURL.path)
        XCTAssertEqual(secondModel.backupDirectory, backupURL.path)
    }
}
