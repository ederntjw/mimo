import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MuesliNativeApp

@Suite("Visual theme", .serialized)
@MainActor
struct VisualThemeTests {
    @Test("Classic is the persisted default and Strawberry Milk keeps its stable raw value")
    func stableValuesAndDefault() {
        #expect(AppConfig().visualTheme == MuesliVisualTheme.classic.rawValue)
        #expect(MuesliVisualTheme.strawberryMilk.rawValue == "strawberryMilk")
        #expect(MuesliVisualTheme.resolved(nil) == .classic)
        #expect(MuesliVisualTheme.resolved("unknown-future-theme") == .classic)
    }

    @Test("Theme selection round-trips through local config JSON")
    func configPersistenceRoundTrip() throws {
        var config = AppConfig()
        config.visualTheme = MuesliVisualTheme.strawberryMilk.rawValue

        let data = try JSONEncoder().encode(config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["visual_theme"] as? String == "strawberryMilk")

        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.visualTheme == "strawberryMilk")
    }

    @Test("Unknown stored themes migrate safely to Classic")
    func unknownStoredValueFallsBackToClassic() throws {
        let data = Data(#"{"visual_theme":"futureTheme"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.visualTheme == MuesliVisualTheme.classic.rawValue)
    }

    @Test("Strawberry Milk selects Pink once and Classic preserves the current accent")
    func accentSelectionPolicy() {
        #expect(
            MuesliVisualTheme.strawberryMilk.accentHex(afterSelecting: "2563eb")
                == MuesliTheme.pinkAccentPresetHex
        )
        #expect(MuesliVisualTheme.classic.accentHex(afterSelecting: "8b5cf6") == "8b5cf6")
    }

    @Test("Live switching updates the rendered theme snapshot without restarting")
    func liveSwitchScreenshotRegression() throws {
        defer {
            MuesliTheme.apply(visualTheme: MuesliVisualTheme.classic.rawValue)
            MuesliTheme.accentOverrideHex = nil
        }

        MuesliTheme.accentOverrideHex = MuesliTheme.pinkAccentPresetHex
        MuesliTheme.apply(visualTheme: MuesliVisualTheme.classic.rawValue)
        let classicSnapshot = try snapshotPNG()

        MuesliTheme.apply(visualTheme: MuesliVisualTheme.strawberryMilk.rawValue)
        let strawberrySnapshot = try snapshotPNG()

        #expect(!classicSnapshot.isEmpty)
        #expect(!strawberrySnapshot.isEmpty)
        #expect(classicSnapshot != strawberrySnapshot)
        #expect(MuesliTheme.cornerSmall == 12)
        #expect(MuesliTheme.cornerMedium == 17)
        #expect(MuesliTheme.cornerLarge == 22)
        #expect(MuesliTheme.cornerXL == 28)

        let lightAppearance = try #require(NSAppearance(named: .aqua))
        var resolvedBackground = NSColor.clear
        lightAppearance.performAsCurrentDrawingAppearance {
            resolvedBackground = MuesliTheme.backgroundDeepNSColor.usingColorSpace(.deviceRGB) ?? .clear
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolvedBackground.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 249.0 / 255.0) < 0.002)
        #expect(abs(green - 223.0 / 255.0) < 0.002)
        #expect(abs(blue - 233.0 / 255.0) < 0.002)
        #expect(abs(alpha - 1) < 0.002)
    }

    private func snapshotPNG() throws -> Data {
        let hostingView = NSHostingView(rootView: VisualThemeSnapshotProbe())
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return try #require(representation.representation(using: .png, properties: [:]))
    }
}

private struct VisualThemeSnapshotProbe: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: "waveform")
                Text("Live meeting")
                    .font(MuesliTheme.title2())
                Spacer()
                MuesliBrandThemeAccents()
            }
            .foregroundStyle(MuesliTheme.textPrimary)

            Text("A rendered regression probe for cards, text, status, and the primary action.")
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)

            HStack {
                Label("Recording", systemImage: "record.circle.fill")
                    .foregroundStyle(MuesliTheme.recording)
                Spacer()
                Text("Ask Mimo")
                    .font(MuesliTheme.captionMedium())
                    .foregroundStyle(.white)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, MuesliTheme.spacing8)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
        }
        .padding(MuesliTheme.spacing20)
        .frame(width: 360, height: 180)
        .background(MuesliTheme.backgroundRaised)
        .overlay {
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .padding(8)
        .background(MuesliTheme.backgroundDeep)
        .muesliThemeTypography()
        .preferredColorScheme(.light)
    }
}
