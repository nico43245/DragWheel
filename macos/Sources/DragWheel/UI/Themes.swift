import SwiftUI

/// A "liquid glass" finish for the wheel and windows.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    /// Tint laid over the blurred glass.
    let glass: Color
    /// Petal fill at rest.
    let petal: Color
    /// Hovered petal / highlights.
    let accent: Color
    /// Label colour on petals.
    let text: Color
    /// Label colour on the hovered petal.
    let textOnAccent: Color
    let isDark: Bool

    static let all: [Theme] = [
        Theme(id: "tangerine", name: "Liquid Tangerine", emoji: "🍊",
              glass: Color(hex: 0xFFF7EC, alpha: 0.55),
              petal: Color(hex: 0xFFFFFF, alpha: 0.72),
              accent: Color(hex: 0xFA6C1E),
              text: Color(hex: 0x3A2414),
              textOnAccent: .white,
              isDark: false),
        Theme(id: "neon", name: "Cyber Neon", emoji: "⚡",
              glass: Color(hex: 0x0B1020, alpha: 0.62),
              petal: Color(hex: 0x141C33, alpha: 0.78),
              accent: Color(hex: 0x00F2FE),
              text: Color(hex: 0xCFEFFF),
              textOnAccent: Color(hex: 0x031018),
              isDark: true),
        Theme(id: "emerald", name: "Emerald Forest", emoji: "🌲",
              glass: Color(hex: 0xEAF5EE, alpha: 0.55),
              petal: Color(hex: 0xF7FFFA, alpha: 0.72),
              accent: Color(hex: 0x10B981),
              text: Color(hex: 0x0F3B2C),
              textOnAccent: .white,
              isDark: false),
        Theme(id: "obsidian", name: "Midnight Obsidian", emoji: "🌑",
              glass: Color(hex: 0x050505, alpha: 0.70),
              petal: Color(hex: 0x1A1A1A, alpha: 0.82),
              accent: Color(hex: 0xE5E5E5),
              text: Color(hex: 0xD4D4D4),
              textOnAccent: Color(hex: 0x0A0A0A),
              isDark: true),
        Theme(id: "rose", name: "Sunset Rose", emoji: "🌸",
              glass: Color(hex: 0xFFEEF1, alpha: 0.55),
              petal: Color(hex: 0xFFFFFF, alpha: 0.70),
              accent: Color(hex: 0xF43F5E),
              text: Color(hex: 0x4C1424),
              textOnAccent: .white,
              isDark: false),
    ]
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
