import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let retainedRowLimit = 2_000

    @Published var selectedSection: NavigationSection = .browser
    @Published var recentDatabases: [RecentDatabase] = []
    @Published var columnFamilies: [String] = ["default"]
    @Published var selectedColumnFamily = "default"
    @Published var comparatorProfile = ComparatorProfile.builtIns[0]
    @Published var rows: [KeyValueRow] = KeyValueRow.sampleRows
    @Published var selectedRowID: KeyValueRow.ID?
    @Published var snapshots: [SnapshotRecord] = []
    @Published var backups: [BackupRecord] = []
    @Published var operations: [OperationRecord] = []
    @Published var openDatabaseSheetPresented = false
    @Published var editSheetMode: EditSheetMode?
    @Published var activeDatabasePath: String?
    @Published var openMode: OpenMode = .readOnly
    @Published var scanMode: ScanMode = .range
    @Published var scanDirection: ScanDirection = .forward
    @Published var keyEncoding: ValueDisplayMode = .utf8
    @Published var lowerBound = ""
    @Published var upperBound = ""
    @Published var prefix = ""
    @Published var exactKey = ""
    @Published var scanLimit = 256

    var selectedRow: KeyValueRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
    }

    var canWrite: Bool {
        activeDatabasePath != nil && openMode == .readWrite
    }

    var canEditSelection: Bool {
        canWrite && selectedRow != nil
    }

    func presentOpenDatabase() {
        openDatabaseSheetPresented = true
    }

    func presentEditSheet(mode: EditSheetMode) {
        editSheetMode = mode
    }

    func refreshCurrentScan() {
        appendOperation(name: "Refresh scan", detail: "Pending bridge integration", progress: nil, cancellable: true)
    }

    func cancelActiveOperation() {
        guard let index = operations.lastIndex(where: { $0.isCancellable }) else { return }
        operations[index].detail = "Cancelled"
        operations[index].progress = 1
    }

    func startBackup() {
        appendOperation(name: "Backup", detail: "Backup service pending bridge integration", progress: 0, cancellable: true)
    }

    func openPlaceholder(path: String, mode: OpenMode) {
        activeDatabasePath = path
        openMode = mode
        let recent = RecentDatabase(
            id: UUID(),
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            lastOpenedAt: .now,
            openMode: mode,
            selectedColumnFamily: selectedColumnFamily,
            comparatorProfileID: comparatorProfile.id,
            lastKnownColumnFamilies: columnFamilies
        )
        recentDatabases.removeAll { $0.path == path }
        recentDatabases.insert(recent, at: 0)
        openDatabaseSheetPresented = false
        appendOperation(name: "Open database", detail: "UI shell accepted path; RocksDB bridge lands in Phase 2", progress: 1, cancellable: false)
    }

    private func appendOperation(name: String, detail: String, progress: Double?, cancellable: Bool) {
        operations.insert(
            OperationRecord(id: UUID(), name: name, detail: detail, progress: progress, startedAt: .now, isCancellable: cancellable),
            at: 0
        )
    }
}

extension ComparatorProfile {
    static let builtIns: [ComparatorProfile] = [
        ComparatorProfile(id: "builtin.bytewise", name: "Bytewise", kind: .bytewise, bundlePath: nil, comparatorIdentifier: "rocksdb.BytewiseComparator", sampleKeys: []),
        ComparatorProfile(id: "builtin.reverse-bytewise", name: "Reverse bytewise", kind: .reverseBytewise, bundlePath: nil, comparatorIdentifier: "rocksdb.ReverseBytewiseComparator", sampleKeys: []),
        ComparatorProfile(id: "builtin.int64-signed", name: "Fixed-width signed integer", kind: .fixedWidthSignedInteger, bundlePath: nil, comparatorIdentifier: "rocksdb.viewer.Int64SignedComparator", sampleKeys: []),
        ComparatorProfile(id: "builtin.uint64", name: "Fixed-width unsigned integer", kind: .fixedWidthUnsignedInteger, bundlePath: nil, comparatorIdentifier: "rocksdb.viewer.UInt64Comparator", sampleKeys: []),
        ComparatorProfile(id: "builtin.utf8", name: "UTF-8 lexical", kind: .utf8Lexical, bundlePath: nil, comparatorIdentifier: "rocksdb.viewer.UTF8LexicalComparator", sampleKeys: [])
    ]
}

extension KeyValueRow {
    static let sampleRows: [KeyValueRow] = (0..<48).map { index in
        let key = "sample:key:\(String(format: "%04d", index))"
        let value = #"{"kind":"preview","index":\#(index),"status":"bridge pending"}"#
        return KeyValueRow(
            id: StableRowID(columnFamily: "default", sequenceIndex: UInt64(index), keyDigest: UInt64(index.hashValue)),
            keyPreview: BytePreview(bytes: Data(key.utf8), totalSize: key.utf8.count),
            valuePreview: BytePreview(bytes: Data(value.utf8), totalSize: value.utf8.count, preferredDisplay: .json),
            keySize: key.utf8.count,
            valueSize: value.utf8.count,
            sequenceIndex: UInt64(index),
            source: .live
        )
    }
}
