import XCTest
@testable import RocksDBViewer

final class HistoryStoreTests: XCTestCase {
    func testHistoryStoresMetadataOnly() {
        let store = HistoryStore()
        let recent = RecentDatabase(
            id: UUID(),
            path: "/tmp/example.rocksdb",
            displayName: "example.rocksdb",
            lastOpenedAt: .now,
            openMode: .readOnly,
            selectedColumnFamily: "default",
            comparatorProfileID: "builtin.bytewise",
            lastKnownColumnFamilies: ["default"]
        )

        store.save([recent])
        defer { store.clear() }

        let loaded = store.load()

        XCTAssertEqual(loaded.first?.path, recent.path)
        XCTAssertEqual(loaded.first?.lastKnownColumnFamilies, ["default"])
    }
}

final class ComparatorRegistryTests: XCTestCase {
    func testBuiltInComparatorValidationPasses() {
        let registry = ComparatorRegistry()

        for profile in registry.builtIns {
            XCTAssertTrue(registry.validate(profile).isValid)
        }
    }

    func testCustomComparatorRequiresExistingBundle() {
        let registry = ComparatorRegistry()
        let profile = ComparatorProfile(id: "custom", name: "Custom", kind: .customBundle, bundlePath: "/missing.bundle", comparatorIdentifier: "custom.id", sampleKeys: [])

        XCTAssertFalse(registry.validate(profile).isValid)
    }
}
