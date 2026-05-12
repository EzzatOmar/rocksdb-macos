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

    func testAddEditRenameAndDeleteSelectedRow() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-edit-\(UUID().uuidString)", isDirectory: true)
        let historyURL = root.appendingPathComponent("history/recent.json")
        let dbURL = root.appendingPathComponent("editable.rocksdb", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(historyStore: HistoryStore(fileURL: historyURL))
        let openMessage = await model.openDatabase(path: dbURL.path, mode: .readWrite, createIfMissing: true, selectedColumnFamily: "default", backupDirectory: nil)
        XCTAssertNil(openMessage)

        let addMessage = await model.saveKeyValue(mode: .add, keyText: "alpha", valueText: "one", encoding: .utf8)
        XCTAssertNil(addMessage)
        let addRowsLoaded = await model.waitForRows(path: dbURL.path)
        XCTAssertTrue(addRowsLoaded)
        var row = try XCTUnwrap(model.rows.first { $0.keyPreview.text == "alpha" })
        model.selectedRowID = row.id

        let editMessage = await model.saveKeyValue(mode: .edit, keyText: "alpha", valueText: "two", encoding: .utf8)
        XCTAssertNil(editMessage)
        let editRowsLoaded = await model.waitForRows(path: dbURL.path)
        XCTAssertTrue(editRowsLoaded)
        row = try XCTUnwrap(model.rows.first { $0.keyPreview.text == "alpha" })
        XCTAssertEqual(row.valuePreview.text, "two")
        model.selectedRowID = row.id

        let renameMessage = await model.saveKeyValue(mode: .edit, keyText: "beta", valueText: "three", encoding: .utf8)
        XCTAssertNil(renameMessage)
        let renameRowsLoaded = await model.waitForRows(path: dbURL.path)
        XCTAssertTrue(renameRowsLoaded)
        XCTAssertNil(model.rows.first { $0.keyPreview.text == "alpha" })
        row = try XCTUnwrap(model.rows.first { $0.keyPreview.text == "beta" })
        XCTAssertEqual(row.valuePreview.text, "three")
        model.selectedRowID = row.id

        let deleteMessage = await model.deleteSelectedKey()
        XCTAssertNil(deleteMessage)
        XCTAssertNil(model.rows.first { $0.keyPreview.text == "beta" })
    }

    func testReadOnlyAndSnapshotSelectionBlockWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rocksdb-viewer-write-guards-\(UUID().uuidString)", isDirectory: true)
        let historyURL = root.appendingPathComponent("history/recent.json")
        let dbURL = root.appendingPathComponent("guarded.rocksdb", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(historyStore: HistoryStore(fileURL: historyURL))
        let openMessage = await model.openDatabase(path: dbURL.path, mode: .readWrite, createIfMissing: true, selectedColumnFamily: "default", backupDirectory: nil)
        XCTAssertNil(openMessage)
        let addMessage = await model.saveKeyValue(mode: .add, keyText: "locked", valueText: "live", encoding: .utf8)
        XCTAssertNil(addMessage)
        let rowsLoaded = await model.waitForRows(path: dbURL.path)
        XCTAssertTrue(rowsLoaded)
        model.selectedRowID = try XCTUnwrap(model.rows.first?.id)

        model.createSnapshot()
        let snapshotAppeared = await waitUntil {
            !model.snapshots.isEmpty && model.selectedSnapshotID != nil
        }
        XCTAssertTrue(snapshotAppeared)
        XCTAssertFalse(model.canWrite)
        let snapshotEditMessage = await model.saveKeyValue(mode: .edit, keyText: "locked", valueText: "blocked", encoding: .utf8)
        XCTAssertEqual(snapshotEditMessage, "Snapshot views are read-only. Switch the snapshot selector back to Live to edit.")
        let snapshotDeleteMessage = await model.deleteSelectedKey()
        XCTAssertEqual(snapshotDeleteMessage, "Snapshot views are read-only. Switch the snapshot selector back to Live to edit.")

        model.selectedSnapshotID = nil
        XCTAssertTrue(model.canWrite)

        let readOnlyOpenMessage = await model.openDatabase(path: dbURL.path, mode: .readOnly, createIfMissing: false, selectedColumnFamily: "default", backupDirectory: nil)
        XCTAssertNil(readOnlyOpenMessage)
        let readOnlyAddMessage = await model.saveKeyValue(mode: .add, keyText: "read-only", valueText: "blocked", encoding: .utf8)
        XCTAssertEqual(readOnlyAddMessage, "Reopen the database in read-write mode to edit or delete rows.")
    }

    private func waitUntil(timeout seconds: TimeInterval = 5, condition: @MainActor @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
