import XCTest
@testable import RocksDBViewer

final class ModelTests: XCTestCase {
    func testBytePreviewTruncatesToLimit() {
        let data = Data(repeating: 0x61, count: 16)
        let preview = BytePreview(bytes: data, limit: 4)

        XCTAssertEqual(preview.bytes.count, 4)
        XCTAssertEqual(preview.totalSize, 16)
        XCTAssertTrue(preview.isTruncated)
    }

    func testBuiltInComparatorIdentifiersAreStable() {
        let ids = ComparatorProfile.builtIns.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains("builtin.bytewise"))
        XCTAssertTrue(ComparatorProfile.builtIns.allSatisfy { !$0.comparatorIdentifier.isEmpty })
    }
}
