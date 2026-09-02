import SwiftUI
import TelemetryDeck

/// The dashboard entry point for Mimo-owned, cross-platform text sync.
/// Legacy CloudKit remains available in Sync settings for existing libraries,
/// but new dashboard surfaces consistently lead with the Mimo Account contract.
struct MimoAccountSyncCard: View {
    let appState: AppState
    let controller: MuesliController

    @State private var promptSeen = false

    var body: some View {
        HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
            RotatingSyncIcon(
                systemName: iconName,
                isAnimating: appState.isMimoAccountWorking,
                font: .system(size: 18, weight: .semibold)
            )
            .foregroundStyle(iconColor)
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(subtitle)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: MuesliTheme.spacing12)

            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    Text(buttonTitle)
                    Image(systemName: buttonIcon)
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(MuesliTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
            .disabled(appState.isMimoAccountWorking)
            .help(buttonHelp)

            Button {
                controller.updateConfig { $0.showIOSCompanionPrompt = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
            .help("Hide Mimo Account sync prompt")
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay {
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        }
        .onAppear {
            guard !promptSeen else { return }
            promptSeen = true
            TelemetryDeck.signal("mimo_account_prompt_seen", parameters: ["platform": "macos"])
        }
    }

    private var title: String {
        switch appState.mimoAccountState {
        case .notConfigured:
            return "Mimo Account sync needs setup"
        case .signedOut:
            return "Sync across all your devices"
        case .signedIn:
            return appState.mimoAccountEmail.map { "Synced as \($0)" } ?? "Mimo Account sync is on"
        case .working:
            return "Syncing with your Mimo Account"
        case .accountMismatch:
            return "This local library belongs to another account"
        case .error:
            return "Mimo Account sync needs attention"
        }
    }

    private var subtitle: String {
        if let status = appState.mimoAccountStatus,
           appState.mimoAccountState != .signedIn {
            return status
        }
        switch appState.mimoAccountState {
        case .notConfigured:
            return "Local history remains available. Add the Supabase client configuration to enable account sync."
        case .signedOut:
            return "Use one Mimo login on Mac, iPhone, and future Android devices. Audio stays local."
        case .signedIn:
            if let date = appState.mimoAccountLastSyncedAt {
                return "Text synced \(date.formatted(.relative(presentation: .named))). Audio and credentials stay on this device."
            }
            return "Transcripts, notes, and summaries can sync. Audio and credentials stay on this device."
        case .working:
            return "Uploading and downloading text changes without blocking local work."
        case .accountMismatch:
            return "Mimo will not upload this Mac's data into a different account. Open Sync settings to resolve it."
        case .error:
            return "Open Sync settings for details or try again. Local data remains safe on this Mac."
        }
    }

    private var iconName: String {
        switch appState.mimoAccountState {
        case .working:
            return "arrow.triangle.2.circlepath"
        case .signedIn:
            return "checkmark.circle.fill"
        case .accountMismatch, .error:
            return "exclamationmark.triangle.fill"
        case .notConfigured, .signedOut:
            return "person.crop.circle"
        }
    }

    private var iconColor: Color {
        switch appState.mimoAccountState {
        case .signedIn:
            return MuesliTheme.success
        case .accountMismatch, .error:
            return MuesliTheme.recording
        case .notConfigured, .signedOut, .working:
            return MuesliTheme.accent
        }
    }

    private var buttonTitle: String {
        switch appState.mimoAccountState {
        case .signedIn:
            return "Sync now"
        case .working:
            return "Syncing…"
        case .notConfigured:
            return "Sync settings"
        case .signedOut:
            return "Sign in"
        case .accountMismatch, .error:
            return "Review"
        }
    }

    private var buttonIcon: String {
        switch appState.mimoAccountState {
        case .signedIn, .working:
            return "arrow.triangle.2.circlepath"
        case .notConfigured:
            return "gearshape"
        case .signedOut:
            return "person.crop.circle"
        case .accountMismatch, .error:
            return "arrow.right"
        }
    }

    private var buttonHelp: String {
        appState.mimoAccountState == .signedIn
            ? "Sync text changes with your Mimo Account"
            : "Open Mimo Account sync settings"
    }

    private func primaryAction() {
        if appState.mimoAccountState == .signedIn {
            controller.performMimoAccountSync()
        } else {
            appState.selectedSettingsPane = .sync
            controller.openSettingsTab()
        }
    }
}
