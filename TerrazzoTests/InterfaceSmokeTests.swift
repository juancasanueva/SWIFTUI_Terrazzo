import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Terrazzo

/// Lays out the interface with a controller that was never started, so no real window is touched.
@MainActor
struct InterfaceSmokeTests {
    private func render(_ view: some View, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test func menuPanelRendersWhileAccessIsMissing() {
        let host = render(MenuPanelView(controller: AppController.shared), size: CGSize(width: 320, height: 600))
        #expect(host.fittingSize.width > 0)
    }

    @Test func settingsRender() {
        let host = render(SettingsView(controller: AppController.shared), size: CGSize(width: 560, height: 560))
        #expect(host.fittingSize.height > 0)
    }

    @Test func aDividerIsEasyToHitEvenInANarrowGap() {
        let narrow = LayoutDivider(
            slot: 0, movesHorizontally: true, frame: CGRect(x: 100, y: 10, width: 2, height: 500))
        #expect(DividerMetrics.hitFrame(of: narrow) == CGRect(x: 95, y: 210, width: 12, height: 100))

        let wide = LayoutDivider(
            slot: 0, movesHorizontally: false, frame: CGRect(x: 10, y: 100, width: 500, height: 20))
        #expect(DividerMetrics.hitFrame(of: wide) == CGRect(x: 210, y: 100, width: 100, height: 20))
    }

    @Test func aDividerIsNeverLongerThanItsGap() {
        let short = LayoutDivider(
            slot: 0, movesHorizontally: true, frame: CGRect(x: 100, y: 10, width: 12, height: 60))
        #expect(DividerMetrics.hitFrame(of: short) == short.frame)
    }

    @Test func aDividerIsWhite() {
        #expect(DividerMetrics.color == .white)
    }

    @Test func aDividerStandsOutOnlyWhenThePointerIsOnIt() {
        let rest = DividerMetrics.appearance(emphasized: false)
        let hover = DividerMetrics.appearance(emphasized: true)
        #expect(rest.opacity <= 0.3)
        #expect(hover.opacity == 1)
        #expect(hover.thickness > rest.thickness)
    }

    @Test func grabbingADividerOffCenterDoesNotMakeItJump() {
        let drag = DividerDrag(position: 500, pointer: 503)
        #expect(drag.position(for: 503) == 500)
        #expect(drag.position(for: 553) == 550)
    }

    @Test func aDividerStaysBelowGripsAndOtherWindows() {
        #expect(DividerMetrics.level == .normal)
        #expect(DividerMetrics.level.rawValue < NSWindow.Level.floating.rawValue)
    }

    private var strip: CGRect { CGRect(x: 500, y: 0, width: 12, height: 900) }
    private var elsewhere: CGRect { CGRect(x: 0, y: 0, width: 100, height: 100) }
    private var overStrip: CGRect { CGRect(x: 400, y: 300, width: 300, height: 200) }

    @Test func aDividerSitsAboveTheHighestTileWhenNothingElseIsInTheGap() {
        let windows = [
            StackedWindow(id: 9, frame: elsewhere), StackedWindow(id: 3, frame: elsewhere),
            StackedWindow(id: 1, frame: elsewhere),
        ]
        #expect(DividerMetrics.order(hitFrame: strip, tiles: [1, 3], frontToBack: windows) == .above(3))
    }

    @Test func anUntiledWindowOverTheGapKeepsItsClicksEvenBehindARaisedTile() {
        // Clicking a tile raises it above the float, which must still stay above the divider.
        let windows = [
            StackedWindow(id: 1, frame: elsewhere), StackedWindow(id: 9, frame: overStrip),
            StackedWindow(id: 8, frame: overStrip), StackedWindow(id: 3, frame: elsewhere),
        ]
        #expect(DividerMetrics.order(hitFrame: strip, tiles: [1, 3], frontToBack: windows) == .below(9))
    }

    @Test func aTileOverlappingTheGapIsNotACover() {
        let windows = [StackedWindow(id: 1, frame: overStrip)]
        #expect(DividerMetrics.order(hitFrame: strip, tiles: [1], frontToBack: windows) == .above(1))
    }

    @Test func aDividerWithNoTileOnScreenHasNoPlace() {
        let windows = [StackedWindow(id: 9, frame: elsewhere)]
        #expect(DividerMetrics.order(hitFrame: strip, tiles: [1], frontToBack: windows) == nil)
    }

    @Test func theTerrazzoIconIsTheDefault() {
        #expect(AppSettings().iconStyle == .terrazzo)
        #expect(IconStyle.terrazzo.usesBundledIcon)
        #expect(!IconStyle.washi.usesBundledIcon)
    }

    @Test func everyIconStyleDraws() {
        for style in IconStyle.allCases {
            #expect(AppIconRenderer.image(for: style).tiffRepresentation != nil)
        }
    }

    @Test func everyShortcutHasKeysAndAUniqueDefault() {
        let map = ShortcutMap()
        let unassigned: Set<ShortcutAction> = [.bigger, .smaller]
        let combos = ShortcutAction.allCases.filter { !unassigned.contains($0) }.compactMap { map.combo(for: $0) }
        #expect(combos.count == ShortcutAction.allCases.count - unassigned.count)
        #expect(Set(combos).count == combos.count)
    }

    @Test func everyKeyHasADistinctKeyCode() {
        let codes = ShortcutKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
        for key in ShortcutKey.allCases {
            #expect(ShortcutKey(keyCode: key.keyCode) == key)
        }
    }

    @Test func theSpanishPerAppSwitchSaysWhatItDoes() {
        let spanish = Bundle(for: AppController.self).path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:))
        #expect(spanish?.localizedString(forKey: "Tile %@", value: nil, table: nil) == "Incluir %@ en el mosaico")
    }

    @Test func aStringCatalogEntryExistsForTheStatusText() {
        let spanish = Bundle(for: AppController.self).path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:))
        #expect(spanish?.localizedString(forKey: "This Space is full", value: nil, table: nil) == "Este Espacio está lleno")
    }
}

@MainActor
struct GripMetricsTests {
    @Test func everySegmentIsBigEnoughToClick() {
        #expect(GripMetrics.hitHeight >= 24)
        #expect(GripMetrics.showingWidth >= 40)
        #expect(GripMetrics.waitingWidth >= 24)
        #expect(GripMetrics.dotTarget >= 24)
    }

    @Test func thePanelFitsEverySegment() {
        for count in 1...8 {
            let active = GripMetrics.collapsedSize(count: count, isActive: true)
            #expect(
                active.width
                    >= GripMetrics.showingWidth + CGFloat(count - 1) * (GripMetrics.waitingWidth + GripMetrics.spacing))
            let inactive = GripMetrics.collapsedSize(count: count, isActive: false)
            #expect(inactive.width >= CGFloat(count) * (GripMetrics.dotTarget + GripMetrics.spacing) - GripMetrics.spacing)
            #expect(active.height == GripMetrics.hitHeight)
        }
    }

    @Test func quickActionsShowTheCurrentShortcuts() {
        var map = ShortcutMap()
        #expect(GripMetrics.shortcutText(for: .makePrimary, in: map) == "⌃⌥↩")
        #expect(GripMetrics.shortcutText(for: .focus, in: map) == "⌃F")
        #expect(GripMetrics.shortcutText(for: .float, in: map) == "⌃T")
        map.bindings[ShortcutAction.focus.rawValue] = "ctrl+shift+y"
        #expect(GripMetrics.shortcutText(for: .focus, in: map) == "⌃⇧Y")
        map.bindings[ShortcutAction.float.rawValue] = ShortcutMap.off
        #expect(GripMetrics.shortcutText(for: .float, in: map) == "")
    }

    @Test func theNextScreenActionShowsTheMoveArrows() {
        var map = ShortcutMap()
        #expect(GripMetrics.screenMoveText(in: map) == "⌃⇧ ← →")
        map.bindings[ShortcutAction.swapLeft.rawValue] = "ctrl+opt+h"
        #expect(GripMetrics.screenMoveText(in: map) == "⌃⌥H ⌃⇧→")
        map.bindings[ShortcutAction.swapRight.rawValue] = ShortcutMap.off
        #expect(GripMetrics.screenMoveText(in: map) == "⌃⌥H")
    }

    @Test func theActionsBarFitsItsLargerActions() {
        #expect(GripMetrics.actionIconSize >= 26)
        let actions = GripMetrics.actionWidth * 4 + GripMetrics.spacing * 3
        #expect(GripMetrics.expandedSize.width >= actions + 12)
        #expect(GripMetrics.expandedSize.height >= GripMetrics.actionHeight + GripMetrics.chipIconSize + 30)
    }

    @Test func theActionsBarWaitsAndItsIconsAreLarge() {
        #expect(GripMetrics.chipIconSize >= 36)
        #expect(GripMetrics.expandedSize.height >= GripMetrics.chipIconSize + 56)
    }

    @Test func segmentsKeepTheirPlaceAndOnlyTheLongOneMoves() {
        let first = GripMetrics.segments(of: [4, 3])
        #expect(first.map(\.id) == [4, 3])
        #expect(first.map(\.width) == [GripMetrics.showingWidth, GripMetrics.waitingWidth])

        let afterSwitching = GripMetrics.segments(of: [3, 4])
        #expect(afterSwitching.map(\.id) == [4, 3])
        #expect(afterSwitching.map(\.width) == [GripMetrics.waitingWidth, GripMetrics.showingWidth])
        #expect(afterSwitching.map(\.isShowing) == [false, true])
    }

    @Test func theMostRecentlyUsedOrderDoesNotMoveSegments() {
        #expect(GripMetrics.segments(of: [3, 5, 4]).map(\.id) == [5, 4, 3])
        #expect(GripMetrics.segments(of: [4, 3, 5]).map(\.id) == [5, 4, 3])
    }

    @Test func stackBarDefaultsToOrangeAndAShortWait() {
        let bar = AppSettings().stackBar
        #expect(bar.color == "#FF9500")
        #expect(bar.hoverDelay == 1.2)
        #expect(bar.resolvedDelay == .milliseconds(1200))
    }

    @Test func aHandEditedDelayIsKeptInARange() {
        var bar = AppSettings.StackBar()
        bar.hoverDelay = -3
        #expect(bar.resolvedDelay == .zero)
        bar.hoverDelay = 500
        #expect(bar.resolvedDelay == .seconds(AppSettings.StackBar.maximumDelay))
    }

    @Test func aHandEditedColorFallsBackWhenInvalid() {
        var bar = AppSettings.StackBar()
        bar.color = "#00FF00"
        #expect(bar.resolvedColor.hexString == "#00FF00")
        bar.color = "green"
        #expect(bar.resolvedColor.hexString == "#FF9500")
    }

    @Test func stackBarSettingsLoadFromAPartialFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(#"{"stackBar": {"hoverDelay": 3}}"#.utf8).write(to: url)
        let settings = try ConfigFile(url: url, defaults: AppSettings()).load()
        #expect(settings.stackBar.hoverDelay == 3)
        #expect(settings.stackBar.color == "#FF9500")
    }
}

struct ProjectLinksTests {
    @Test func aboutLinksToTheRepositoryAndItsLicense() {
        #expect(ProjectLinks.repository.absoluteString == "https://github.com/juancasanueva/SWIFTUI_Terrazzo")
        #expect(ProjectLinks.license.absoluteString == "https://github.com/juancasanueva/SWIFTUI_Terrazzo/blob/main/LICENSE")
    }

    @Test func theLicenseFileIsTheOneAboutNames() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let license = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(license.hasPrefix("MIT License"))
    }
}
