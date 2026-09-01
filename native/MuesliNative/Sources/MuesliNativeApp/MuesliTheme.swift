import SwiftUI
import MuesliCore

enum MuesliVisualTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case strawberryMilk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: "Classic"
        case .strawberryMilk: "Strawberry Milk"
        }
    }

    var detail: String {
        switch self {
        case .classic: "Clean, calm, and focused."
        case .strawberryMilk: "Blush pink, creamy, and extra sweet."
        }
    }

    var icon: String {
        switch self {
        case .classic: "waveform"
        case .strawberryMilk: "heart.fill"
        }
    }

    var applicationIconFilename: String {
        switch self {
        case .classic: "muesli.icns"
        case .strawberryMilk: "mimo_strawberry_app_icon.png"
        }
    }

    var previewBackground: Color {
        switch self {
        case .classic: Color(hex: 0xF0F4FA)
        case .strawberryMilk: Color(hex: 0xFFF0F5)
        }
    }

    var previewAccent: Color {
        switch self {
        case .classic: Color(hex: 0x2563EB)
        case .strawberryMilk: Color(hex: 0xE94F8A)
        }
    }

    /// Preview cards use their light palettes even while Settings is in dark mode.
    /// Keeping their matching text colors with the preview tokens prevents the
    /// surrounding active theme from reducing card contrast.
    var previewTextPrimary: Color {
        switch self {
        case .classic: Color(hex: 0x152033)
        case .strawberryMilk: Color(hex: 0x4A2434)
        }
    }

    var previewTextSecondary: Color {
        switch self {
        case .classic: Color.black.opacity(0.58)
        case .strawberryMilk: Color(hex: 0x765465)
        }
    }

    static func resolved(_ rawValue: String?) -> MuesliVisualTheme {
        rawValue.flatMap(MuesliVisualTheme.init(rawValue:)) ?? .classic
    }

    func accentHex(afterSelecting currentAccentHex: String) -> String {
        self == .strawberryMilk ? MuesliTheme.pinkAccentPresetHex : currentAccentHex
    }
}

enum MuesliTheme {
    static private(set) var visualTheme: MuesliVisualTheme = .classic
    static var usesCuteStyling: Bool { visualTheme == .strawberryMilk }

    static func apply(visualTheme rawValue: String?) {
        visualTheme = MuesliVisualTheme.resolved(rawValue)
    }

    static func applicationIconImage(runtime: RuntimePaths) -> NSImage? {
        guard let url = runtime.applicationIconURL(for: visualTheme) else { return nil }
        return NSImage(contentsOf: url)
    }

    @MainActor
    @discardableResult
    static func applyApplicationIcon(to application: NSApplication, runtime: RuntimePaths) -> Bool {
        guard let image = applicationIconImage(runtime: runtime) else { return false }
        application.applicationIconImage = image
        return true
    }

    // MARK: - Colors — Backgrounds (layered)

    static let backgroundDeepDarkHex = 0x0B0C0E
    static let backgroundDeepLightHex = 0xF5F5F7
    static var backgroundDeep: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x21151D, light: 0xF9DFE9)
            : Color.adaptive(dark: backgroundDeepDarkHex, light: backgroundDeepLightHex)
    }

    /// AppKit counterpart of `backgroundDeep`, for window chrome that cannot use SwiftUI colors.
    static var backgroundDeepNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0x21151D, light: 0xF9DFE9)
            : NSColor.adaptive(dark: backgroundDeepDarkHex, light: backgroundDeepLightHex)
    }
    static var backgroundBase: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x2A1923, light: 0xFFF7FA)
            : Color.adaptive(dark: 0x161719, light: 0xFFFFFF)
    }
    static var backgroundRaised: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x36222D, light: 0xFFFDFE)
            : Color.adaptive(dark: 0x1C1D20, light: 0xF0F0F2)
    }
    static var backgroundHover: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x4A2C3B, light: 0xF8D9E6)
            : Color.adaptive(dark: 0x232528, light: 0xE8E8EC)
    }

    // MARK: - Surfaces (interactive elements)

    static var surfacePrimary: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x3B2632, light: 0xFFF0F5)
            : Color.adaptive(dark: 0x262830, light: 0xE5E5EA)
    }
    static var surfaceSelected: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x553044, light: 0xFFD9E8)
            : Color.adaptive(dark: 0x2E3340, light: 0xD6DFFE)
    }
    static var surfaceBorder: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0xFFB3CE, light: 0xB44B72).opacity(0.25)
            : Color.adaptiveAlpha(
                dark: .white, darkAlpha: 0.07,
                light: .black, lightAlpha: 0.08
            )
    }

    // MARK: - Text hierarchy

    static var textPrimary: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0xFFF1F6, light: 0x4A2434)
            : Color.adaptiveAlpha(
                dark: .white, darkAlpha: 0.92,
                light: .black, lightAlpha: 0.88
            )
    }
    static var textSecondary: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0xD8B6C5, light: 0x765465)
            : Color.adaptiveAlpha(
                dark: .white, darkAlpha: 0.62,
                light: .black, lightAlpha: 0.55
            )
    }
    static var textTertiary: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0xAA8295, light: 0xA07E8E)
            : Color.adaptiveAlpha(
                dark: .white, darkAlpha: 0.40,
                light: .black, lightAlpha: 0.33
            )
    }

    // MARK: - Accent

    static let defaultAccentDarkHex = 0x6BA3F7
    static let defaultAccentLightHex = 0x2563EB
    static let pinkAccentPresetHex = "ec4899"
    static var strawberryPinkAccent: Color { Color.adaptive(dark: 0xFF8CB8, light: 0xE94F8A) }
    static var strawberryPinkAccentNSColor: NSColor { NSColor.adaptive(dark: 0xFF8CB8, light: 0xE94F8A) }
    static var defaultAccent: Color {
        usesCuteStyling
            ? strawberryPinkAccent
            : Color.adaptive(dark: defaultAccentDarkHex, light: defaultAccentLightHex)
    }
    static var accentOverrideHex: String?
    static var accent: Color {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            if usesCuteStyling, hex.lowercased() == pinkAccentPresetHex {
                return strawberryPinkAccent
            }
            return Color(hex: Int(val))
        }
        return defaultAccent
    }
    static var accentNSColor: NSColor {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            if usesCuteStyling, hex.lowercased() == pinkAccentPresetHex {
                return strawberryPinkAccentNSColor
            }
            return NSColor(hex: Int(val))
        }
        return usesCuteStyling
            ? strawberryPinkAccentNSColor
            : NSColor.adaptive(dark: defaultAccentDarkHex, light: defaultAccentLightHex)
    }
    static var accentSubtle: Color { accent.opacity(0.15) }

    // MARK: - Semantic

    static var recording: Color { usesCuteStyling ? strawberryPinkAccent : Color(hex: 0xEF4444) }
    static var transcribing: Color {
        usesCuteStyling ? Color.adaptive(dark: 0xD7A0FF, light: 0xA75AC7) : Color(hex: 0xF59E0B)
    }
    static var success: Color {
        usesCuteStyling ? Color.adaptive(dark: 0x72D8BF, light: 0x2E9F87) : Color(hex: 0x34D399)
    }
    static var destructive: Color {
        usesCuteStyling ? Color.adaptive(dark: 0xFF8B96, light: 0xC7354B) : Color.red
    }
    static var streak: Color {
        usesCuteStyling ? Color.adaptive(dark: 0xFFBE8E, light: 0xE87565) : Color.orange
    }

    // MARK: - Navigation

    static var navigationBase: Color {
        usesCuteStyling
            ? Color.adaptive(dark: 0x4B2D3C, light: 0xFFF7FB).opacity(0.74)
            : Color.clear
    }
    static var navigationTint: Color { usesCuteStyling ? strawberryPinkAccent.opacity(0.18) : Color.clear }
    static var navigationBorder: Color { usesCuteStyling ? strawberryPinkAccent.opacity(0.25) : Color.clear }
    static var navigationShadow: Color { usesCuteStyling ? strawberryPinkAccent.opacity(0.18) : Color.clear }

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
        if usesCuteStyling, normalized == pinkAccentPresetHex {
            return strawberryPinkAccentNSColor
        }
        if let value = UInt64(normalized, radix: 16) {
            return NSColor(hex: Int(value))
        }
        return accentNSColor
    }

    static var indicatorBaseNSColor: NSColor {
        usesCuteStyling ? NSColor.adaptive(dark: 0x36222D, light: 0xFFFDFE) : NSColor(hex: 0x1E1E2E)
    }
    static var indicatorBorderNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0xFFB3CE, light: 0xB44B72).withAlphaComponent(0.25)
            : NSColor.white.withAlphaComponent(0.16)
    }
    static var warningNSColor: NSColor {
        usesCuteStyling ? NSColor.adaptive(dark: 0xFFBE8E, light: 0xE87565) : NSColor(hex: 0xD99A11)
    }
    static var transcribingNSColor: NSColor {
        usesCuteStyling ? NSColor.adaptive(dark: 0xD7A0FF, light: 0xA75AC7) : NSColor(hex: 0xF59E0B)
    }
    static var selectedSurfaceNSColor: NSColor {
        usesCuteStyling ? NSColor.adaptive(dark: 0x553044, light: 0xFFD9E8) : NSColor(hex: 0x2E3340)
    }
    static var hoverSurfaceNSColor: NSColor {
        usesCuteStyling ? NSColor.adaptive(dark: 0x4A2C3B, light: 0xF8D9E6) : NSColor(hex: 0x232528)
    }
    static var textPrimaryNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0xFFF1F6, light: 0x4A2434)
            : NSColor.white.withAlphaComponent(0.88)
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
    /// panel while allowing non-SwiftUI menu-bar surfaces to follow Strawberry Milk.
    static var panelBackgroundNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0x36222D, light: 0xFFFDFE).withAlphaComponent(0.97)
            : NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.97)
    }
    static var panelBorderNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0xFFB3CE, light: 0xB44B72).withAlphaComponent(0.25)
            : NSColor.white.withAlphaComponent(0.10)
    }
    static var panelProgressNSColor: NSColor {
        usesCuteStyling
            ? strawberryPinkAccentNSColor.withAlphaComponent(0.8)
            : NSColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 0.8)
    }
    static var panelPrimaryActionNSColor: NSColor {
        usesCuteStyling ? strawberryPinkAccentNSColor : NSColor(red: 0.20, green: 0.50, blue: 1.0, alpha: 1.0)
    }
    static var panelPrimaryTextNSColor: NSColor {
        usesCuteStyling ? textPrimaryNSColor : .white
    }
    static var panelSecondaryTextNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0xD8B6C5, light: 0x765465)
            : NSColor.white.withAlphaComponent(0.55)
    }
    static var panelDetailTextNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0xD8B6C5, light: 0x765465)
            : NSColor.white.withAlphaComponent(0.72)
    }
    static var panelDismissBackgroundNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0x21151D, light: 0xF9DFE9).withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.70)
    }
    static var panelDismissBorderNSColor: NSColor {
        usesCuteStyling ? strawberryPinkAccentNSColor.withAlphaComponent(0.36) : NSColor.white.withAlphaComponent(0.55)
    }
    static var panelDismissTintNSColor: NSColor {
        usesCuteStyling ? textPrimaryNSColor.withAlphaComponent(0.86) : NSColor.white.withAlphaComponent(0.86)
    }
    static var joinActionNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0x72D8BF, light: 0x2E9F87)
            : NSColor(red: 0.20, green: 0.72, blue: 0.53, alpha: 1.0)
    }
    static var joinActionSecondaryNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0x58AD99, light: 0x267F6D)
            : NSColor(red: 0.15, green: 0.58, blue: 0.42, alpha: 1.0)
    }
    static var panelSecondaryButtonNSColor: NSColor {
        usesCuteStyling
            ? NSColor.adaptive(dark: 0x4A2C3B, light: 0xF8D9E6)
            : NSColor.white.withAlphaComponent(0.12)
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
