import Foundation

/// Codable JSON value used to persist `SurfaceMetadataStore` contents across
/// c11mux restarts. Numbers are stored as `Double`; consumers needing integer
/// fidelity must convert explicitly. `Bool` is distinct from number on the
/// wire and on the Swift side, matching JSON semantics.
enum PersistedJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([PersistedJSONValue])
    case object([String: PersistedJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Decode Bool before Double: JSON `true`/`false` are bools, numbers
        // are numbers, and JSONDecoder respects the distinction. Keeping this
        // order ensures a persisted `.bool(true)` never surfaces as `.number`.
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .number(double)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let array = try? container.decode([PersistedJSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: PersistedJSONValue].self) {
            self = .object(object)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "PersistedJSONValue: unsupported JSON shape"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        case .bool(let b):   try container.encode(b)
        case .array(let a):  try container.encode(a)
        case .object(let o): try container.encode(o)
        case .null:          try container.encodeNil()
        }
    }
}

/// Codable sidecar preserving the `(source, ts)` record alongside a persisted
/// metadata value so the precedence chain survives a restart.
struct PersistedMetadataSource: Codable, Sendable, Equatable {
    /// `MetadataSource` raw value: `"explicit" | "declare" | "osc" | "heuristic"`.
    /// Unknown strings decode cleanly (no Codable error); the bridge downgrades
    /// them to `.heuristic` with a debug log on the way back into the store.
    var source: String
    /// Seconds since 1970, matching `SurfaceMetadataStore.SourceRecord.ts`.
    var ts: TimeInterval
}
