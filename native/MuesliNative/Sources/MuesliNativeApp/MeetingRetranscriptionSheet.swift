import SwiftUI

struct MeetingRetranscriptionSheet: View {
    let modelChoices: [BackendOption]
    let downloadedModels: [BackendOption]
    let isBlocked: Bool
    let onCancel: () -> Void
    let onManageModels: () -> Void
    let onRetranscribe: (BackendOption) -> Void

    @State private var selectedModelID: String

    init(
        downloadedModels: [BackendOption],
        configuredModel: BackendOption,
        isBlocked: Bool,
        onCancel: @escaping () -> Void,
        onManageModels: @escaping () -> Void,
        onRetranscribe: @escaping (BackendOption) -> Void
    ) {
        let choices = MeetingRetranscriptionPolicy.modelChoices(downloaded: downloadedModels)
        self.modelChoices = choices
        self.downloadedModels = downloadedModels
        self.isBlocked = isBlocked
        self.onCancel = onCancel
        self.onManageModels = onManageModels
        self.onRetranscribe = onRetranscribe
        let initial = choices.first { $0 == configuredModel && downloadedModels.contains($0) }
            ?? choices.first { downloadedModels.contains($0) }
            ?? .whisperLargeV3
        _selectedModelID = State(initialValue: Self.modelID(initial))
    }

    private var selectedModel: BackendOption? {
        modelChoices.first { Self.modelID($0) == selectedModelID }
    }

    private var isModelReady: Bool {
        selectedModel.map { downloadedModels.contains($0) } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Text("Re-transcribe Meeting")
                .font(MuesliTheme.title3())
            Text("Choose a model to transcribe the saved recording again. This replaces the transcript and regenerates the summary. Your manual notes and recording are kept.")
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Transcription model", selection: $selectedModelID) {
                ForEach(modelChoices, id: \.model) { model in
                    Text(model.label + (downloadedModels.contains(model) ? "" : " — Download needed"))
                        .tag(Self.modelID(model))
                }
            }
            .accessibilityIdentifier("meeting.retranscriptionModel")

            if let selectedModel {
                Text(selectedModel.description)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Model size: \(selectedModel.sizeLabel)")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            Text("This choice applies only to this re-transcription.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)

            if !isModelReady {
                Text("Download this model in Speech Models, then return to re-transcribe.")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            if isBlocked {
                Text("Re-transcription is available after the active recording or transcription finishes.")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            HStack {
                Button("Speech Models…", action: onManageModels)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Re-transcribe") {
                    guard let selectedModel, isModelReady, !isBlocked else { return }
                    onRetranscribe(selectedModel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isModelReady || isBlocked)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("meeting.confirmRetranscription")
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(width: 520)
        .background(MuesliTheme.backgroundBase)
    }

    private static func modelID(_ model: BackendOption) -> String {
        "\(model.backend):\(model.model)"
    }
}
