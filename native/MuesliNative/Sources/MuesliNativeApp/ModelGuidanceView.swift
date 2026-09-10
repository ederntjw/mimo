import SwiftUI

/// Shared by the model library and the selected-model controls in Settings.
struct SpeechModelGuidanceView: View {
    let option: BackendOption
    var isDownloaded = false
    var hardware: LocalModelHardwareSnapshot?
    var showsLanguageDetails = true

    var body: some View {
        let guidance = option.speechGuidance
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            if showsLanguageDetails {
                SpeechModelLanguageView(option: option)
            }
            ModelGuidanceRow(title: "Best for", detail: guidance.bestFor)
            if !guidance.limitation.isEmpty {
                Text(guidance.limitation)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LocalModelRequirementsView(
                modelID: option.model,
                isDownloaded: isDownloaded,
                hardware: hardware,
                showsStrengths: false
            )
        }
    }
}

struct SpeechModelLanguageView: View {
    let option: BackendOption

    var body: some View {
        let guidance = option.speechGuidance
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            ModelGuidanceRow(title: "Languages", detail: guidance.languageSummary)
            if guidance.languages.count > 8 {
                DisclosureGroup("Show all \(guidance.languages.count) languages") {
                    Text(guidance.languages.joined(separator: ", "))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(MuesliTheme.caption())
                .tint(MuesliTheme.accent)
            } else if guidance.languages.count > 1,
                      !guidance.languages.allSatisfy({ guidance.languageSummary.localizedCaseInsensitiveContains($0) }) {
                Text(guidance.languages.joined(separator: ", "))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ModelGuidanceRow(title: "Mixing languages", detail: guidance.switchingSummary)
        }
    }
}

struct LocalModelRequirementsView: View {
    let modelID: String
    var isDownloaded = false
    var hardware: LocalModelHardwareSnapshot?
    var showsStrengths = true
    @State private var detectedHardware: LocalModelHardwareSnapshot?

    var body: some View {
        Group {
            if let guidance = LocalModelHardware.guidance(forModelID: modelID) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Divider().background(MuesliTheme.surfaceBorder)
                    if showsStrengths {
                        ModelGuidanceRow(title: "Best for", detail: guidance.strengths)
                    }
                    ModelGuidanceRow(
                        title: "Download",
                        detail: guidance.isBundled ? "Included with Mimo" : guidance.downloadBytes.map(Self.diskSize) ?? "Managed by macOS"
                    )
                    ModelGuidanceRow(
                        title: "Mac requirements",
                        detail: "macOS \(guidance.minimumMacOSVersionLabel) or later" + (guidance.requiresAppleSilicon ? " · Apple silicon (M1 or later)" : "")
                    )
                    ModelGuidanceRow(
                        title: "Total Mac RAM",
                        detail: "\(guidance.minimumMemoryGB) GB suggested minimum · \(guidance.recommendedMemoryGB) GB recommended"
                    )
                    ModelGuidanceRow(
                        title: "Model RAM use",
                        detail: "About \(guidance.estimatedWorkingMemoryGB.lowerBound.formatted(.number.precision(.fractionLength(0...1))))–\(guidance.estimatedWorkingMemoryGB.upperBound.formatted(.number.precision(.fractionLength(0...1)))) GB while running"
                    )
                    ModelGuidanceRow(
                        title: "Free disk needed",
                        detail: Self.diskSize(isDownloaded || guidance.isBundled ? guidance.minimumFreeDiskBytesWhenDownloaded : guidance.minimumFreeDiskBytes)
                    )
                    if let snapshot = hardware ?? detectedHardware {
                        let assessment = guidance.suitability(on: snapshot, isDownloaded: isDownloaded)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(assessment.label, systemImage: assessment.level == .recommended ? "checkmark.circle" : "info.circle")
                                .font(MuesliTheme.captionMedium())
                                .foregroundStyle(assessment.level == .recommended ? MuesliTheme.success : MuesliTheme.textSecondary)
                            Text(assessment.detail)
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Memory requirements are Mimo estimates for the whole Mac, including macOS and other apps. They are separate from download size.")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsStrengths, !guidance.limitations.isEmpty {
                        Text(guidance.limitations)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .task {
            if hardware == nil, detectedHardware == nil {
                detectedHardware = LocalModelHardwareSnapshot.current()
            }
        }
    }

    static func diskSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
}

struct ModelGuidanceDisclosure: View {
    let option: BackendOption
    let isActive: Bool
    let isDownloaded: Bool
    var hardware: LocalModelHardwareSnapshot?
    var isCleanup = false
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                if isCleanup {
                    LocalModelRequirementsView(modelID: option.model, isDownloaded: isDownloaded, hardware: hardware)
                } else {
                    SpeechModelGuidanceView(option: option, isDownloaded: isDownloaded, hardware: hardware, showsLanguageDetails: false)
                }
            }
            .padding(.top, MuesliTheme.spacing8)
        } label: {
            Text("Strengths & Mac requirements")
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .tint(MuesliTheme.accent)
        .onAppear { isExpanded = isActive }
        .onChange(of: isActive) { _, active in
            if active { isExpanded = true }
        }
    }
}

struct LocalModelRequirementsDisclosure: View {
    let modelID: String
    let isActive: Bool
    let isDownloaded: Bool
    var hardware: LocalModelHardwareSnapshot?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LocalModelRequirementsView(modelID: modelID, isDownloaded: isDownloaded, hardware: hardware)
                .padding(.top, MuesliTheme.spacing8)
        } label: {
            Text("Strengths & Mac requirements")
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .tint(MuesliTheme.accent)
        .onAppear { isExpanded = isActive }
        .onChange(of: isActive) { _, active in
            if active { isExpanded = true }
        }
    }
}

struct ModelGuidanceRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(detail)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
