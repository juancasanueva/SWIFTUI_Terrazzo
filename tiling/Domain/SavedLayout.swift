/// `~/.config/tiling/layout.json`: where windows were, so a restart of this app puts them back.
/// Holds window numbers and app identifiers only, never titles. Window numbers last as long as the
/// window, so this does not survive quitting those apps or restarting the Mac.
struct SavedLayout: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var key: WorkspaceKey
        var tiles: [[WindowID]]
        var overflow: [WindowID]
        var activeTile: Int
    }

    var entries: [Entry] = []
    /// Window number, as text, to the app that owned it.
    var apps: [String: String] = [:]
    var floats: [WindowID] = []
    var visible: [String: Int] = [:]
    var homes: [String: String] = [:]
}

extension TilingState {
    func savedLayout(map: VirtualWorkspaces) -> SavedLayout {
        var saved = SavedLayout()
        for (key, workspace) in workspaces where !workspace.tiles.isEmpty || !workspace.overflow.isEmpty {
            saved.entries.append(
                SavedLayout.Entry(
                    key: key, tiles: workspace.tiles.map(\.windows), overflow: workspace.overflow,
                    activeTile: workspace.activeTile))
        }
        // Dictionary order varies, and an unchanged layout must compare equal.
        saved.entries.sort { ($0.key.display, $0.key.space, $0.key.virtual) < ($1.key.display, $1.key.space, $1.key.virtual) }
        for (id, app) in apps { saved.apps[String(id)] = app }
        saved.floats = userFloats.sorted()
        saved.visible = map.savedVisible
        saved.homes = map.savedHomes
        return saved
    }

    /// Puts saved windows back. `owners` lists the windows that exist now and their apps; a window
    /// number that is gone, or now belongs to another app, is dropped.
    mutating func restore(_ saved: SavedLayout, owners: [WindowID: String]) {
        func isSame(_ id: WindowID) -> Bool {
            guard let owner = owners[id] else { return false }
            return saved.apps[String(id)] == owner
        }
        for entry in saved.entries {
            let tiles = entry.tiles.map { $0.filter(isSame) }.filter { !$0.isEmpty }.map(Tile.init(windows:))
            let overflow = entry.overflow.filter(isSame)
            guard !tiles.isEmpty || !overflow.isEmpty else { continue }
            var workspace = workspaces[entry.key] ?? Workspace()
            workspace.tiles = tiles
            workspace.overflow = overflow
            workspace.activeTile = min(max(entry.activeTile, 0), max(tiles.count - 1, 0))
            workspaces[entry.key] = workspace
            for id in tiles.flatMap(\.windows) + overflow { apps[id] = owners[id] }
        }
        for id in saved.floats where isSame(id) {
            userFloats.insert(id)
            apps[id] = owners[id]
        }
    }
}
