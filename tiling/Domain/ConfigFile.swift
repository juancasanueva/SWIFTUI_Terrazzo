import Foundation

enum ConfigDirectory {
    /// `$XDG_CONFIG_HOME/tiling`, or `~/.config/tiling`.
    static func url(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("tiling")
        }
        return home.appendingPathComponent(".config/tiling")
    }
}

enum ConfigFileError: Error, Equatable {
    case malformed
}

/// One hand-editable JSON file. Keys left out of the file take their default value.
struct ConfigFile<Value: Codable> {
    let url: URL
    let defaults: Value

    func load() throws -> Value {
        guard let data = try? Data(contentsOf: url) else { return defaults }
        let defaultObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
        let fileObject = try JSONSerialization.jsonObject(with: data)
        let merged = Self.merge(defaultObject, fileObject)
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    /// Refuses to replace a file the user left malformed, so their edit is never lost.
    func save(_ value: Value) throws {
        if FileManager.default.fileExists(atPath: url.path), (try? load()) == nil {
            throw ConfigFileError.malformed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func merge(_ base: Any, _ overlay: Any) -> Any {
        guard let baseObject = base as? [String: Any], let overlayObject = overlay as? [String: Any] else {
            return overlay
        }
        return baseObject.merging(overlayObject) { merge($0, $1) }
    }
}
