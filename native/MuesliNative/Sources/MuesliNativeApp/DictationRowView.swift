import SwiftUI
import MuesliCore

struct DictationRowView: View {
    let record: DictationRecord
    let timeOnly: String
    let onCopy: () -> Void
    var onCopyOriginal: (() -> Void)? = nil
    var onCopyTrace: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showDeleteConfirmation = false
    @State private var isExpanded = false
    @State private var showsOriginal = false
    @State private var copyFeedbackToken: UUID?
    @State private var originalCopyFeedbackToken: UUID?
    @State private var rowWidth: CGFloat = 0

    private var didCopy: Bool { copyFeedbackToken != nil }

    private var originalText: String? {
        guard let original = record.originalText,
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              original != record.rawText else { return nil }
        return original
    }

    private var isComputerUseCommand: Bool {
        record.source == "cua"
    }

    private var isQuilTransformation: Bool {
        record.source == "quil"
    }

    private var hasExpandableDetails: Bool {
        record.computerUseTrace != nil
    }

    private var syncOriginBadgeLabel: String? {
        SyncOriginDisplay.badgeLabel(forDictationSource: record.source)
    }

    var body: some View {
        Group {
            if rowWidth >= 560 {
                HStack(alignment: .top, spacing: MuesliTheme.spacing16) {
                    timestamp
                        .frame(width: 64, alignment: .leading)
                        .padding(.top, 5)
                    transcriptContent
                    targetApplicationIcon
                    rowActions
                }
            } else {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        timestamp
                        Spacer(minLength: 0)
                        targetApplicationIcon
                    }
                    transcriptContent
                    HStack {
                        Spacer(minLength: 0)
                        rowActions
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MuesliTheme.spacing20)
        .padding(.vertical, MuesliTheme.spacing16)
        .background(isHovered ? MuesliTheme.backgroundHover : MuesliTheme.backgroundBase)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rowWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in
                        rowWidth = width
                    }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if hasExpandableDetails {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } else {
                copyDictation()
            }
        }
        .task(id: copyFeedbackToken) {
            guard copyFeedbackToken != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                copyFeedbackToken = nil
            }
        }
        .task(id: originalCopyFeedbackToken) {
            guard originalCopyFeedbackToken != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                originalCopyFeedbackToken = nil
            }
        }
        .alert("Delete Dictation", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this dictation? This cannot be undone.")
        }
    }

    private var timestamp: some View {
        Text(timeOnly)
            .font(MuesliTheme.captionMedium())
            .foregroundStyle(MuesliTheme.textSecondary)
    }

    @ViewBuilder
    private var targetApplicationIcon: some View {
        if let targetAppName = record.targetAppName {
            TargetApplicationIconView(
                appName: targetAppName,
                bundleIdentifier: record.targetAppBundleID
            )
        }
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            if isComputerUseCommand || isQuilTransformation || syncOriginBadgeLabel != nil || record.computerUseTrace != nil {
                HStack(spacing: MuesliTheme.spacing8) {
                    if isComputerUseCommand {
                        Text("Action")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MuesliTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MuesliTheme.accentSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if isQuilTransformation {
                        HStack(spacing: 3) {
                            Image(nsImage: QuillIcon.image())
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 10, height: 10)
                            Text("Quill")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if let syncOriginBadgeLabel {
                        SyncOriginBadge(label: syncOriginBadgeLabel)
                    }

                    if let trace = record.computerUseTrace, !isQuilTransformation {
                        Text(Self.displayFinalStatus(trace.finalStatus))
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(statusColor(trace.finalStatus))
                    }
                }
            }

            Text(record.rawText)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineSpacing(4)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let originalText {
                originalDictationDisclosure(originalText)
            }

            if isExpanded, let trace = record.computerUseTrace {
                computerUseTraceView(trace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func originalDictationDisclosure(_ original: String) -> some View {
        DisclosureGroup(isExpanded: $showsOriginal) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                Text(original)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let onCopyOriginal {
                    Button {
                        onCopyOriginal()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            originalCopyFeedbackToken = UUID()
                        }
                    } label: {
                        Label(originalCopyFeedbackToken == nil ? "Copy original" : "Copied",
                              systemImage: originalCopyFeedbackToken == nil ? "doc.on.doc" : "checkmark")
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(originalCopyFeedbackToken == nil ? MuesliTheme.textPrimary : MuesliTheme.accent)
                            .padding(.horizontal, MuesliTheme.spacing12)
                            .frame(height: 28)
                            .background(MuesliTheme.surfacePrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)
                    .help("Copy the saved speech text before cleanup or snippet expansion")
                    .accessibilityLabel(originalCopyFeedbackToken == nil ? "Copy original dictation" : "Original dictation copied")
                }
            }
            .padding(MuesliTheme.spacing12)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .padding(.top, MuesliTheme.spacing8)
            .onTapGesture { }
        } label: {
            Text("Original dictation")
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .tint(MuesliTheme.textSecondary)
    }

    private var rowActions: some View {
        HStack(spacing: 4) {
            if hasExpandableDetails {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show details")
                .accessibilityLabel(isExpanded ? "Hide details" : "Show details")
            }

            if !isQuilTransformation, record.computerUseTrace != nil, let onCopyTrace {
                Button(action: onCopyTrace) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy action details")
                .accessibilityLabel("Copy action details")
            }

            Button(action: copyDictation) {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(didCopy ? MuesliTheme.accent : MuesliTheme.textSecondary)
                    .frame(width: 68, height: 28)
                    .background(didCopy ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy dictation to clipboard")
            .accessibilityLabel(didCopy ? "Dictation copied" : "Copy dictation")

            if onDelete != nil {
                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(isHovered ? MuesliTheme.destructive : MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete dictation")
                .accessibilityLabel("Delete dictation")
            }
        }
        .fixedSize()
    }

    private func copyDictation() {
        onCopy()
        withAnimation(.easeInOut(duration: 0.15)) {
            copyFeedbackToken = UUID()
        }
    }

    @ViewBuilder
    private func computerUseTraceView(_ trace: ComputerUseTraceRecord) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                ForEach(trace.events) { event in
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        HStack(spacing: MuesliTheme.spacing8) {
                            if !isQuilTransformation {
                                Text(event.step.map { "Step \($0)" } ?? "Run")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(MuesliTheme.textTertiary)
                                    .frame(width: 48, alignment: .leading)
                            }

                            Text(event.title)
                                .font(MuesliTheme.captionMedium())
                                .foregroundStyle(MuesliTheme.textSecondary)

                            if let status = ComputerUseTraceFormatter.displayStatus(for: event) {
                                Text(status)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(statusColor(status))
                            }
                        }

                        Text(event.body)
                            .font(.system(
                                size: 12,
                                weight: .regular,
                                design: ["model_output", "quil_model"].contains(event.kind) ? .monospaced : .default
                            ))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, isQuilTransformation ? 0 : 56)
                    }
                }
            }
        }
        .padding(.top, MuesliTheme.spacing4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "done", "executed":
            return MuesliTheme.success
        case "confirm", "needsconfirmation":
            return MuesliTheme.transcribing
        case "timed_out", "timedout":
            return MuesliTheme.transcribing
        case "failed", "unsupported":
            return MuesliTheme.recording
        default:
            return MuesliTheme.textTertiary
        }
    }

    private static func displayFinalStatus(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done":
            return "Done"
        case "timed_out", "timedout":
            return "Timed out"
        case "failed", "fail":
            return "Failed"
        case "confirm", "needsconfirmation", "needs_confirmation":
            return "Confirm"
        case "cancelled", "canceled":
            return "Cancelled"
        default:
            return status.capitalized
        }
    }
}
