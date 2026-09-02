import SwiftUI

/// Shared dashboard heading for surfaces that display account-syncable history.
struct DashboardPageHeader: View {
    let title: String
    let appState: AppState
    let controller: MuesliController

    var body: some View {
        HStack(spacing: MuesliTheme.spacing12) {
            PageTitle(title)

            DashboardAccountSyncButton(
                state: appState.mimoAccountState,
                isSyncing: appState.isMimoAccountWorking,
                onSync: { controller.performMimoAccountSync() },
                onOpenSettings: {
                    appState.selectedSettingsPane = .sync
                    controller.openSettingsTab()
                }
            )
        }
    }
}

struct DashboardAccountSyncButton: View {
    let state: MimoAccountState
    let isSyncing: Bool
    let onSync: () -> Void
    let onOpenSettings: () -> Void

    private var tint: Color {
        switch state {
        case .signedIn, .working:
            return MuesliTheme.accent
        case .accountMismatch, .error:
            return MuesliTheme.recording
        case .notConfigured, .signedOut:
            return MuesliTheme.textTertiary
        }
    }

    private var label: String {
        if isSyncing {
            return "Syncing with your Mimo Account"
        }
        switch state {
        case .signedIn:
            return "Sync now"
        case .signedOut:
            return "Sign in to Mimo Account sync"
        case .notConfigured:
            return "Mimo Account sync is not configured"
        case .accountMismatch, .error:
            return "Review Mimo Account sync"
        case .working:
            return "Syncing with your Mimo Account"
        }
    }

    var body: some View {
        Button {
            if state == .signedIn {
                onSync()
            } else {
                onOpenSettings()
            }
        } label: {
            ZStack {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))

                RotatingSyncIcon(
                    systemName: "arrow.triangle.2.circlepath",
                    isAnimating: isSyncing,
                    font: .system(size: 8, weight: .bold)
                )
                    .offset(y: 1)
                    .opacity(state == .working ? 1 : 0)
            }
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(tint.opacity(state == .signedIn || state == .error ? 0.28 : 0.14), lineWidth: 1)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSyncing)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Sync text across devices through your private Mimo Account.")
    }

    private var iconName: String {
        switch state {
        case .signedIn:
            return "person.crop.circle.badge.checkmark"
        case .working:
            return "person.crop.circle"
        case .accountMismatch, .error:
            return "person.crop.circle.badge.exclamationmark"
        case .notConfigured, .signedOut:
            return "person.crop.circle"
        }
    }
}

struct RotatingSyncIcon: View {
    let systemName: String
    let isAnimating: Bool
    let font: Font
    @State private var rotationDegrees = 0.0

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear { updateRotation(animated: false) }
            .onChange(of: isAnimating) { _, _ in updateRotation(animated: true) }
    }

    private func updateRotation(animated: Bool) {
        guard isAnimating else {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) { rotationDegrees = 0 }
            } else {
                rotationDegrees = 0
            }
            return
        }

        rotationDegrees = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotationDegrees = 360
        }
    }
}
