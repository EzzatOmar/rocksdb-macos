import Foundation

enum OpenMode: String, Codable, CaseIterable, Identifiable {
    case readOnly
    case readWrite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .readOnly: "Read-only"
        case .readWrite: "Read-write"
        }
    }
}

struct RecentDatabase: Codable, Identifiable, Hashable {
    var id: UUID
    var path: String
    var displayName: String
    var lastOpenedAt: Date
    var openMode: OpenMode
    var selectedColumnFamily: String?
    var comparatorProfileID: String?
    var backupDirectory: String?
    var lastKnownColumnFamilies: [String]
}

enum ComparatorKind: String, Codable, CaseIterable, Identifiable {
    case bytewise
    case reverseBytewise
    case fixedWidthSignedInteger
    case fixedWidthUnsignedInteger
    case utf8Lexical
    case customBundle

    var id: String { rawValue }
}

struct ComparatorProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: ComparatorKind
    var bundlePath: String?
    var comparatorIdentifier: String
    var sampleKeys: [Data]
}

struct StableRowID: Hashable, Codable {
    var columnFamily: String
    var sequenceIndex: UInt64
    var keyDigest: UInt64
}

enum ValueDisplayMode: String, Codable, CaseIterable, Identifiable {
    case utf8 = "UTF-8"
    case hex = "Hex"
    case json = "JSON"
    case raw = "Raw"

    var id: String { rawValue }
}

struct BytePreview: Hashable {
    static let defaultLimit = 4 * 1024

    var bytes: Data
    var totalSize: Int
    var isTruncated: Bool
    var preferredDisplay: ValueDisplayMode

    init(bytes: Data, totalSize: Int? = nil, preferredDisplay: ValueDisplayMode = .utf8, limit: Int = Self.defaultLimit) {
        let actualSize = totalSize ?? bytes.count
        self.bytes = bytes.prefix(limit)
        self.totalSize = actualSize
        self.isTruncated = actualSize > self.bytes.count
        self.preferredDisplay = preferredDisplay
    }

    var text: String {
        switch preferredDisplay {
        case .utf8, .json:
            guard let string = String(data: bytes, encoding: .utf8), string.isMostlyPrintable else {
                return hexString
            }
            return string
        case .hex:
            return hexString
        case .raw:
            return bytes.map { byte in
                byte >= 32 && byte <= 126 ? String(UnicodeScalar(byte)) : "."
            }.joined()
        }
    }

    var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

private extension String {
    var isMostlyPrintable: Bool {
        guard !isEmpty else { return true }
        let printable = unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\r" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }.count
        return Double(printable) / Double(unicodeScalars.count) >= 0.85
    }
}

struct KeyValueRow: Identifiable, Hashable {
    var id: StableRowID
    var keyPreview: BytePreview
    var valuePreview: BytePreview
    var keySize: Int
    var valueSize: Int
    var sequenceIndex: UInt64
    var source: RowSource
}

enum RowSource: String, Hashable {
    case live
    case snapshot
}

enum ScanMode: String, CaseIterable, Identifiable {
    case exact = "Exact key"
    case prefix = "Prefix"
    case range = "Range"

    var id: String { rawValue }
}

enum ScanDirection: String, CaseIterable, Identifiable {
    case forward = "Forward"
    case reverse = "Reverse"

    var id: String { rawValue }
}

struct ScanRequest: Hashable {
    var columnFamily: String
    var mode: ScanMode
    var lowerBound: Data?
    var upperBound: Data?
    var prefix: Data?
    var limit: Int
    var direction: ScanDirection
    var snapshotID: UUID?
    var previewByteLimit: Int
}

struct SnapshotRecord: Identifiable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var activeQueryCount: Int
}

struct BackupRecord: Identifiable, Hashable {
    var id: Int
    var location: String
    var createdAt: Date
    var sizeDescription: String
    var status: String
}

struct OperationRecord: Identifiable, Hashable {
    var id: UUID
    var name: String
    var detail: String
    var progress: Double?
    var startedAt: Date
    var isCancellable: Bool
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case browser = "Browser"
    case search = "Search"
    case snapshotsBackups = "Snapshots & Backups"
    case operations = "Operations"
    case settings = "Settings"

    var id: String { rawValue }
}

enum EditSheetMode: Identifiable {
    case add
    case edit

    var id: String {
        switch self {
        case .add: "add"
        case .edit: "edit"
        }
    }
}
