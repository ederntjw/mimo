import AppKit
import CryptoKit
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

    @Test("Visual themes route to distinct packaged app icons")
    func applicationIconRouting() throws {
        let repoRoot = repositoryRoot()
        let classicURL = repoRoot.appendingPathComponent("assets/muesli.icns")
        let strawberryURL = repoRoot.appendingPathComponent("assets/mimo_strawberry_app_icon.png")
        let runtime = RuntimePaths(
            repoRoot: repoRoot,
            menuIcon: nil,
            appIcon: classicURL,
            bundlePath: nil,
            strawberryAppIcon: strawberryURL
        )

        #expect(MuesliVisualTheme.classic.applicationIconFilename == "muesli.icns")
        #expect(MuesliVisualTheme.strawberryMilk.applicationIconFilename == "mimo_strawberry_app_icon.png")
        #expect(runtime.applicationIconURL(for: .classic) == classicURL)
        #expect(runtime.applicationIconURL(for: .strawberryMilk) == strawberryURL)

        let application = NSApplication.shared
        let originalApplicationIcon = application.applicationIconImage
        defer {
            MuesliTheme.apply(visualTheme: MuesliVisualTheme.classic.rawValue)
            application.applicationIconImage = originalApplicationIcon
        }
        MuesliTheme.apply(visualTheme: MuesliVisualTheme.classic.rawValue)
        let classicImage = try #require(MuesliTheme.applicationIconImage(runtime: runtime))
        #expect(MuesliTheme.applyApplicationIcon(to: application, runtime: runtime))
        let classicDockImage = try #require(application.applicationIconImage?.tiffRepresentation)
        MuesliTheme.apply(visualTheme: MuesliVisualTheme.strawberryMilk.rawValue)
        let strawberryImage = try #require(MuesliTheme.applicationIconImage(runtime: runtime))
        #expect(MuesliTheme.applyApplicationIcon(to: application, runtime: runtime))
        let strawberryDockImage = try #require(application.applicationIconImage?.tiffRepresentation)
        let explicitStrawberryImage = try #require(
            MuesliTheme.applicationIconImage(for: .strawberryMilk, runtime: runtime)
        )

        #expect(classicImage.tiffRepresentation != strawberryImage.tiffRepresentation)
        #expect(classicDockImage != strawberryDockImage)
        #expect(explicitStrawberryImage.tiffRepresentation == strawberryImage.tiffRepresentation)
    }

    @Test("Strawberry Milk icon exactly matches the generated iPhone artwork")
    func strawberryApplicationIconAsset() throws {
        let iconURL = repositoryRoot().appendingPathComponent("assets/mimo_strawberry_app_icon.png")
        let data = try Data(contentsOf: iconURL)
        let representation = try #require(NSBitmapImageRep(data: data))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        #expect(representation.pixelsWide == 1024)
        #expect(representation.pixelsHigh == 1024)
        #expect(!representation.hasAlpha)
        #expect(digest == "b2446487c271c2b954fa1cf5e3acf558d7a039cfe8837d642ae19eadf4b90b17")
        #expect((representation.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) == 1)
        #expect((representation.colorAt(x: 512, y: 512)?.alphaComponent ?? 0) == 1)
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

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
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

            Text("Live Summary · GPT-5.4 Mini · recording continues while you Ask Mimo.")
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)

            HStack {
                Label("Local speech", systemImage: "waveform.and.mic")
                    .foregroundStyle(MuesliTheme.success)
                Spacer()
                Text("Start Live Meeting")
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
