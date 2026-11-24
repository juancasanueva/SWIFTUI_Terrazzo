import SwiftUI

/// A workspace's layout buttons and window-count buttons, used by the menu bar panel and by Settings.
struct LayoutChoiceControls: View {
    let choice: LayoutChoice
    let onKind: (LayoutKind) -> Void
    let onCount: (Int) -> Void

    var body: some View {
        HStack {
            ForEach(LayoutKind.allCases, id: \.self) { option in
                Button {
                    onKind(option)
                } label: {
                    Image(systemName: option.symbol).frame(width: 26, height: 20)
                }
                .buttonStyle(.bordered)
                .tint(option == choice.kind ? .accentColor : nil)
                .disabled(choice.isVertical && option == .columns)
                .help(Text(option.title))
                .accessibilityLabel(Text(option.title))
            }
            Spacer()
            ForEach(1...(choice.maxCount == 5 ? 5 : 4), id: \.self) { count in
                Button("\(count)") { onCount(count) }
                    .buttonStyle(.bordered)
                    .tint(count == choice.count ? .accentColor : nil)
                    .disabled(count > choice.maxCount)
            }
        }
    }
}
