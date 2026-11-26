import Foundation

/// The one JSON form for index data: sorted keys, ISO 8601 dates, pretty printed.
/// Sorted keys make the output the same on every run, so files can be compared byte for byte.
public enum GitHubPRExplorerJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
