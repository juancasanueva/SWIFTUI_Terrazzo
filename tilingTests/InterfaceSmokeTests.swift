import AppKit
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
        let combos = ShortcutAction.allCases.compactMap { map.combo(for: $0) }
        #expect(combos.count == ShortcutAction.allCases.count)
        #expect(Set(combos).count == combos.count)
    }

    @Test func everyKeyHasADistinctKeyCode() {
        let codes = ShortcutKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
        for key in ShortcutKey.allCases {
            #expect(ShortcutKey(keyCode: key.keyCode) == key)
        }
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
}
