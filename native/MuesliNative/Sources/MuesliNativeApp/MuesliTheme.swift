import SwiftUI
import MuesliCore

private struct MuesliThemeColorToken {
    let dark: Int
    let light: Int
    var darkAlpha: CGFloat = 1
    var lightAlpha: CGFloat = 1

    var color: Color { Color(nsColor: nsColor) }
    var lightColor: Color { Color(nsColor: NSColor(hex: light, alpha: lightAlpha)) }

    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(
                hex: isDark ? dark : light,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        }
    }
}

private struct MuesliVisualPalette {
    let backgroundDeep: MuesliThemeColorToken
    let backgroundBase: MuesliThemeColorToken
    let backgroundRaised: MuesliThemeColorToken
    let backgroundHover: MuesliThemeColorToken
    let surfacePrimary: MuesliThemeColorToken
    let surfaceSelected: MuesliThemeColorToken
    let surfaceBorder: MuesliThemeColorToken
    let textPrimary: MuesliThemeColorToken
    let textSecondary: MuesliThemeColorToken
    let textTertiary: MuesliThemeColorToken
    let accent: MuesliThemeColorToken
    var recording = MuesliThemeColorToken(dark: 0xFF657C, light: 0xE53955)
    var transcribing = MuesliThemeColorToken(dark: 0xFFC766, light: 0xD97706)
    var success = MuesliThemeColorToken(dark: 0x45D6A8, light: 0x16876A)
    var destructive = MuesliThemeColorToken(dark: 0xFF657C, light: 0xC92F49)
    var streak = MuesliThemeColorToken(dark: 0xFFD071, light: 0xD97706)
    var joinAction = MuesliThemeColorToken(dark: 0x45D6A8, light: 0x16876A)
    var joinActionSecondary = MuesliThemeColorToken(dark: 0x2FA783, light: 0x116B55)
}

enum MuesliVisualTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case strawberryMilk
    case cherryRibbon
    case lavenderDream
    case peachSorbet
    case mintMacaron
    case roseQuartz
    case neonGrid
    case auroraGlass
    case solarFlare

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: "Classic"
        case .strawberryMilk: "Strawberry Milk"
        case .cherryRibbon: "Cherry Ribbon"
        case .lavenderDream: "Lavender Dream"
        case .peachSorbet: "Peach Sorbet"
        case .mintMacaron: "Mint Macaron"
        case .roseQuartz: "Rose Quartz"
        case .neonGrid: "Neon Grid"
        case .auroraGlass: "Aurora Glass"
        case .solarFlare: "Solar Flare"
        }
    }

    var detail: String {
        switch self {
        case .classic: "Clean, calm, and focused."
        case .strawberryMilk: "Blush pink, creamy, and extra sweet."
        case .cherryRibbon: "Cherry red, soft pink, and playful."
        case .lavenderDream: "Lilac, pearl, and quietly magical."
        case .peachSorbet: "Peach, cream, and a warm coral glow."
        case .mintMacaron: "Fresh mint with a berry-pink bow."
        case .roseQuartz: "Dusty rose, pearl, and soft plum."
        case .neonGrid: "Electric cyan on deep-space ink."
        case .auroraGlass: "Iridescent teal with glassy depth."
        case .solarFlare: "Hot orange, magenta, and midnight."
        }
    }

    var icon: String {
        switch self {
        case .classic: "waveform"
        case .strawberryMilk: "heart.fill"
        case .cherryRibbon: "heart.circle.fill"
        case .lavenderDream: "moon.stars.fill"
        case .peachSorbet: "sun.haze.fill"
        case .mintMacaron: "leaf.fill"
        case .roseQuartz: "diamond.fill"
        case .neonGrid: "square.grid.3x3.fill"
        case .auroraGlass: "sparkles"
        case .solarFlare: "sun.max.fill"
        }
    }

    var applicationIconFilename: String {
        switch self {
        case .classic: "muesli.icns"
        case .strawberryMilk: "mimo_strawberry_app_icon.png"
        case .cherryRibbon, .lavenderDream, .peachSorbet, .mintMacaron, .roseQuartz,
             .neonGrid, .auroraGlass, .solarFlare:
            "muesli.icns"
        }
    }

    var usesCuteStyling: Bool {
        switch self {
        case .strawberryMilk, .cherryRibbon, .lavenderDream, .peachSorbet, .mintMacaron, .roseQuartz:
            true
        case .classic, .neonGrid, .auroraGlass, .solarFlare: false
        }
    }

    var usesPackagedIconPreview: Bool {
        self == .classic || self == .strawberryMilk
    }

    var previewBackground: Color {
        switch self {
        case .classic: Color(hex: 0xF0F4FA)
        case .strawberryMilk: Color(hex: 0xFFF0F5)
        case .cherryRibbon, .lavenderDream, .peachSorbet, .mintMacaron, .roseQuartz,
             .neonGrid, .auroraGlass, .solarFlare:
            palette.backgroundDeep.lightColor
        }
    }

    var previewAccent: Color {
        palette.accent.lightColor
    }

    /// Preview cards use their light palettes even while Settings is in dark mode.
    /// Keeping their matching text colors with the preview tokens prevents the
    /// surrounding active theme from reducing card contrast.
    var previewTextPrimary: Color {
        self == .classic ? Color(hex: 0x152033) : palette.textPrimary.lightColor
    }

    var previewTextSecondary: Color {
        self == .classic ? Color.black.opacity(0.58) : palette.textSecondary.lightColor
    }

    static func resolved(_ rawValue: String?) -> MuesliVisualTheme {
        rawValue.flatMap(MuesliVisualTheme.init(rawValue:)) ?? .classic
    }

    func accentHex(afterSelecting currentAccentHex: String) -> String {
        preferredAccentHex ?? currentAccentHex
    }

    var preferredAccentHex: String? {
        switch self {
        case .classic: nil
        case .strawberryMilk: MuesliTheme.pinkAccentPresetHex
        case .cherryRibbon: "c81e43"
        case .lavenderDream: "7652b8"
        case .peachSorbet: "c94f35"
        case .mintMacaron: "a92f5b"
        case .roseQuartz: "a83b6a"
        case .neonGrid: "08788f"
        case .auroraGlass: "08766e"
        case .solarFlare: "c84a0b"
        }
    }

    fileprivate var palette: MuesliVisualPalette {
        switch self {
        case .classic:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x0B0C0E, light: 0xF5F5F7),
                backgroundBase: .init(dark: 0x161719, light: 0xFFFFFF),
                backgroundRaised: .init(dark: 0x1C1D20, light: 0xF0F0F2),
                backgroundHover: .init(dark: 0x232528, light: 0xE8E8EC),
                surfacePrimary: .init(dark: 0x262830, light: 0xE5E5EA),
                surfaceSelected: .init(dark: 0x2E3340, light: 0xD6DFFE),
                surfaceBorder: .init(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.07, lightAlpha: 0.08),
                textPrimary: .init(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.92, lightAlpha: 0.88),
                textSecondary: .init(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.62, lightAlpha: 0.55),
                textTertiary: .init(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.40, lightAlpha: 0.33),
                accent: .init(dark: MuesliTheme.defaultAccentDarkHex, light: MuesliTheme.defaultAccentLightHex),
                recording: .init(dark: 0xEF4444, light: 0xEF4444),
                transcribing: .init(dark: 0xF59E0B, light: 0xF59E0B),
                success: .init(dark: 0x34D399, light: 0x34D399),
                destructive: .init(dark: 0xFF0000, light: 0xFF0000),
                streak: .init(dark: 0xFF8000, light: 0xFF8000),
                joinAction: .init(dark: 0x33B887, light: 0x33B887),
                joinActionSecondary: .init(dark: 0x26946B, light: 0x26946B)
            )
        case .strawberryMilk:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x21151D, light: 0xF9DFE9),
                backgroundBase: .init(dark: 0x2A1923, light: 0xFFF7FA),
                backgroundRaised: .init(dark: 0x36222D, light: 0xFFFDFE),
                backgroundHover: .init(dark: 0x4A2C3B, light: 0xF8D9E6),
                surfacePrimary: .init(dark: 0x3B2632, light: 0xFFF0F5),
                surfaceSelected: .init(dark: 0x553044, light: 0xFFD9E8),
                surfaceBorder: .init(dark: 0xFFB3CE, light: 0xB44B72, darkAlpha: 0.25, lightAlpha: 0.25),
                textPrimary: .init(dark: 0xFFF1F6, light: 0x4A2434),
                textSecondary: .init(dark: 0xD8B6C5, light: 0x765465),
                textTertiary: .init(dark: 0xAA8295, light: 0xA07E8E),
                accent: .init(dark: 0xFF8CB8, light: 0xE94F8A),
                recording: .init(dark: 0xFF8CB8, light: 0xE94F8A),
                transcribing: .init(dark: 0xD7A0FF, light: 0xA75AC7),
                success: .init(dark: 0x72D8BF, light: 0x2E9F87),
                destructive: .init(dark: 0xFF8B96, light: 0xC7354B),
                streak: .init(dark: 0xFFBE8E, light: 0xE87565),
                joinAction: .init(dark: 0x72D8BF, light: 0x2E9F87),
                joinActionSecondary: .init(dark: 0x58AD99, light: 0x267F6D)
            )
        case .cherryRibbon:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x210F18, light: 0xFFF0F3),
                backgroundBase: .init(dark: 0x2A121C, light: 0xFFF9FA),
                backgroundRaised: .init(dark: 0x381A24, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x522333, light: 0xFFE1E8),
                surfacePrimary: .init(dark: 0x431E2B, light: 0xFFF0F3),
                surfaceSelected: .init(dark: 0x66263A, light: 0xFFD2DC),
                surfaceBorder: .init(dark: 0xFF9FB4, light: 0xB42042, darkAlpha: 0.28, lightAlpha: 0.24),
                textPrimary: .init(dark: 0xFFF5F7, light: 0x4A1825),
                textSecondary: .init(dark: 0xE8BAC5, light: 0x7F4050),
                textTertiary: .init(dark: 0xBF8594, light: 0xA06574),
                accent: .init(dark: 0xFF6B86, light: 0xC81E43),
                recording: .init(dark: 0xFF6B86, light: 0xC81E43),
                transcribing: .init(dark: 0xFFBE7A, light: 0xD75C31)
            )
        case .lavenderDream:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x171225, light: 0xF3EAF8),
                backgroundBase: .init(dark: 0x20172E, light: 0xFCF8FF),
                backgroundRaised: .init(dark: 0x2B203B, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x3A2B50, light: 0xEDE4F7),
                surfacePrimary: .init(dark: 0x322443, light: 0xF5ECFC),
                surfaceSelected: .init(dark: 0x493060, light: 0xE5D3F6),
                surfaceBorder: .init(dark: 0xD8B4FE, light: 0x7C3FA3, darkAlpha: 0.26, lightAlpha: 0.23),
                textPrimary: .init(dark: 0xFBF5FF, light: 0x352044),
                textSecondary: .init(dark: 0xD5C2E5, light: 0x6F577F),
                textTertiary: .init(dark: 0xA890B9, light: 0x90749F),
                accent: .init(dark: 0xC9A3FF, light: 0x7652B8),
                recording: .init(dark: 0xFF8CB8, light: 0xE94F8A),
                transcribing: .init(dark: 0x80E1FF, light: 0x287FA3)
            )
        case .peachSorbet:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x211411, light: 0xFFEDE4),
                backgroundBase: .init(dark: 0x2B1917, light: 0xFFF9F5),
                backgroundRaised: .init(dark: 0x38211D, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x512E27, light: 0xFFE1D3),
                surfacePrimary: .init(dark: 0x412720, light: 0xFFF0E8),
                surfaceSelected: .init(dark: 0x61382F, light: 0xFFD7C7),
                surfaceBorder: .init(dark: 0xFFAD91, light: 0xB44731, darkAlpha: 0.27, lightAlpha: 0.23),
                textPrimary: .init(dark: 0xFFF7F2, light: 0x49241B),
                textSecondary: .init(dark: 0xE6BCAF, light: 0x7D5046),
                textTertiary: .init(dark: 0xB98B7E, light: 0x9A6E63),
                accent: .init(dark: 0xFF9B7A, light: 0xC94F35),
                recording: .init(dark: 0xFF6B7D, light: 0xC72D4D),
                transcribing: .init(dark: 0xFFD06E, light: 0xC4770F)
            )
        case .mintMacaron:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x10201C, light: 0xF0FAF5),
                backgroundBase: .init(dark: 0x142A24, light: 0xFAFFFC),
                backgroundRaised: .init(dark: 0x1C372F, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x295044, light: 0xDDF3E9),
                surfacePrimary: .init(dark: 0x214037, light: 0xEBF8F2),
                surfaceSelected: .init(dark: 0x2F5B4D, light: 0xCFEBDD),
                surfaceBorder: .init(dark: 0xA7E5C9, light: 0x2E8068, darkAlpha: 0.26, lightAlpha: 0.22),
                textPrimary: .init(dark: 0xF3FFF9, light: 0x173B31),
                textSecondary: .init(dark: 0xB7D9CC, light: 0x507469),
                textTertiary: .init(dark: 0x82A99A, light: 0x6F9588),
                accent: .init(dark: 0xFF9BB9, light: 0xA92F5B),
                recording: .init(dark: 0xFF8FAF, light: 0xB92F5D),
                transcribing: .init(dark: 0xCBA8FF, light: 0x7950B5)
            )
        case .roseQuartz:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x21141C, light: 0xF8EAF0),
                backgroundBase: .init(dark: 0x2B1925, light: 0xFFF9FB),
                backgroundRaised: .init(dark: 0x37212F, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x4B2C3E, light: 0xF4DDE7),
                surfacePrimary: .init(dark: 0x3E2634, light: 0xFBEAF1),
                surfaceSelected: .init(dark: 0x583047, light: 0xF0CADB),
                surfaceBorder: .init(dark: 0xE9A5C3, light: 0x934466, darkAlpha: 0.27, lightAlpha: 0.23),
                textPrimary: .init(dark: 0xFFF5FA, light: 0x432333),
                textSecondary: .init(dark: 0xDEB6C9, light: 0x765465),
                textTertiary: .init(dark: 0xAD8095, light: 0x9B7587),
                accent: .init(dark: 0xFF9CC5, light: 0xA83B6A),
                recording: .init(dark: 0xFF7EAB, light: 0xB52F64),
                transcribing: .init(dark: 0xD4A5FF, light: 0x7848A8)
            )
        case .neonGrid:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x03070D, light: 0xEAFBFF),
                backgroundBase: .init(dark: 0x071019, light: 0xF7FDFF),
                backgroundRaised: .init(dark: 0x0C1723, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x112638, light: 0xDDF6FC),
                surfacePrimary: .init(dark: 0x0F1F2D, light: 0xE4F8FC),
                surfaceSelected: .init(dark: 0x12384A, light: 0xC7F0FA),
                surfaceBorder: .init(dark: 0x36E1FF, light: 0x087F99, darkAlpha: 0.28, lightAlpha: 0.22),
                textPrimary: .init(dark: 0xE9FCFF, light: 0x0B2A33),
                textSecondary: .init(dark: 0x9BC3CE, light: 0x3E6972),
                textTertiary: .init(dark: 0x668B95, light: 0x6B8D94),
                accent: .init(dark: 0x32E3FF, light: 0x08788F),
                transcribing: .init(dark: 0xB77DFF, light: 0x7C3AED)
            )
        case .auroraGlass:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x08111A, light: 0xEAFBF7),
                backgroundBase: .init(dark: 0x0C1720, light: 0xF6FFFD),
                backgroundRaised: .init(dark: 0x12212C, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x183440, light: 0xDDF7F2),
                surfacePrimary: .init(dark: 0x162A35, light: 0xE4F7F3),
                surfaceSelected: .init(dark: 0x17483F, light: 0xC9EEE6),
                surfaceBorder: .init(dark: 0x5EEAD4, light: 0x0F766E, darkAlpha: 0.26, lightAlpha: 0.22),
                textPrimary: .init(dark: 0xEFFFFB, light: 0x12312D),
                textSecondary: .init(dark: 0xA7D3CC, light: 0x476F69),
                textTertiary: .init(dark: 0x719A94, light: 0x6F918B),
                accent: .init(dark: 0x5EEAD4, light: 0x08766E),
                recording: .init(dark: 0xF472B6, light: 0xDB2777),
                transcribing: .init(dark: 0xC084FC, light: 0x7E22CE)
            )
        case .solarFlare:
            MuesliVisualPalette(
                backgroundDeep: .init(dark: 0x120B19, light: 0xFFF3EA),
                backgroundBase: .init(dark: 0x1B1022, light: 0xFFFBF8),
                backgroundRaised: .init(dark: 0x26142D, light: 0xFFFFFF),
                backgroundHover: .init(dark: 0x3A1B3C, light: 0xFFE5D3),
                surfacePrimary: .init(dark: 0x2E1935, light: 0xFFF0E5),
                surfaceSelected: .init(dark: 0x4B2042, light: 0xFFD6C2),
                surfaceBorder: .init(dark: 0xFF8A4C, light: 0xC2410C, darkAlpha: 0.29, lightAlpha: 0.23),
                textPrimary: .init(dark: 0xFFF7EE, light: 0x3B1B25),
                textSecondary: .init(dark: 0xD9B8CB, light: 0x714C57),
                textTertiary: .init(dark: 0xA78396, light: 0x956E79),
                accent: .init(dark: 0xFF9A4D, light: 0xC84A0B),
                recording: .init(dark: 0xFF4F82, light: 0xE11D48),
                transcribing: .init(dark: 0xFF6EE7, light: 0xC026D3)
            )
        }
    }
}

enum MuesliTheme {
    static private(set) var visualTheme: MuesliVisualTheme = .classic
    private static var palette: MuesliVisualPalette { visualTheme.palette }
    static var usesCuteStyling: Bool { visualTheme.usesCuteStyling }

    static func apply(visualTheme rawValue: String?) {
        visualTheme = MuesliVisualTheme.resolved(rawValue)
    }

    static func applicationIconImage(
        for theme: MuesliVisualTheme,
        runtime: RuntimePaths
    ) -> NSImage? {
        guard let url = runtime.applicationIconURL(for: theme) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func applicationIconImage(runtime: RuntimePaths) -> NSImage? {
        applicationIconImage(for: visualTheme, runtime: runtime)
    }

    @MainActor
    @discardableResult
    static func applyApplicationIcon(to application: NSApplication, runtime: RuntimePaths) -> Bool {
        guard let image = applicationIconImage(runtime: runtime) else { return false }
        application.applicationIconImage = image
        application.dockTile.contentView?.needsDisplay = true
        application.dockTile.display()
        return true
    }

    // MARK: - Colors — Backgrounds (layered)

    static let backgroundDeepDarkHex = 0x0B0C0E
    static let backgroundDeepLightHex = 0xF5F5F7
    static var backgroundDeep: Color { palette.backgroundDeep.color }

    /// AppKit counterpart of `backgroundDeep`, for window chrome that cannot use SwiftUI colors.
    static var backgroundDeepNSColor: NSColor { palette.backgroundDeep.nsColor }
    static var backgroundBase: Color { palette.backgroundBase.color }
    static var backgroundRaised: Color { palette.backgroundRaised.color }
    static var backgroundHover: Color { palette.backgroundHover.color }

    // MARK: - Surfaces (interactive elements)

    static var surfacePrimary: Color { palette.surfacePrimary.color }
    static var surfaceSelected: Color { palette.surfaceSelected.color }
    static var surfaceBorder: Color { palette.surfaceBorder.color }

    // MARK: - Text hierarchy

    static var textPrimary: Color { palette.textPrimary.color }
    static var textSecondary: Color { palette.textSecondary.color }
    static var textTertiary: Color { palette.textTertiary.color }

    // MARK: - Accent

    static let defaultAccentDarkHex = 0x6BA3F7
    static let defaultAccentLightHex = 0x2563EB
    static let pinkAccentPresetHex = "ec4899"
    static var strawberryPinkAccent: Color { Color.adaptive(dark: 0xFF8CB8, light: 0xE94F8A) }
    static var strawberryPinkAccentNSColor: NSColor { NSColor.adaptive(dark: 0xFF8CB8, light: 0xE94F8A) }
    static var defaultAccent: Color { palette.accent.color }
    static var accentOverrideHex: String?
    static var accent: Color {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            if hex.lowercased() == visualTheme.preferredAccentHex {
                return defaultAccent
            }
            return Color(hex: Int(val))
        }
        return defaultAccent
    }
    static var accentNSColor: NSColor {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            if hex.lowercased() == visualTheme.preferredAccentHex {
                return palette.accent.nsColor
            }
            return NSColor(hex: Int(val))
        }
        return palette.accent.nsColor
    }
    static var accentSubtle: Color { accent.opacity(0.15) }

    // MARK: - Semantic

    static var recording: Color { palette.recording.color }
    static var transcribing: Color { palette.transcribing.color }
    static var success: Color { palette.success.color }
    static var destructive: Color { palette.destructive.color }
    static var streak: Color { palette.streak.color }

    // MARK: - Navigation

    static var navigationBase: Color {
        visualTheme == .classic ? Color.clear : palette.surfacePrimary.color.opacity(0.74)
    }
    static var navigationTint: Color { visualTheme == .classic ? Color.clear : accent.opacity(usesCuteStyling ? 0.18 : 0.12) }
    static var navigationBorder: Color { visualTheme == .classic ? Color.clear : accent.opacity(usesCuteStyling ? 0.25 : 0.20) }
    static var navigationShadow: Color { visualTheme == .classic ? Color.clear : accent.opacity(usesCuteStyling ? 0.18 : 0.14) }

    // MARK: - Typography (SF Pro / SF Rounded via .system())

    static func title1() -> Font { themedFont(size: 26, weight: .bold) }
    static func title2() -> Font { themedFont(size: 20, weight: .semibold) }
    static func title3() -> Font { themedFont(size: 18, weight: .semibold) }
    static func headline() -> Font { themedFont(size: 15, weight: .semibold) }
    static func body() -> Font { themedFont(size: 14, weight: .regular) }
    static func callout() -> Font { themedFont(size: 13, weight: .regular) }
    static func caption() -> Font { themedFont(size: 12, weight: .regular) }
    static func captionMedium() -> Font { themedFont(size: 12, weight: .medium) }

    private static func themedFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: usesCuteStyling ? .rounded : .default)
    }

    // MARK: - Spacing (4pt grid)

    /// Top padding for page content and for the sidebar header, so a page's heading lines up
    /// with the app name in the sidebar.
    static let pageTop: CGFloat = 8

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner radii

    static var cornerSmall: CGFloat { usesCuteStyling ? 12 : 6 }
    static var cornerMedium: CGFloat { usesCuteStyling ? 17 : 10 }
    static var cornerLarge: CGFloat { usesCuteStyling ? 22 : 14 }
    static var cornerXL: CGFloat { usesCuteStyling ? 28 : 20 }

    static func indicatorTintNSColor(recordingColorHex: String) -> NSColor {
        let normalized = recordingColorHex.replacingOccurrences(of: "#", with: "").lowercased()
        if normalized == visualTheme.preferredAccentHex {
            return palette.accent.nsColor
        }
        if let value = UInt64(normalized, radix: 16) {
            return NSColor(hex: Int(value))
        }
        return accentNSColor
    }

    static var indicatorBaseNSColor: NSColor {
        visualTheme == .classic ? NSColor(hex: 0x1E1E2E) : palette.backgroundRaised.nsColor
    }
    static var indicatorBorderNSColor: NSColor {
        visualTheme == .classic ? NSColor.white.withAlphaComponent(0.16) : palette.surfaceBorder.nsColor
    }
    static var warningNSColor: NSColor {
        visualTheme == .classic ? NSColor(hex: 0xD99A11) : palette.streak.nsColor
    }
    static var transcribingNSColor: NSColor { palette.transcribing.nsColor }
    static var selectedSurfaceNSColor: NSColor {
        visualTheme == .classic ? NSColor(hex: 0x2E3340) : palette.surfaceSelected.nsColor
    }
    static var hoverSurfaceNSColor: NSColor {
        visualTheme == .classic ? NSColor(hex: 0x232528) : palette.backgroundHover.nsColor
    }
    static var textPrimaryNSColor: NSColor {
        visualTheme == .classic ? NSColor.white.withAlphaComponent(0.88) : palette.textPrimary.nsColor
    }

    static func appKitFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard usesCuteStyling,
              let descriptor = font.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return font
        }
        return rounded
    }

    // MARK: - AppKit panels

    /// AppKit notification/prompt tokens preserve the original dark Classic
    /// panel while allowing non-SwiftUI menu-bar surfaces to follow the selected palette.
    static var panelBackgroundNSColor: NSColor {
        visualTheme == .classic
            ? NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.97)
            : palette.backgroundRaised.nsColor.withAlphaComponent(0.97)
    }
    static var panelBorderNSColor: NSColor {
        visualTheme == .classic ? NSColor.white.withAlphaComponent(0.10) : palette.surfaceBorder.nsColor
    }
    static var panelProgressNSColor: NSColor {
        visualTheme == .classic
            ? NSColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 0.8)
            : palette.accent.nsColor.withAlphaComponent(0.8)
    }
    static var panelPrimaryActionNSColor: NSColor {
        visualTheme == .classic
            ? NSColor(red: 0.20, green: 0.50, blue: 1.0, alpha: 1.0)
            : palette.accent.nsColor
    }
    static var panelPrimaryTextNSColor: NSColor {
        visualTheme == .classic ? .white : textPrimaryNSColor
    }
    static var panelSecondaryTextNSColor: NSColor {
        visualTheme == .classic ? NSColor.white.withAlphaComponent(0.55) : palette.textSecondary.nsColor
    }
    static var panelDetailTextNSColor: NSColor {
        visualTheme == .classic ? NSColor.white.withAlphaComponent(0.72) : palette.textSecondary.nsColor
    }
    static var panelDismissBackgroundNSColor: NSColor {
        visualTheme == .classic
            ? NSColor.black.withAlphaComponent(0.70)
            : palette.backgroundDeep.nsColor.withAlphaComponent(0.92)
    }
    static var panelDismissBorderNSColor: NSColor {
        visualTheme == .classic
            ? NSColor.white.withAlphaComponent(0.55)
            : palette.accent.nsColor.withAlphaComponent(0.36)
    }
    static var panelDismissTintNSColor: NSColor {
        visualTheme == .classic
            ? NSColor.white.withAlphaComponent(0.86)
            : textPrimaryNSColor.withAlphaComponent(0.86)
    }
    static var joinActionNSColor: NSColor { palette.joinAction.nsColor }
    static var joinActionSecondaryNSColor: NSColor { palette.joinActionSecondary.nsColor }
    static var panelSecondaryButtonNSColor: NSColor {
        visualTheme == .classic ? NSColor.white.withAlphaComponent(0.12) : palette.backgroundHover.nsColor
    }
}

/// Uses the same theme-owned asset as the running Dock tile. Passing the theme
/// explicitly makes SwiftUI invalidate the brand mark immediately when the
/// stored selection changes, rather than waiting for a process restart.
struct MimoApplicationIconView: View {
    let theme: MuesliVisualTheme
    let size: CGFloat

    init(theme: MuesliVisualTheme, size: CGFloat = 34) {
        self.theme = theme
        self.size = size
    }

    var body: some View {
        Group {
            if theme.usesPackagedIconPreview,
               let runtime = try? RuntimePaths.resolve(),
               let image = MuesliTheme.applicationIconImage(for: theme, runtime: runtime) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: theme.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(theme.previewAccent)
                    .background(theme.previewBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: theme.previewAccent.opacity(0.14), radius: 5, y: 2)
        .accessibilityHidden(true)
        .id(theme.rawValue)
    }
}

// MARK: - Color Helpers

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor.adaptive(dark: dark, light: light))
    }

    static func adaptiveAlpha(dark: NSColor, darkAlpha: CGFloat, light: NSColor, lightAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.withAlphaComponent(darkAlpha)
                : light.withAlphaComponent(lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    static func adaptive(dark: Int, light: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        }
    }
}

struct MuesliBrandThemeAccents: View {
    var body: some View {
        if MuesliTheme.usesCuteStyling {
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .offset(x: 12, y: -12)
                Image(systemName: "heart.fill")
                    .font(.system(size: 8, weight: .bold))
                    .offset(x: -12, y: 12)
            }
            .foregroundStyle(MuesliTheme.accent)
            .accessibilityHidden(true)
            .accessibilityIdentifier("theme.cuteBadge")
        }
    }
}

struct MuesliPrimaryActionThemeAccents: View {
    var body: some View {
        if MuesliTheme.usesCuteStyling {
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                Image(systemName: "sparkles")
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(4)
            .accessibilityHidden(true)
        }
    }
}

private struct MuesliThemeTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.fontDesign(MuesliTheme.usesCuteStyling ? .rounded : nil)
    }
}

extension View {
    /// Applies the selected type design to descendant views, including views
    /// that use their own system font size rather than a MuesliTheme font token.
    func muesliThemeTypography() -> some View {
        modifier(MuesliThemeTypographyModifier())
    }
}

/// Page heading used by every dashboard page, so titles stay identical across tabs.
struct PageTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(MuesliTheme.title1())
            .foregroundStyle(MuesliTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
