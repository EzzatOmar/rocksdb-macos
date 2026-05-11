import Foundation

struct ComparatorValidationResult: Equatable {
    var isValid: Bool
    var message: String
}

struct ComparatorRegistry {
    var builtIns: [ComparatorProfile] { ComparatorProfile.builtIns }

    func validate(_ profile: ComparatorProfile) -> ComparatorValidationResult {
        switch profile.kind {
        case .bytewise, .reverseBytewise, .fixedWidthSignedInteger, .fixedWidthUnsignedInteger, .utf8Lexical:
            return ComparatorValidationResult(isValid: true, message: "\(profile.name) comparator is available.")
        case .customBundle:
            guard let bundlePath = profile.bundlePath, FileManager.default.fileExists(atPath: bundlePath) else {
                return ComparatorValidationResult(isValid: false, message: "Custom comparator bundle path does not exist.")
            }
            guard !profile.comparatorIdentifier.isEmpty else {
                return ComparatorValidationResult(isValid: false, message: "Comparator identifier is required.")
            }
            return ComparatorValidationResult(isValid: false, message: "Custom comparator loading is scaffolded; C++ adapter integration is not enabled yet.")
        }
    }

    func orderedSamples(for profile: ComparatorProfile, samples: [Data]) -> [Data] {
        switch profile.kind {
        case .reverseBytewise:
            return samples.sorted { $0.lexicographicallyPrecedes($1) }.reversed()
        case .fixedWidthSignedInteger:
            return samples.sorted { int64Value($0, signed: true) < int64Value($1, signed: true) }
        case .fixedWidthUnsignedInteger:
            return samples.sorted { int64Value($0, signed: false) < int64Value($1, signed: false) }
        case .utf8Lexical:
            return samples.sorted { String(data: $0, encoding: .utf8) ?? "" < String(data: $1, encoding: .utf8) ?? "" }
        case .bytewise, .customBundle:
            return samples.sorted { $0.lexicographicallyPrecedes($1) }
        }
    }

    private func int64Value(_ data: Data, signed: Bool) -> Int64 {
        let bytes = Array(data.prefix(8))
        let padded = bytes + Array(repeating: UInt8(0), count: max(0, 8 - bytes.count))
        let unsigned = padded.enumerated().reduce(UInt64(0)) { result, item in
            result | (UInt64(item.element) << UInt64(item.offset * 8))
        }
        return signed ? Int64(bitPattern: unsigned) : Int64(clamping: UInt64(unsigned))
    }
}
