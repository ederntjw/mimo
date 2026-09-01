import Foundation
import SwiftUI

enum LiveMeetingAssistantRole: Equatable, Sendable {
    case user
    case assistant
}

struct LiveMeetingAssistantMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: LiveMeetingAssistantRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: LiveMeetingAssistantRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

enum LiveMeetingSummaryPolicy {
    // Keep the first checkpoint visibly live. The delay starts only after a
    // committed speech chunk arrives, so larger values make short meetings
    // appear as though live summarization is not running at all.
    static let initialDelay: TimeInterval = 12
    static let refreshDelay: TimeInterval = 30
    static let minimumTranscriptCharacters = 120
    static let minimumNewCharacters = 160

    static func shouldGenerate(
        transcriptCharacterCount: Int,
        lastSummarizedCharacterCount: Int,
        isGenerating: Bool
    ) -> Bool {
        guard !isGenerating,
              transcriptCharacterCount >= minimumTranscriptCharacters else {
            return false
        }
        if lastSummarizedCharacterCount == 0 {
            return true
        }
        return transcriptCharacterCount - lastSummarizedCharacterCount >= minimumNewCharacters
    }
}

struct LiveMeetingAssistantSection: View {
    let appState: AppState
    let meetingID: Int64
    let controller: MuesliController
    let isActive: Bool

    @State private var question = ""
    @FocusState private var questionFieldFocused: Bool

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: MuesliTheme.spacing12) {
            liveBrief
                .frame(minHeight: 150, idealHeight: 220, maxHeight: 280)

            conversation

            composer
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundBase)
        .onChange(of: isActive) { _, active in
            questionFieldFocused = active
        }
    }

    private var liveBrief: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(MuesliTheme.accent)
                Text("Live Summary")
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Circle()
                    .fill(appState.isMeetingRecordingPaused ? MuesliTheme.textTertiary : MuesliTheme.success)
                    .frame(width: 6, height: 6)
                Text(appState.isMeetingRecordingPaused ? "Recording paused" : "Recording continues")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                Spacer()
                if appState.isLiveMeetingSummaryRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh") {
                    controller.refreshLiveMeetingSummary(meetingID: meetingID)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isLiveMeetingSummaryRefreshing)
            }
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.top, MuesliTheme.spacing16)

            HStack(spacing: MuesliTheme.spacing8) {
                serviceBadge(
                    appState.selectedMeetingTranscriptionBackend.label,
                    systemImage: "waveform.and.mic",
                    tint: MuesliTheme.success
                )
                serviceBadge(
                    appState.isChatGPTAuthenticated
                        ? "ChatGPT · GPT-5.4 Mini"
                        : "ChatGPT sign-in needed · GPT-5.4 Mini",
                    systemImage: "sparkles",
                    tint: MuesliTheme.accent
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MuesliTheme.spacing24)

            if appState.liveMeetingSummary.isEmpty {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Text(appState.isLiveMeetingSummaryRefreshing ? "Reading what has been said so far…" : "Your first rolling summary appears after roughly 10–15 seconds of committed speech.")
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                    Text("You can ask a question at any time; only committed transcript text is used.")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.bottom, MuesliTheme.spacing16)
            } else {
                MeetingNotesView(markdown: appState.liveMeetingSummary)
            }

            if let error = appState.liveMeetingAssistantError, !error.isEmpty {
                Text(error)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.recording)
                    .lineLimit(2)
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.bottom, MuesliTheme.spacing8)
            }
        }
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge, style: .continuous)
                .strokeBorder(MuesliTheme.accent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityIdentifier("meeting.liveSummaryPanel")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    if appState.liveMeetingAssistantMessages.isEmpty {
                        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                            HStack(spacing: MuesliTheme.spacing8) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .foregroundStyle(MuesliTheme.accent)
                                Text("Ask Mimo")
                            }
                                .font(MuesliTheme.headline())
                                .foregroundStyle(MuesliTheme.textPrimary)
                            Text("Try “What did they say about the deadline?” or “Which action items are mine?”")
                                .font(MuesliTheme.body())
                                .foregroundStyle(MuesliTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, MuesliTheme.spacing8)
                    }

                    ForEach(appState.liveMeetingAssistantMessages) { message in
                        messageBubble(message)
                    }

                    if appState.isLiveMeetingAssistantAnswering {
                        HStack(spacing: MuesliTheme.spacing8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Answering from the transcript…")
                                .font(MuesliTheme.body())
                                .foregroundStyle(MuesliTheme.textSecondary)
                        }
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("liveMeetingAssistantBottom")
                }
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.vertical, MuesliTheme.spacing16)
            }
            .onChange(of: appState.liveMeetingAssistantMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: appState.isLiveMeetingAssistantAnswering) { _, _ in
                scrollToBottom(proxy)
            }
        }
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium, style: .continuous)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        }
        .accessibilityIdentifier("meeting.askMimoConversation")
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: MuesliTheme.spacing8) {
            TextField("Ask Mimo about what has already been said…", text: $question)
                .textFieldStyle(.plain)
                .focused($questionFieldFocused)
                .onSubmit(submitQuestion)

            Button(action: submitQuestion) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(trimmedQuestion.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmedQuestion.isEmpty || appState.isLiveMeetingAssistantAnswering)
            .help("Ask about the meeting so far")
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .frame(height: 44)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay {
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        }
        .accessibilityIdentifier("meeting.askMimoComposer")
    }

    private func serviceBadge(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(MuesliTheme.captionMedium())
            .foregroundStyle(tint)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            }
    }

    private func messageBubble(_ message: LiveMeetingAssistantMessage) -> some View {
        HStack(alignment: .bottom, spacing: MuesliTheme.spacing8) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            Text(message.role == .assistant ? MarkdownInlineParser.parse(message.text) : AttributedString(message.text))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(message.role == .user ? MuesliTheme.accent.opacity(0.18) : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay {
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(message.role == .user ? MuesliTheme.accent.opacity(0.25) : MuesliTheme.surfaceBorder, lineWidth: 1)
                }
                .frame(maxWidth: 680, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func submitQuestion() {
        let submitted = trimmedQuestion
        guard !submitted.isEmpty, !appState.isLiveMeetingAssistantAnswering else { return }
        question = ""
        controller.askLiveMeetingAssistant(question: submitted, meetingID: meetingID)
        questionFieldFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("liveMeetingAssistantBottom", anchor: .bottom)
            }
        }
    }
}
