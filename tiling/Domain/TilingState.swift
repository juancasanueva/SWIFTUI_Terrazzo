import CoreGraphics

typealias WindowID = UInt32

struct WorkspaceKey: Hashable, Codable, Sendable {
    var display: String
    var space: UInt64
}

enum FullScreenBehavior: String, Codable, CaseIterable, Sendable {
    case stack, floatInMiddle
}

enum MoveIntoFullBehavior: String, Codable, CaseIterable, Sendable {
    case swap, stackOnTop
}

enum Direction: Sendable {
    case left, right, up, down
}

struct TilingPolicy: Equatable, Sendable {
    var kind: LayoutKind = .grid
    var kindIsChosen = false
    var count = 3
    var main: MainSize = .half
    var gap: CGFloat = 8
    var whenFull: FullScreenBehavior = .stack
    var movingIntoFull: MoveIntoFullBehavior = .swap

    init(
        gap: CGFloat = 8, whenFull: FullScreenBehavior = .stack, movingIntoFull: MoveIntoFullBehavior = .swap
    ) {
        self.gap = gap
        self.whenFull = whenFull
        self.movingIntoFull = movingIntoFull
    }
}

struct ScreenGeometry: Equatable, Sendable {
    var key: WorkspaceKey
    var area: CGRect
}

struct TilingContext {
    var screens: [ScreenGeometry]
    var policy: TilingPolicy
    var minimumSize: (String) -> CGSize
}

struct ObservedWindow: Equatable, Sendable {
    var id: WindowID
    var app: String
    var key: WorkspaceKey
    var frame: CGRect
}

/// What the window system currently shows on the active Spaces.
struct Snapshot: Equatable, Sendable {
    var windows: [ObservedWindow]
    var minimized: [WindowID]
    var focused: WindowID?
}

struct Placement: Equatable, Sendable {
    var id: WindowID
    var frame: CGRect
}

struct Plan: Equatable, Sendable {
    var placements: [Placement] = []
    /// Windows on top of their tile, in slot order.
    var showing: [WindowID] = []
    /// Windows to move once to the middle of their screen.
    var centered: [WindowID] = []
}

enum Notice: Equatable, Sendable {
    case stacked, spaceFull, maximumSize, minimumSize
    case doesNotFit(app: String)
}

struct Tile: Equatable, Sendable {
    /// The showing window first, then the rest by most recent use.
    var windows: [WindowID]
}

struct Workspace: Equatable, Sendable {
    var tiles: [Tile] = []
    var overflow: [WindowID] = []
    var kind: LayoutKind?
    var count: Int?
    var overrides = SizeOverrides()
    var zoomed: WindowID?
    var cleanSet: [WindowID]?
    var activeTile = 0
}

struct TilingState: Equatable {
    private struct Origin: Equatable {
        var key: WorkspaceKey
        var tile: Int
    }

    var workspaces: [WorkspaceKey: Workspace] = [:]
    var apps: [WindowID: String] = [:]
    var userFloats: Set<WindowID> = []
    var focused: WindowID?
    private var minimizedOrigins: [WindowID: Origin] = [:]
    private var pendingCenter: [WindowID] = []
    private var lastFrames: [WindowID: CGRect] = [:]

    // MARK: Reconciling

    @discardableResult
    mutating func reconcile(_ snapshot: Snapshot, context: TilingContext) -> [Notice] {
        var notices: [Notice] = []
        let activeKeys = Set(context.screens.map(\.key))
        let observed = Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let minimized = Set(snapshot.minimized)
        var added = snapshot.windows.filter { !isTracked($0.id) && !userFloats.contains($0.id) }

        for key in activeKeys {
            for id in allWindows(on: key) where observed[id] == nil {
                if let index = added.firstIndex(where: { isTabReplacement($0, of: id) }) {
                    replace(id, with: added.remove(at: index))
                } else {
                    remove(id, minimized: minimized.contains(id), context: context)
                }
            }
        }

        // A window that changed Space, or lost its display, belongs to the workspace it now sits on.
        let activeDisplays = Set(activeKeys.map(\.display))
        for window in snapshot.windows {
            guard let stored = key(of: window.id), stored != window.key else { continue }
            if stored.display == window.key.display || !activeDisplays.contains(stored.display) {
                remove(window.id, minimized: false, context: context)
                added.append(window)
            }
        }

        userFloats = userFloats.filter { observed[$0] != nil || minimized.contains($0) }
        pendingCenter = pendingCenter.filter { observed[$0] != nil }

        for window in added where activeKeys.contains(window.key) {
            apps[window.id] = window.app
            notices += place(window, context: context)
        }

        if let id = snapshot.focused { noteFocus(id, context: context) }
        focused = snapshot.focused
        return notices
    }

    private func isTracked(_ id: WindowID) -> Bool { key(of: id) != nil }

    func key(of id: WindowID) -> WorkspaceKey? {
        workspaces.first { _, workspace in
            workspace.tiles.contains { $0.windows.contains(id) } || workspace.overflow.contains(id)
                || (workspace.cleanSet?.contains(id) ?? false)
        }?.key
    }

    private func allWindows(on key: WorkspaceKey) -> [WindowID] {
        guard let workspace = workspaces[key] else { return [] }
        var ids = workspace.tiles.flatMap(\.windows) + workspace.overflow
        for id in workspace.cleanSet ?? [] where !ids.contains(id) { ids.append(id) }
        return ids
    }

    private func isTabReplacement(_ window: ObservedWindow, of id: WindowID) -> Bool {
        guard apps[id] == window.app, let last = lastFrames[id] else { return false }
        return abs(last.minX - window.frame.minX) < 2 && abs(last.minY - window.frame.minY) < 2
            && abs(last.width - window.frame.width) < 2 && abs(last.height - window.frame.height) < 2
    }

    private mutating func replace(_ old: WindowID, with window: ObservedWindow) {
        guard let key = key(of: old), var workspace = workspaces[key] else { return }
        for index in workspace.tiles.indices {
            workspace.tiles[index].windows = workspace.tiles[index].windows.map { $0 == old ? window.id : $0 }
        }
        workspace.overflow = workspace.overflow.map { $0 == old ? window.id : $0 }
        workspace.cleanSet = workspace.cleanSet?.map { $0 == old ? window.id : $0 }
        if workspace.zoomed == old { workspace.zoomed = window.id }
        workspaces[key] = workspace
        apps[window.id] = window.app
        lastFrames[window.id] = lastFrames.removeValue(forKey: old)
        apps[old] = nil
    }

    private mutating func remove(_ id: WindowID, minimized: Bool, context: TilingContext) {
        guard let key = key(of: id), var workspace = workspaces[key] else { return }
        if minimized, let tile = workspace.tiles.firstIndex(where: { $0.windows.contains(id) }) {
            minimizedOrigins[id] = Origin(key: key, tile: tile)
        }
        let tilesBefore = workspace.tiles.count
        for index in workspace.tiles.indices { workspace.tiles[index].windows.removeAll { $0 == id } }
        workspace.tiles.removeAll { $0.windows.isEmpty }
        workspace.overflow.removeAll { $0 == id }
        workspace.cleanSet?.removeAll { $0 == id }
        if workspace.zoomed == id { workspace.zoomed = nil }
        workspaces[key] = workspace
        lastFrames[id] = nil
        if !minimized { apps[id] = nil }
        normalize(key, pull: workspace.tiles.count < tilesBefore, context: context)
    }

    private mutating func place(_ window: ObservedWindow, context: TilingContext) -> [Notice] {
        let key = window.key
        var workspace = workspaces[key] ?? Workspace()
        defer { normalize(key, pull: false, context: context) }

        if workspace.cleanSet != nil { workspace.cleanSet?.append(window.id) }

        if let origin = minimizedOrigins.removeValue(forKey: window.id), origin.key == key,
            origin.tile < workspace.tiles.count {
            workspace.tiles[origin.tile].windows.insert(window.id, at: 0)
            workspaces[key] = workspace
            return []
        }

        workspaces[key] = workspace
        if canAddTile(on: key, app: window.app, context: context) {
            workspaces[key]?.tiles.append(Tile(windows: [window.id]))
            return []
        }
        switch context.policy.whenFull {
        case .stack:
            if workspace.tiles.isEmpty {
                workspaces[key]?.tiles.append(Tile(windows: [window.id]))
                return []
            }
            let target = min(workspace.activeTile, workspace.tiles.count - 1)
            workspaces[key]?.tiles[target].windows.insert(window.id, at: 0)
            return [.stacked]
        case .floatInMiddle:
            workspaces[key]?.overflow.append(window.id)
            pendingCenter.append(window.id)
            return [.spaceFull]
        }
    }

    private mutating func noteFocus(_ id: WindowID, context: TilingContext) {
        guard let key = key(of: id), var workspace = workspaces[key] else { return }
        if let tile = workspace.tiles.firstIndex(where: { $0.windows.contains(id) }) {
            workspace.tiles[tile].windows.removeAll { $0 == id }
            workspace.tiles[tile].windows.insert(id, at: 0)
            workspace.activeTile = tile
        }
        if let zoomed = workspace.zoomed, zoomed != id { workspace.zoomed = nil }
        if workspace.cleanSet != nil, workspace.cleanSet?.contains(id) == false {
            workspace.cleanSet?.append(id)
        }
        workspaces[key] = workspace
    }

    // MARK: Capacity

    func area(of key: WorkspaceKey, context: TilingContext) -> CGRect? {
        context.screens.first { $0.key == key }?.area
    }

    func resolvedKind(_ workspace: Workspace, area: CGRect, policy: TilingPolicy) -> LayoutKind {
        if let kind = workspace.kind { return kind }
        if !policy.kindIsChosen, Orientation(area: area) == .vertical { return .rows }
        return policy.kind
    }

    func limit(on key: WorkspaceKey, context: TilingContext) -> Int {
        guard let area = area(of: key, context: context) else { return 1 }
        let workspace = workspaces[key] ?? Workspace()
        let kind = resolvedKind(workspace, area: area, policy: context.policy)
        let cap = LayoutEngine.maxCount(kind: kind, area: area, gap: context.policy.gap)
        return max(1, min(workspace.count ?? context.policy.count, cap))
    }

    private func slotMinimums(_ tiles: [Tile], context: TilingContext) -> [Int: CGSize] {
        var minimums: [Int: CGSize] = [:]
        for (slot, tile) in tiles.enumerated() {
            var size = LayoutEngine.resizeFloor
            for id in tile.windows {
                guard let app = apps[id] else { continue }
                let minimum = context.minimumSize(app)
                size = CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
            }
            minimums[slot] = size
        }
        return minimums
    }

    private func fits(_ tiles: [Tile], on key: WorkspaceKey, context: TilingContext) -> Bool {
        guard let area = area(of: key, context: context) else { return false }
        let workspace = workspaces[key] ?? Workspace()
        let shape = LayoutEngine.shape(
            kind: resolvedKind(workspace, area: area, policy: context.policy), count: tiles.count, area: area,
            main: context.policy.main, overrides: workspace.overrides)
        return LayoutEngine.solve(
            shape: shape, area: area, gap: context.policy.gap, minimums: slotMinimums(tiles, context: context)
        ).overflowingSlots.isEmpty
    }

    private func canAddTile(on key: WorkspaceKey, app: String, context: TilingContext) -> Bool {
        let tiles = workspaces[key]?.tiles ?? []
        guard tiles.count < limit(on: key, context: context) else { return false }
        return tiles.isEmpty || fitsAdding(app, to: tiles, on: key, context: context)
    }

    private func fitsAdding(_ app: String, to tiles: [Tile], on key: WorkspaceKey, context: TilingContext) -> Bool {
        var probe = self
        probe.apps[WindowID.max] = app
        return probe.fits(tiles + [Tile(windows: [WindowID.max])], on: key, context: context)
    }

    private func isFull(_ key: WorkspaceKey, context: TilingContext) -> Bool {
        (workspaces[key]?.tiles.count ?? 0) >= limit(on: key, context: context)
    }

    /// Brings the tiles in line with the screen's limit and, when asked, fills freed room from waiting windows.
    private mutating func normalize(_ key: WorkspaceKey, pull: Bool, context: TilingContext) {
        guard var workspace = workspaces[key] else { return }
        let limit = limit(on: key, context: context)

        while workspace.tiles.count > limit
            || (workspace.tiles.count > 1 && !fits(workspace.tiles, on: key, context: context)) {
            let last = workspace.tiles.removeLast()
            if context.policy.whenFull == .floatInMiddle {
                workspace.overflow.append(contentsOf: last.windows)
                pendingCenter.append(contentsOf: last.windows)
            } else {
                workspace.tiles[workspace.tiles.count - 1].windows.append(contentsOf: last.windows)
            }
        }

        // Windows floated only because the screen was full rejoin as soon as there is room.
        while !workspace.overflow.isEmpty, workspace.tiles.count < limit,
            let app = apps[workspace.overflow[0]],
            workspace.tiles.isEmpty || fitsAdding(app, to: workspace.tiles, on: key, context: context) {
            let id = workspace.overflow.removeFirst()
            workspace.tiles.append(Tile(windows: [id]))
            pendingCenter.removeAll { $0 == id }
        }

        if pull {
            while workspace.tiles.count < limit,
                let source = workspace.tiles.lastIndex(where: { $0.windows.count > 1 }),
                let app = apps[workspace.tiles[source].windows[1]],
                fitsAdding(app, to: workspace.tiles, on: key, context: context) {
                let id = workspace.tiles[source].windows.remove(at: 1)
                workspace.tiles.append(Tile(windows: [id]))
            }
        }

        workspace.activeTile = min(workspace.activeTile, max(workspace.tiles.count - 1, 0))
        workspaces[key] = workspace
    }

    // MARK: Planning

    func slotFrames(on key: WorkspaceKey, context: TilingContext) -> [CGRect] {
        guard let area = area(of: key, context: context), let workspace = workspaces[key],
            !workspace.tiles.isEmpty
        else { return [] }
        let shape = LayoutEngine.shape(
            kind: resolvedKind(workspace, area: area, policy: context.policy), count: workspace.tiles.count,
            area: area, main: context.policy.main, overrides: workspace.overrides)
        return LayoutEngine.solve(
            shape: shape, area: area, gap: context.policy.gap,
            minimums: slotMinimums(workspace.tiles, context: context)
        ).frames
    }

    mutating func plan(context: TilingContext) -> Plan {
        var plan = Plan()
        for screen in context.screens {
            guard let workspace = workspaces[screen.key] else { continue }
            let gap = context.policy.gap
            let full = screen.area.insetBy(dx: gap, dy: gap)

            if let clean = workspace.cleanSet {
                plan.showing += clean
                let shape = LayoutEngine.shape(
                    kind: .grid, count: clean.count, area: screen.area, main: .half, overrides: SizeOverrides())
                let frames = LayoutEngine.solve(shape: shape, area: screen.area, gap: gap, minimums: [:]).frames
                for (id, frame) in zip(clean, clean.isEmpty ? [] : frames) {
                    plan.placements.append(Placement(id: id, frame: frame))
                }
                continue
            }

            let frames = slotFrames(on: screen.key, context: context)
            for (slot, tile) in workspace.tiles.enumerated() {
                plan.showing.append(tile.windows[0])
                for id in tile.windows {
                    plan.placements.append(
                        Placement(id: id, frame: id == workspace.zoomed ? full : frames[slot]))
                }
            }
        }
        for placement in plan.placements { lastFrames[placement.id] = placement.frame }
        plan.centered = pendingCenter
        pendingCenter = []
        return plan
    }

    // MARK: Commands

    mutating func swap(_ a: WindowID, with b: WindowID, context: TilingContext) {
        guard a != b, let aKey = key(of: a), let bKey = key(of: b),
            let aTile = workspaces[aKey]?.tiles.firstIndex(where: { $0.windows.contains(a) }),
            let bTile = workspaces[bKey]?.tiles.firstIndex(where: { $0.windows.contains(b) })
        else { return }
        workspaces[aKey]?.tiles[aTile].windows.removeAll { $0 == a }
        workspaces[bKey]?.tiles[bTile].windows.removeAll { $0 == b }
        workspaces[aKey]?.tiles[aTile].windows.insert(b, at: 0)
        workspaces[bKey]?.tiles[bTile].windows.insert(a, at: 0)
    }

    mutating func makePrimary(_ id: WindowID, context: TilingContext) {
        guard let key = key(of: id), let first = workspaces[key]?.tiles.first?.windows.first else { return }
        swap(id, with: first, context: context)
    }

    /// Swaps with the neighbor, or moves to the next screen when there is none.
    @discardableResult
    mutating func moveOrSwap(_ id: WindowID, direction: Direction, context: TilingContext) -> [Notice] {
        guard let key = key(of: id), let workspace = workspaces[key],
            let tile = workspace.tiles.firstIndex(where: { $0.windows.contains(id) })
        else { return [] }
        let frames = slotFrames(on: key, context: context)
        if let neighbor = Self.neighbor(of: frames[tile], in: frames, direction: direction) {
            swap(id, with: workspace.tiles[neighbor].windows[0], context: context)
            return []
        }
        guard let target = nextScreen(from: key, direction: direction, context: context) else { return [] }
        return move(id, from: key, tile: tile, to: target, context: context)
    }

    /// Sends a window to a chosen screen, under the same rules as moving past a screen edge.
    @discardableResult
    mutating func moveToScreen(_ id: WindowID, target: WorkspaceKey, context: TilingContext) -> [Notice] {
        guard let key = key(of: id), key != target,
            let tile = workspaces[key]?.tiles.firstIndex(where: { $0.windows.contains(id) })
        else { return [] }
        return move(id, from: key, tile: tile, to: target, context: context)
    }

    private mutating func move(
        _ id: WindowID, from key: WorkspaceKey, tile: Int, to target: WorkspaceKey, context: TilingContext
    ) -> [Notice] {
        guard let app = apps[id] else { return [] }
        if isFull(target, context: context) {
            let frames = slotFrames(on: target, context: context)
            let source = slotFrames(on: key, context: context)[tile]
            let center = CGPoint(x: source.midX, y: source.midY)
            guard let nearest = frames.indices.min(by: {
                Self.distance(frames[$0], center) < Self.distance(frames[$1], center)
            }) else { return [] }
            if context.policy.movingIntoFull == .stackOnTop {
                moveToTile(id, tile: nearest, on: target, context: context)
            } else if let other = workspaces[target]?.tiles[nearest].windows.first {
                swap(id, with: other, context: context)
            }
            return []
        }
        if canAddTile(on: target, app: app, context: context) {
            remove(id, minimized: false, keepingApp: true, context: context)
            workspaces[target, default: Workspace()].tiles.append(Tile(windows: [id]))
            normalize(target, pull: false, context: context)
            return []
        }
        return [.doesNotFit(app: app)]
    }

    private mutating func remove(_ id: WindowID, minimized: Bool, keepingApp: Bool, context: TilingContext) {
        let app = apps[id]
        remove(id, minimized: minimized, context: context)
        if keepingApp { apps[id] = app }
    }

    /// A plain drop onto another screen: joins as newest, or reports that it must go back.
    mutating func join(_ id: WindowID, to target: WorkspaceKey, context: TilingContext) -> Bool {
        guard let app = apps[id], canAddTile(on: target, app: app, context: context) else { return false }
        remove(id, minimized: false, keepingApp: true, context: context)
        workspaces[target, default: Workspace()].tiles.append(Tile(windows: [id]))
        return true
    }

    /// Shows the window on top of the tile, leaving the displaced window behind it.
    mutating func moveToTile(_ id: WindowID, tile: Int, on target: WorkspaceKey, context: TilingContext) {
        guard let targetTile = workspaces[target]?.tiles[safe: tile], !targetTile.windows.contains(id) else { return }
        let displaced = targetTile.windows.first
        remove(id, minimized: false, keepingApp: true, context: context)
        guard var workspace = workspaces[target] else { return }
        let index = displaced.flatMap { shown in
            workspace.tiles.firstIndex { $0.windows.contains(shown) }
        }
        guard let index else { return }
        workspace.tiles[index].windows.insert(id, at: 0)
        workspaces[target] = workspace
    }

    mutating func cycleStack(of id: WindowID, forward: Bool) -> WindowID? {
        guard let key = key(of: id), var workspace = workspaces[key],
            let index = workspace.tiles.firstIndex(where: { $0.windows.contains(id) }),
            workspace.tiles[index].windows.count > 1
        else { return nil }
        var windows = workspace.tiles[index].windows
        if forward {
            windows.append(windows.removeFirst())
        } else {
            windows.insert(windows.removeLast(), at: 0)
        }
        workspace.tiles[index].windows = windows
        workspaces[key] = workspace
        return windows[0]
    }

    mutating func show(_ id: WindowID) {
        guard let key = key(of: id), var workspace = workspaces[key],
            let index = workspace.tiles.firstIndex(where: { $0.windows.contains(id) })
        else { return }
        workspace.tiles[index].windows.removeAll { $0 == id }
        workspace.tiles[index].windows.insert(id, at: 0)
        workspaces[key] = workspace
    }

    func adjacentWindow(to id: WindowID, forward: Bool) -> WindowID? {
        guard let key = key(of: id), let workspace = workspaces[key] else { return nil }
        let showing = workspace.tiles.compactMap(\.windows.first)
        guard let index = showing.firstIndex(of: id), showing.count > 1 else { return nil }
        let next = (index + (forward ? 1 : -1) + showing.count) % showing.count
        return showing[next]
    }

    mutating func setCount(_ count: Int, on key: WorkspaceKey, context: TilingContext) -> [Notice] {
        workspaces[key, default: Workspace()].count = count
        normalize(key, pull: true, context: context)
        return []
    }

    mutating func setKind(_ kind: LayoutKind, on key: WorkspaceKey, context: TilingContext) {
        workspaces[key, default: Workspace()].kind = kind
        normalize(key, pull: true, context: context)
    }

    /// Re-applies the screen limits after a setting or a learned minimum changed.
    mutating func refreshLimits(context: TilingContext) {
        for screen in context.screens { normalize(screen.key, pull: true, context: context) }
    }

    mutating func toggleZoom(_ id: WindowID, context: TilingContext) {
        guard let key = key(of: id) else { return }
        let current = workspaces[key]?.zoomed
        workspaces[key]?.zoomed = current == id ? nil : id
    }

    mutating func toggleFloat(_ id: WindowID, context: TilingContext) {
        if userFloats.remove(id) != nil { return }
        let app = apps[id]
        remove(id, minimized: false, context: context)
        apps[id] = app
        userFloats.insert(id)
    }

    mutating func toggleClean(on key: WorkspaceKey, active: WindowID?) {
        if workspaces[key]?.cleanSet != nil {
            workspaces[key]?.cleanSet = nil
        } else {
            workspaces[key, default: Workspace()].cleanSet = active.map { [$0] } ?? []
        }
    }

    mutating func endClean() {
        for key in workspaces.keys { workspaces[key]?.cleanSet = nil }
    }

    // MARK: Sizes

    mutating func dragEdges(of id: WindowID, deltas: EdgeDeltas, context: TilingContext) -> Bool {
        withResizeTarget(id, context: context) { state, key, slot, area, kind, count, minimums in
            LayoutEngine.moveEdges(
                slot: slot, kind: kind, count: count, area: area, main: context.policy.main,
                gap: context.policy.gap, minimums: minimums, deltas: deltas,
                overrides: &state.workspaces[key, default: Workspace()].overrides)
        } ?? false
    }

    mutating func step(_ id: WindowID, grow: Bool, context: TilingContext) -> [Notice] {
        let result = withResizeTarget(id, context: context) { state, key, slot, area, kind, count, minimums in
            LayoutEngine.step(
                slot: slot, grow: grow, kind: kind, count: count, area: area, main: context.policy.main,
                gap: context.policy.gap, minimums: minimums,
                overrides: &state.workspaces[key, default: Workspace()].overrides)
        }
        guard result == .changed else { return [grow ? .maximumSize : .minimumSize] }
        return []
    }

    private mutating func withResizeTarget<Result>(
        _ id: WindowID, context: TilingContext,
        body: (inout TilingState, WorkspaceKey, Int, CGRect, LayoutKind, Int, [Int: CGSize]) -> Result
    ) -> Result? {
        guard let key = key(of: id), let workspace = workspaces[key],
            let slot = workspace.tiles.firstIndex(where: { $0.windows.contains(id) }),
            let area = area(of: key, context: context)
        else { return nil }
        let kind = resolvedKind(workspace, area: area, policy: context.policy)
        let minimums = slotMinimums(workspace.tiles, context: context)
        return body(&self, key, slot, area, kind, workspace.tiles.count, minimums)
    }

    func hasCustomSizes(on key: WorkspaceKey) -> Bool {
        !(workspaces[key]?.overrides.isEmpty ?? true)
    }

    mutating func resetSizes(on key: WorkspaceKey) {
        workspaces[key]?.overrides = SizeOverrides()
    }

    // MARK: Geometry

    static func neighbor(of frame: CGRect, in frames: [CGRect], direction: Direction) -> Int? {
        let tolerance: CGFloat = 1
        let candidates = frames.indices.filter { index in
            let other = frames[index]
            guard other != frame else { return false }
            switch direction {
            case .left: return other.maxX <= frame.minX + tolerance && overlap(other.minY, other.maxY, frame.minY, frame.maxY)
            case .right: return other.minX >= frame.maxX - tolerance && overlap(other.minY, other.maxY, frame.minY, frame.maxY)
            case .up: return other.maxY <= frame.minY + tolerance && overlap(other.minX, other.maxX, frame.minX, frame.maxX)
            case .down: return other.minY >= frame.maxY - tolerance && overlap(other.minX, other.maxX, frame.minX, frame.maxX)
            }
        }
        return candidates.min { first, second in
            let a = frames[first]
            let b = frames[second]
            let (gapA, gapB) = (gapAlong(direction, frame, a), gapAlong(direction, frame, b))
            if abs(gapA - gapB) > tolerance { return gapA < gapB }
            return (a.minY, a.minX) < (b.minY, b.minX)
        }
    }

    private static func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool {
        min(a1, b1) - max(a0, b0) > 1
    }

    private static func gapAlong(_ direction: Direction, _ from: CGRect, _ to: CGRect) -> CGFloat {
        switch direction {
        case .left: from.minX - to.maxX
        case .right: to.minX - from.maxX
        case .up: from.minY - to.maxY
        case .down: to.minY - from.maxY
        }
    }

    private static func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    func nextScreen(from key: WorkspaceKey, direction: Direction, context: TilingContext) -> WorkspaceKey? {
        guard let area = area(of: key, context: context) else { return nil }
        let others = context.screens.filter { $0.key != key }
        guard let index = Self.neighbor(of: area, in: others.map(\.area), direction: direction) else { return nil }
        return others[index].key
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
