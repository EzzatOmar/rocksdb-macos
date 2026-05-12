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
}
