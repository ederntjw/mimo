import Foundation
import MuesliCore

struct RuntimePaths {
    let repoRoot: URL
    let menuIcon: URL?
    let appIcon: URL?
    let bundlePath: URL?
    let strawberryAppIcon: URL?

    init(
        repoRoot: URL,
        menuIcon: URL?,
        appIcon: URL?,
        bundlePath: URL?,
        strawberryAppIcon: URL? = nil
    ) {
        self.repoRoot = repoRoot
        self.menuIcon = menuIcon
        self.appIcon = appIcon
        self.bundlePath = bundlePath
        self.strawberryAppIcon = strawberryAppIcon
    }

    func applicationIconURL(for theme: MuesliVisualTheme) -> URL? {
        switch theme {
        case .classic:
            return appIcon
        case .strawberryMilk:
            return strawberryAppIcon ?? appIcon
        }
    }

    static func resolve() throws -> RuntimePaths {
        if let bundleResource = Bundle.main.resourceURL {
            return RuntimePaths(
                repoRoot: bundleResource,
                menuIcon: bundleResource.appendingPathComponent("menu_m_template.png"),
                appIcon: bundleResource.appendingPathComponent(MuesliVisualTheme.classic.applicationIconFilename),
                bundlePath: Bundle.main.bundleURL,
                strawberryAppIcon: bundleResource.appendingPathComponent(
                    MuesliVisualTheme.strawberryMilk.applicationIconFilename
                )
            )
        }

        // Dev fallback: search up for assets
        let fileManager = FileManager.default
        var searchURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = searchURL.appendingPathComponent(
                "assets/\(MuesliVisualTheme.classic.applicationIconFilename)"
            )
            if fileManager.fileExists(atPath: candidate.path) {
                return RuntimePaths(
                    repoRoot: searchURL,
                    menuIcon: searchURL.appendingPathComponent("assets/menu_m_template.png"),
                    appIcon: candidate,
                    bundlePath: nil,
                    strawberryAppIcon: searchURL.appendingPathComponent(
                        "assets/\(MuesliVisualTheme.strawberryMilk.applicationIconFilename)"
                    )
                )
            }
            searchURL.deleteLastPathComponent()
        }

        throw NSError(domain: "MuesliRuntime", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not locate app bundle or repo root.",
        ])
    }
}
