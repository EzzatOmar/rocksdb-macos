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

    func testBytePreviewFallsBackToHexForControlBytes() {
        let preview = BytePreview(bytes: Data([0, 1, 2, 3]), preferredDisplay: .utf8)

        XCTAssertEqual(preview.text, "00 01 02 03")
    }

    func testBuiltInComparatorIdentifiersAreStable() {
        let ids = ComparatorProfile.builtIns.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains("builtin.bytewise"))
        XCTAssertTrue(ComparatorProfile.builtIns.allSatisfy { !$0.comparatorIdentifier.isEmpty })
    }

    func testHexCodecRejectsInvalidInput() {
        XCTAssertThrowsError(try HexCodec.decode("abc"))
        XCTAssertThrowsError(try HexCodec.decode("zz"))
        XCTAssertEqual(try HexCodec.decode("68 69"), Data("hi".utf8))
    }

    func testJSONEncodingValidatesInput() {
        XCTAssertNoThrow(try AppModel.decode(#"{"ok":true}"#, encoding: .json))
        XCTAssertThrowsError(try AppModel.decode("{", encoding: .json))
    }
}
