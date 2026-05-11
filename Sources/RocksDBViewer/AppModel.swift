import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let retainedRowLimit = 2_000
    private let session = DatabaseSession()
    private var activeScanTask: Task<Void, Never>?

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
        guard activeDatabasePath != nil else {
            appendOperation(name: "Refresh scan", detail: "Open a database before scanning", progress: 1, cancellable: false)
            return
        }

        activeScanTask?.cancel()
        rows.removeAll(keepingCapacity: true)
        let operationID = appendOperation(name: "Scan", detail: "Running \(scanMode.rawValue.lowercased())", progress: nil, cancellable: true)
        let request: ScanRequest
        do {
            request = try makeScanRequest()
        } catch {
            updateOperation(operationID, detail: error.localizedDescription, progress: 1)
            return
        }

        activeScanTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await batch in session.scan(request) {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.appendRows(batch)
                    }
                }
                await MainActor.run {
                    self.updateOperation(operationID, detail: "Completed \(self.rows.count.formatted()) retained rows", progress: 1)
                }
            } catch {
                await MainActor.run {
                    self.updateOperation(operationID, detail: error.localizedDescription, progress: 1)
                }
            }
        }
    }

    func cancelActiveOperation() {
        activeScanTask?.cancel()
        guard let index = operations.lastIndex(where: { $0.isCancellable }) else { return }
        operations[index].detail = "Cancelled"
        operations[index].progress = 1
    }

    func startBackup() {
        appendOperation(name: "Backup", detail: "Backup service pending bridge integration", progress: 0, cancellable: true)
    }

    func openPlaceholder(path: String, mode: OpenMode) {
        let operationID = appendOperation(name: "Open database", detail: "Opening \(URL(fileURLWithPath: path).lastPathComponent)", progress: nil, cancellable: false)
        Task { [weak self] in
            guard let self else { return }
            do {
                let metadata = try await session.open(DatabaseOpenRequest(path: path, mode: mode, createIfMissing: false, selectedColumnFamily: selectedColumnFamily))
                await MainActor.run {
                    self.activeDatabasePath = path
                    self.openMode = metadata.openMode
                    self.columnFamilies = metadata.columnFamilies
                    self.selectedColumnFamily = metadata.selectedColumnFamily
                    self.rows.removeAll(keepingCapacity: true)
                    let recent = RecentDatabase(
                        id: UUID(),
                        path: path,
                        displayName: URL(fileURLWithPath: path).lastPathComponent,
                        lastOpenedAt: .now,
                        openMode: mode,
                        selectedColumnFamily: metadata.selectedColumnFamily,
                        comparatorProfileID: self.comparatorProfile.id,
                        lastKnownColumnFamilies: metadata.columnFamilies
                    )
                    self.recentDatabases.removeAll { $0.path == path }
                    self.recentDatabases.insert(recent, at: 0)
                    self.openDatabaseSheetPresented = false
                    self.updateOperation(operationID, detail: "Opened \(metadata.columnFamilies.count) column families", progress: 1)
                }
                await MainActor.run {
                    self.refreshCurrentScan()
                }
            } catch {
                await MainActor.run {
                    self.updateOperation(operationID, detail: error.localizedDescription, progress: 1)
                }
            }
        }
    }

    @discardableResult
    private func appendOperation(name: String, detail: String, progress: Double?, cancellable: Bool) -> UUID {
        let id = UUID()
        operations.insert(
            OperationRecord(id: id, name: name, detail: detail, progress: progress, startedAt: .now, isCancellable: cancellable),
            at: 0
        )
        return id
    }

    private func updateOperation(_ id: UUID, detail: String, progress: Double?) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].detail = detail
        operations[index].progress = progress
    }

    private func appendRows(_ newRows: [KeyValueRow]) {
        rows.append(contentsOf: newRows)
        if rows.count > Self.retainedRowLimit {
            rows.removeFirst(rows.count - Self.retainedRowLimit)
        }
    }

    private func makeScanRequest() throws -> ScanRequest {
        let exactData = try decode(exactKey)
        let lowerData = try decode(lowerBound)
        let upperData = try decode(upperBound)
        let prefixData = try decode(prefix)
        return ScanRequest(
            columnFamily: selectedColumnFamily,
            mode: scanMode,
            lowerBound: scanMode == .exact ? exactData : lowerData,
            upperBound: upperData,
            prefix: scanMode == .prefix ? prefixData : nil,
            limit: scanLimit,
            direction: scanDirection,
            snapshotID: nil,
            previewByteLimit: BytePreview.defaultLimit
        )
    }

    private func decode(_ text: String) throws -> Data? {
        guard !text.isEmpty else { return nil }
        switch keyEncoding {
        case .utf8, .json:
            return Data(text.utf8)
        case .raw:
            return Data(text.utf8)
        case .hex:
            return try HexCodec.decode(text)
        }
    }
}

enum HexCodec {
    static func decode(_ text: String) throws -> Data {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.count.isMultiple(of: 2) else {
            throw RocksBridgeError(code: 1, message: "Hex input must contain an even number of digits.")
        }
        var data = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            let pair = compact[index..<next]
            guard let byte = UInt8(pair, radix: 16) else {
                throw RocksBridgeError(code: 1, message: "Hex input contains invalid digits.")
            }
            data.append(byte)
            index = next
        }
        return data
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
