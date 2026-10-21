import SwiftUI
import AppKit

enum Theme {
    /// 影视飓风 Gate 的主色 #2E55DB
    static let accent = Color(red: 0.180, green: 0.333, blue: 0.890)
    static let folder = Color(red: 0.310, green: 0.420, blue: 0.950)
    static let selection = accent.opacity(0.12)
    static let hover = Color.primary.opacity(0.05)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let sidebar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor(white: 0.962, alpha: 1)
    })
    static let canvas = Color(nsColor: .textBackgroundColor)
}

extension View {
    func cardStyle() -> some View {
        padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}


extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1)
    }
}
