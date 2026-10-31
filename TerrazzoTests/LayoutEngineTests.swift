import CoreGraphics
import Testing
@testable import Terrazzo

@MainActor
struct LayoutEngineTests {
    let laptop = CGRect(x: 0, y: 32, width: 1512, height: 945)
    let monitor = CGRect(x: 0, y: 25, width: 1920, height: 1055)
    let ultrawide = CGRect(x: 0, y: 25, width: 3440, height: 1415)
    let vertical = CGRect(x: 0, y: 25, width: 1080, height: 1895)

    private func frames(
        _ kind: LayoutKind, _ count: Int, in area: CGRect, main: MainSize = .half, gap: CGFloat = 0,
        overrides: SizeOverrides = SizeOverrides(), mins: [Int: CGSize] = [:]
    ) -> [CGRect] {
        let shape = LayoutEngine.shape(kind: kind, count: count, area: area, main: main, overrides: overrides)
        return LayoutEngine.solve(shape: shape, area: area, gap: gap, minimums: mins).frames
    }

    private func dividers(
        _ kind: LayoutKind, _ count: Int, in area: CGRect, gap: CGFloat
    ) -> [LayoutDivider] {
        let shape = LayoutEngine.shape(kind: kind, count: count, area: area, main: .half, overrides: SizeOverrides())
        return LayoutEngine.dividers(
            shape: shape, frames: LayoutEngine.solve(shape: shape, area: area, gap: gap, minimums: [:]).frames)
    }

    @Test func aSingleWindowHasNoDivider() {
        #expect(dividers(.grid, 1, in: laptop, gap: 12).isEmpty)
    }

    @Test func dividersFillTheGapsBetweenTiles() {
        let result = dividers(.grid, 3, in: laptop, gap: 12)
        #expect(
            result == [
                LayoutDivider(
                    slot: 0, movesHorizontally: true, frame: CGRect(x: 750, y: 44, width: 12, height: 921)),
                LayoutDivider(
                    slot: 1, movesHorizontally: false, frame: CGRect(x: 762, y: 498.5, width: 738, height: 12)),
            ])
    }

    @Test func aTrackDividerSpansEveryCell() {
        let result = dividers(.grid, 4, in: laptop, gap: 12)
        let track = result.first { $0.movesHorizontally }
        #expect(track?.frame == CGRect(x: 750, y: 44, width: 12, height: 921))
        #expect(result.filter { !$0.movesHorizontally }.map(\.slot).sorted() == [0, 1])
    }

    @Test func rowsHaveDividersThatMoveVertically() {
        let result = dividers(.rows, 2, in: laptop, gap: 0)
        #expect(
            result == [
                LayoutDivider(
                    slot: 0, movesHorizontally: false, frame: CGRect(x: 0, y: 504.5, width: 1512, height: 0))
            ])
        #expect(result[0].position == 504.5)
    }

    @Test func singleWindowFillsTheArea() {
        #expect(frames(.grid, 1, in: laptop) == [laptop])
    }

    @Test func gridTwoIsSideBySideWithPrimaryOnTheLeft() {
        let result = frames(.grid, 2, in: laptop)
        #expect(result[0] == CGRect(x: 0, y: 32, width: 756, height: 945))
        #expect(result[1] == CGRect(x: 756, y: 32, width: 756, height: 945))
    }

    @Test func gridThreeSplitsTheRightHalf() {
        let result = frames(.grid, 3, in: laptop)
        #expect(result[0].height == 945)
        #expect(result[1] == CGRect(x: 756, y: 32, width: 756, height: 472.5))
        #expect(result[2] == CGRect(x: 756, y: 504.5, width: 756, height: 472.5))
    }

    @Test func gridFourGivesTheFourthThePrimaryColumnBottom() {
        let result = frames(.grid, 4, in: laptop)
        #expect(result[0] == CGRect(x: 0, y: 32, width: 756, height: 472.5))
        #expect(result[3] == CGRect(x: 0, y: 504.5, width: 756, height: 472.5))
    }

    @Test func columnsAreFullHeightAndRowsFullWidth() {
        let columns = frames(.columns, 3, in: monitor)
        #expect(columns.allSatisfy { $0.height == monitor.height })
        #expect(columns[0].minX < columns[1].minX)
        let rows = frames(.rows, 3, in: monitor)
        #expect(rows.allSatisfy { $0.width == monitor.width })
        #expect(rows[0].minY < rows[1].minY)
    }

    @Test func columnsStartEqualAtHalfAndFollowLargerMainSizes() {
        #expect(frames(.columns, 3, in: monitor)[0].width == 640)
        let result = frames(.columns, 3, in: monitor, main: .sixty)
        #expect(result[0].width == 1152)
        #expect(result[1].width == 384)
    }

    @Test func sidePutsTheOthersInOneRightColumn() {
        let result = frames(.side, 4, in: monitor, main: .twoThirds)
        #expect(result[0].width == 1280)
        #expect(result[1...3].allSatisfy { $0.minX == 1280 && $0.width == 640 })
    }

    @Test func ultrawideSideKeepsTwoLargeAndANarrowQuarterColumn() {
        let result = frames(.side, 5, in: ultrawide)
        #expect(result[0].width == 1290)
        #expect(result[1].width == 1290)
        #expect(result[2...4].allSatisfy { $0.width == 860 && $0.minX == 2580 })
        #expect(frames(.side, 2, in: ultrawide)[0].width == 1720)
    }

    @Test func verticalLayoutsPutTheMainWindowOnTop() {
        #expect(frames(.grid, 2, in: vertical)[1].minY > frames(.grid, 2, in: vertical)[0].maxY - 1)
        let three = frames(.grid, 3, in: vertical)
        #expect(three[0].width == 1080)
        #expect(three[1].minY == three[2].minY)
        let side = frames(.side, 5, in: vertical)
        #expect(side[0].height == vertical.height / 2)
        #expect(side[1...4].allSatisfy { $0.width == 1080 })
    }

    @Test func columnsBecomeRowsOnVertical() {
        #expect(frames(.columns, 2, in: vertical)[0].width == 1080)
    }

    @Test(arguments: [
        (LayoutKind.grid, 4, 4), (.columns, 3, 4), (.rows, 2, 3), (.side, 3, 4),
    ])
    func maximumWindowsAtUsableSize(kind: LayoutKind, laptopMax: Int, monitorMax: Int) {
        #expect(LayoutEngine.maxCount(kind: kind, area: laptop, gap: 8) == laptopMax)
        #expect(LayoutEngine.maxCount(kind: kind, area: monitor, gap: 8) == monitorMax)
    }

    @Test func fiveIsOnlyReachableInSideOnUltrawideOrVertical() {
        #expect(LayoutEngine.maxCount(kind: .side, area: ultrawide, gap: 8) == 5)
        #expect(LayoutEngine.maxCount(kind: .side, area: vertical, gap: 8) == 5)
        #expect(LayoutEngine.maxCount(kind: .rows, area: vertical, gap: 8) == 3)
        #expect(LayoutEngine.maxCount(kind: .grid, area: ultrawide, gap: 8) == 4)
    }

    @Test func gapsSurroundEveryWindow() {
        let result = frames(.grid, 2, in: CGRect(x: 0, y: 0, width: 1000, height: 500), gap: 8)
        #expect(result[0] == CGRect(x: 8, y: 8, width: 488, height: 484))
        #expect(result[1] == CGRect(x: 504, y: 8, width: 488, height: 484))
    }

    @Test func splitLineMovesToSatisfyALearnedMinimum() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let result = frames(.grid, 2, in: area, mins: [1: CGSize(width: 700, height: 100)])
        #expect(result[1].width == 700)
        #expect(result[0].width == 300)
    }

    @Test func impossibleMinimumIsReported() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let shape = LayoutEngine.shape(kind: .grid, count: 2, area: area, main: .half, overrides: SizeOverrides())
        let solved = LayoutEngine.solve(
            shape: shape, area: area, gap: 0,
            minimums: [0: CGSize(width: 700, height: 100), 1: CGSize(width: 700, height: 100)])
        #expect(solved.overflowingSlots == [1])
    }

    @Test func draggedTrackEdgeIsStoredAndCarriesAcrossGridCounts() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        var overrides = SizeOverrides()
        let moved = LayoutEngine.moveEdges(
            slot: 0, kind: .grid, count: 2, area: area, main: .half, gap: 0, minimums: [:],
            deltas: EdgeDeltas(maxX: 100), overrides: &overrides)
        #expect(moved)
        #expect(frames(.grid, 2, in: area, overrides: overrides)[0].width == 600)
        #expect(frames(.grid, 3, in: area, overrides: overrides)[0].width == 600)
        #expect(!overrides.isEmpty)
    }

    @Test func outerEdgeDragDoesNothing() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        var overrides = SizeOverrides()
        let moved = LayoutEngine.moveEdges(
            slot: 0, kind: .grid, count: 2, area: area, main: .half, gap: 0, minimums: [:],
            deltas: EdgeDeltas(minX: -100), overrides: &overrides)
        #expect(!moved)
        #expect(overrides.isEmpty)
    }

    @Test func draggedEdgeStopsAtTheMinimumOfTheOtherSide() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        var overrides = SizeOverrides()
        _ = LayoutEngine.moveEdges(
            slot: 0, kind: .grid, count: 2, area: area, main: .half, gap: 0,
            minimums: [1: CGSize(width: 450, height: 100)],
            deltas: EdgeDeltas(maxX: 300), overrides: &overrides)
        #expect(frames(.grid, 2, in: area, overrides: overrides)[0].width == 550)
    }

    @Test func draggedCellEdgeResizesWithinItsColumn() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        var overrides = SizeOverrides()
        _ = LayoutEngine.moveEdges(
            slot: 1, kind: .grid, count: 3, area: area, main: .half, gap: 0, minimums: [:],
            deltas: EdgeDeltas(maxY: 100), overrides: &overrides)
        let result = frames(.grid, 3, in: area, overrides: overrides)
        #expect(result[1].height == 350)
        #expect(result[2].height == 150)
        #expect(result[0].height == 500)
    }

    @Test func stepResizeReportsLimits() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 500)
        var overrides = SizeOverrides()
        let single = LayoutEngine.step(
            slot: 0, grow: true, kind: .grid, count: 1, area: area, main: .half, gap: 0, minimums: [:],
            overrides: &overrides)
        #expect(single == .limit)
        let grown = LayoutEngine.step(
            slot: 0, grow: true, kind: .grid, count: 2, area: area, main: .half, gap: 0, minimums: [:],
            overrides: &overrides)
        #expect(grown == .changed)
        #expect(frames(.grid, 2, in: area, overrides: overrides)[0].width > 500)
    }
}
