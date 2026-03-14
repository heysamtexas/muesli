import SwiftUI

enum MuesliTheme {
    // MARK: - Colors — Backgrounds (layered, darkest to lightest)

    static let backgroundDeep   = Color(hex: 0x111214)
    static let backgroundBase   = Color(hex: 0x161719)
    static let backgroundRaised = Color(hex: 0x1C1D20)
    static let backgroundHover  = Color(hex: 0x232528)

    // MARK: - Surfaces (interactive elements)

    static let surfacePrimary   = Color(hex: 0x262830)
    static let surfaceSelected  = Color(hex: 0x2E3340)
    static let surfaceBorder    = Color.white.opacity(0.07)

    // MARK: - Text hierarchy

    static let textPrimary      = Color.white.opacity(0.92)
    static let textSecondary    = Color.white.opacity(0.62)
    static let textTertiary     = Color.white.opacity(0.40)

    // MARK: - Accent

    static let accent           = Color(hex: 0x6BA3F7)
    static let accentSubtle     = Color(hex: 0x6BA3F7).opacity(0.15)

    // MARK: - Semantic

    static let recording        = Color(hex: 0xEF4444)
    static let transcribing     = Color(hex: 0xF59E0B)
    static let success          = Color(hex: 0x34D399)

    // MARK: - Typography (SF Pro via .system())

    static func title1() -> Font { .system(size: 28, weight: .bold) }
    static func title2() -> Font { .system(size: 22, weight: .semibold) }
    static func title3() -> Font { .system(size: 18, weight: .semibold) }
    static func headline() -> Font { .system(size: 15, weight: .semibold) }
    static func body() -> Font { .system(size: 14, weight: .regular) }
    static func callout() -> Font { .system(size: 13, weight: .regular) }
    static func caption() -> Font { .system(size: 12, weight: .regular) }
    static func captionMedium() -> Font { .system(size: 12, weight: .medium) }

    // MARK: - Spacing (4pt grid)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner radii

    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
    static let cornerLarge: CGFloat = 14
    static let cornerXL: CGFloat = 20
}

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
