import CoreGraphics

enum LayoutKind: String, Codable, CaseIterable, Sendable {
    case grid, columns, rows, side
}

enum MainSize: String, Codable, CaseIterable, Sendable {
    case half, sixty, twoThirds

    var fraction: CGFloat {
        switch self {
        case .half: 0.5
        case .sixty: 0.6
        case .twoThirds: 2.0 / 3.0
        }
    }
}

enum Orientation: String, Sendable {
    case landscape, ultrawide, vertical

    init(area: CGRect) {
        if area.height > area.width {
            self = .vertical
        } else if area.width / max(area.height, 1) >= 2 {
            self = .ultrawide
        } else {
            self = .landscape
        }
    }
}

/// A screen divided into tracks (columns, or rows when `rowsFirst`), each divided into cells.
struct LayoutShape: Equatable, Sendable {
    struct Cell: Equatable, Sendable {
        var slot: Int
        var weight: CGFloat
    }

    struct Track: Equatable, Sendable {
        var weight: CGFloat
        var cells: [Cell]
    }

    var rowsFirst: Bool
    var tracks: [Track]
    var trackKey: String
    var cellKey: String
}

/// Dragged edges, stored as fractions so they belong to screen positions rather than windows.
struct SizeOverrides: Codable, Equatable, Sendable {
    var tracks: [String: [CGFloat]] = [:]
    var cells: [String: [[CGFloat]]] = [:]

    var isEmpty: Bool { tracks.isEmpty && cells.isEmpty }
}

struct EdgeDeltas: Equatable, Sendable {
    var minX: CGFloat = 0
    var maxX: CGFloat = 0
    var minY: CGFloat = 0
    var maxY: CGFloat = 0
}

struct SolvedLayout: Equatable, Sendable {
    var frames: [CGRect]
    /// Slots that cannot reach their minimum size even after split lines move.
    var overflowingSlots: [Int]
}

enum StepResult: Equatable, Sendable {
    case changed, limit
}

enum LayoutEngine {
    static let usableSize = CGSize(width: 450, height: 320)
    /// Smallest size a window can be dragged or stepped to, whatever the app allows.
    static let resizeFloor = CGSize(width: 240, height: 140)
    static let stepFraction: CGFloat = 0.05

    // MARK: Shapes

    static func shape(
        kind: LayoutKind, count: Int, area: CGRect, main: MainSize, overrides: SizeOverrides
    ) -> LayoutShape {
        let orientation = Orientation(area: area)
        let n = max(1, count)
        let kind = orientation == .vertical && kind == .columns ? LayoutKind.rows : kind
        var rowsFirst = orientation == .vertical
        var slots: [[Int]]
        var trackWeights: [CGFloat]?
        var sharedTrackKey = false

        switch kind {
        case .grid:
            switch n {
            case 1: slots = [[0]]
            case 2: slots = [[0], [1]]
            case 3: slots = [[0], [1, 2]]
            default: slots = [[0, 3], [1, 2] + Array(4..<max(n, 4))]
            }
            sharedTrackKey = true
        case .columns:
            slots = (0..<n).map { [$0] }
            rowsFirst = false
            trackWeights = lineWeights(n, main: main)
        case .rows:
            slots = (0..<n).map { [$0] }
            rowsFirst = true
            trackWeights = lineWeights(n, main: main)
        case .side:
            if orientation == .ultrawide, n >= 3 {
                slots = [[0], [1], Array(2..<n)]
                let m = main.fraction
                trackWeights = [0.75 * m, 0.75 * (1 - m), 0.25]
            } else if orientation == .vertical, n >= 2 {
                slots = (0..<n).map { [$0] }
                let m = main.fraction
                trackWeights = [m] + Array(repeating: (1 - m) / CGFloat(n - 1), count: n - 1)
            } else {
                slots = n == 1 ? [[0]] : [[0], Array(1..<n)]
                sharedTrackKey = true
            }
        }

        let weights =
            trackWeights
            ?? (slots.count == 1 ? [1] : [main.fraction, 1 - main.fraction])
        let base = "\(kind.rawValue)-\(orientation.rawValue)"
        let trackKey = sharedTrackKey ? base : "\(base)-\(n)"
        let cellKey = "\(base)-\(n)"

        let resolvedTracks = overrides.tracks[trackKey].flatMap { $0.count == slots.count ? $0 : nil } ?? weights
        let resolvedCells = overrides.cells[cellKey]

        let tracks = slots.enumerated().map { index, cells -> LayoutShape.Track in
            let cellWeights: [CGFloat]
            if let stored = resolvedCells, stored.count == slots.count, stored[index].count == cells.count {
                cellWeights = stored[index]
            } else {
                cellWeights = Array(repeating: 1, count: cells.count)
            }
            return LayoutShape.Track(
                weight: resolvedTracks[index],
                cells: zip(cells, cellWeights).map { LayoutShape.Cell(slot: $0, weight: $1) })
        }
        return LayoutShape(rowsFirst: rowsFirst, tracks: tracks, trackKey: trackKey, cellKey: cellKey)
    }

    /// Half means equal shares when lines of windows are involved; larger sizes favor the first line.
    private static func lineWeights(_ n: Int, main: MainSize) -> [CGFloat] {
        guard n > 1, main != .half else { return Array(repeating: 1, count: n) }
        let m = main.fraction
        return [m] + Array(repeating: (1 - m) / CGFloat(n - 1), count: n - 1)
    }

    // MARK: Solving

    static func solve(shape: LayoutShape, area: CGRect, gap: CGFloat, minimums: [Int: CGSize]) -> SolvedLayout {
        let trackLengths = solvedTrackLengths(shape: shape, area: area, gap: gap, minimums: minimums)
        var frames = [CGRect](repeating: .zero, count: shape.tracks.flatMap(\.cells).count)
        var overflowing: [Int] = []
        if trackLengths.overflow, let last = shape.tracks.last?.cells.last {
            overflowing.append(last.slot)
        }

        let mainOrigin = shape.rowsFirst ? area.minY : area.minX
        var position = mainOrigin + gap
        for (index, track) in shape.tracks.enumerated() {
            let length = trackLengths.sizes[index]
            let cellLengths = solvedCellLengths(track: track, shape: shape, area: area, gap: gap, minimums: minimums)
            if cellLengths.overflow, let last = track.cells.last, !overflowing.contains(last.slot) {
                overflowing.append(last.slot)
            }
            var crossPosition = (shape.rowsFirst ? area.minX : area.minY) + gap
            for (cellIndex, cell) in track.cells.enumerated() {
                let crossLength = cellLengths.sizes[cellIndex]
                frames[cell.slot] =
                    shape.rowsFirst
                    ? CGRect(x: crossPosition, y: position, width: crossLength, height: length)
                    : CGRect(x: position, y: crossPosition, width: length, height: crossLength)
                crossPosition += crossLength + gap
            }
            position += length + gap
        }
        return SolvedLayout(frames: frames, overflowingSlots: overflowing.sorted())
    }

    private static func solvedTrackLengths(
        shape: LayoutShape, area: CGRect, gap: CGFloat, minimums: [Int: CGSize]
    ) -> (sizes: [CGFloat], overflow: Bool) {
        let total = shape.rowsFirst ? area.height : area.width
        let available = total - gap * CGFloat(shape.tracks.count + 1)
        let mins = shape.tracks.map { track in
            track.cells.map { axisLength(minimums[$0.slot] ?? .zero, along: shape.rowsFirst) }.max() ?? 0
        }
        return distribute(weights: shape.tracks.map(\.weight), available: available, minimums: mins)
    }

    private static func solvedCellLengths(
        track: LayoutShape.Track, shape: LayoutShape, area: CGRect, gap: CGFloat, minimums: [Int: CGSize]
    ) -> (sizes: [CGFloat], overflow: Bool) {
        let total = shape.rowsFirst ? area.width : area.height
        let available = total - gap * CGFloat(track.cells.count + 1)
        let mins = track.cells.map { axisLength(minimums[$0.slot] ?? .zero, along: !shape.rowsFirst) }
        return distribute(weights: track.cells.map(\.weight), available: available, minimums: mins)
    }

    private static func axisLength(_ size: CGSize, along rows: Bool) -> CGFloat {
        rows ? size.height : size.width
    }

    /// Shares `available` by weight, then moves split lines so every minimum is met when possible.
    static func distribute(
        weights: [CGFloat], available: CGFloat, minimums: [CGFloat]
    ) -> (sizes: [CGFloat], overflow: Bool) {
        let needed = minimums.reduce(0, +)
        if needed > available {
            let scale = available / max(needed, 1)
            return (minimums.map { halfPoint($0 * scale) }, true)
        }
        var locked = [CGFloat?](repeating: nil, count: weights.count)
        while true {
            let remaining = available - locked.compactMap { $0 }.reduce(0, +)
            let freeWeight = zip(weights, locked).filter { $0.1 == nil }.map(\.0).reduce(0, +)
            var sizes = [CGFloat](repeating: 0, count: weights.count)
            var changed = false
            for index in weights.indices {
                if let value = locked[index] {
                    sizes[index] = value
                    continue
                }
                let size = freeWeight > 0 ? remaining * weights[index] / freeWeight : 0
                if size < minimums[index] {
                    locked[index] = minimums[index]
                    changed = true
                }
                sizes[index] = size
            }
            if !changed {
                return (sizes.map(halfPoint), false)
            }
        }
    }

    private static func halfPoint(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }

    // MARK: Capacity

    static func maxCount(kind: LayoutKind, area: CGRect, gap: CGFloat) -> Int {
        switch Orientation(area: area) {
        case .vertical:
            switch kind {
            case .grid: return 4
            case .rows, .columns: return 3
            case .side: return 5
            }
        case .ultrawide where kind == .side:
            return 5
        default:
            for count in stride(from: 4, to: 1, by: -1) {
                let candidate = shape(
                    kind: kind, count: count, area: area, main: .half, overrides: SizeOverrides())
                let frames = solve(shape: candidate, area: area, gap: gap, minimums: [:]).frames
                if frames.allSatisfy({ $0.width >= usableSize.width && $0.height >= usableSize.height }) {
                    return count
                }
            }
            return 1
        }
    }

    // MARK: Resizing

    @discardableResult
    static func moveEdges(
        slot: Int, kind: LayoutKind, count: Int, area: CGRect, main: MainSize, gap: CGFloat,
        minimums: [Int: CGSize], deltas: EdgeDeltas, overrides: inout SizeOverrides
    ) -> Bool {
        let current = shape(kind: kind, count: count, area: area, main: main, overrides: overrides)
        guard let trackIndex = current.tracks.firstIndex(where: { $0.cells.contains { $0.slot == slot } }),
            let cellIndex = current.tracks[trackIndex].cells.firstIndex(where: { $0.slot == slot })
        else { return false }

        let floored = (0..<current.tracks.flatMap(\.cells).count).reduce(into: [Int: CGSize]()) { result, index in
            let minimum = minimums[index] ?? .zero
            result[index] = CGSize(
                width: max(minimum.width, resizeFloor.width), height: max(minimum.height, resizeFloor.height))
        }

        var changed = false

        // Track edges run along the main axis.
        var trackSizes = solvedTrackLengths(shape: current, area: area, gap: gap, minimums: minimums).sizes
        let trackMins = current.tracks.map { track in
            track.cells.map { axisLength(floored[$0.slot] ?? .zero, along: current.rowsFirst) }.max() ?? 0
        }
        let lowTrack = current.rowsFirst ? deltas.minY : deltas.minX
        let highTrack = current.rowsFirst ? deltas.maxY : deltas.maxX
        if trackIndex < trackSizes.count - 1,
            moveEdge(&trackSizes, at: trackIndex, by: highTrack, minimums: trackMins) {
            changed = true
        }
        if trackIndex > 0, moveEdge(&trackSizes, at: trackIndex - 1, by: lowTrack, minimums: trackMins) {
            changed = true
        }
        if changed {
            overrides.tracks[current.trackKey] = normalized(trackSizes)
        }

        // Cell edges run along the cross axis, within the track.
        let track = current.tracks[trackIndex]
        var cellSizes = solvedCellLengths(track: track, shape: current, area: area, gap: gap, minimums: minimums).sizes
        let cellMins = track.cells.map { axisLength(floored[$0.slot] ?? .zero, along: !current.rowsFirst) }
        let lowCell = current.rowsFirst ? deltas.minX : deltas.minY
        let highCell = current.rowsFirst ? deltas.maxX : deltas.maxY
        var cellChanged = false
        if cellIndex < cellSizes.count - 1,
            moveEdge(&cellSizes, at: cellIndex, by: highCell, minimums: cellMins) {
            cellChanged = true
        }
        if cellIndex > 0, moveEdge(&cellSizes, at: cellIndex - 1, by: lowCell, minimums: cellMins) {
            cellChanged = true
        }
        if cellChanged {
            var stored = current.tracks.map { $0.cells.map(\.weight) }
            stored[trackIndex] = normalized(cellSizes)
            overrides.cells[current.cellKey] = stored
            changed = true
        }
        return changed
    }

    private static func moveEdge(
        _ sizes: inout [CGFloat], at index: Int, by delta: CGFloat, minimums: [CGFloat]
    ) -> Bool {
        guard abs(delta) >= 1 else { return false }
        var applied = delta
        if delta > 0 {
            applied = min(delta, sizes[index + 1] - minimums[index + 1])
        } else {
            applied = max(delta, minimums[index] - sizes[index])
        }
        guard abs(applied) >= 1 else { return false }
        sizes[index] += applied
        sizes[index + 1] -= applied
        return true
    }

    private static func normalized(_ sizes: [CGFloat]) -> [CGFloat] {
        let total = sizes.reduce(0, +)
        return total > 0 ? sizes.map { $0 / total } : sizes
    }

    static func step(
        slot: Int, grow: Bool, kind: LayoutKind, count: Int, area: CGRect, main: MainSize, gap: CGFloat,
        minimums: [Int: CGSize], overrides: inout SizeOverrides
    ) -> StepResult {
        let sign: CGFloat = grow ? 1 : -1
        let dx = area.width * stepFraction * sign
        let dy = area.height * stepFraction * sign
        let moved = moveEdges(
            slot: slot, kind: kind, count: count, area: area, main: main, gap: gap, minimums: minimums,
            deltas: EdgeDeltas(minX: -dx, maxX: dx, minY: -dy, maxY: dy), overrides: &overrides)
        return moved ? .changed : .limit
    }
}
