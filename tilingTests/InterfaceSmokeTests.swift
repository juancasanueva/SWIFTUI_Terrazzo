import AppKit
import Foundation
import SwiftUI
import Testing
@testable import tiling

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
