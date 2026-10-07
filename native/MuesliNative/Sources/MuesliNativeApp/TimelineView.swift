import SwiftUI
import MuesliCore

struct TimelineView: View {
    let appState: AppState
    let controller: MuesliController
    @State private var showsFilters = false

    private struct DayGroup: Identifiable {
        let id: Date
        let header: String
        let entries: [TimelineEntry]
    }

    private var groupedEntries: [DayGroup] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var entriesByDay: [Date: [TimelineEntry]] = [:]
        for entry in appState.timelineRows {
            let date = MeetingBrowserLogic.parseDate(entry.timestamp) ?? now
            let day = calendar.startOfDay(for: date)
            entriesByDay[day, default: []].append(entry)
        }
        return entriesByDay.keys.sorted(by: >).map { day in
            let header: String
            if day == today {
                header = "Today"
            } else if day == yesterday {
                header = "Yesterday"
            } else {
                header = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            return DayGroup(id: day, header: header, entries: entriesByDay[day] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardPageHeader(
                title: "Home",
                appState: appState,
                controller: controller
            )
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.top, MuesliTheme.spacing20)
                .padding(.bottom, MuesliTheme.spacing12)

            timelineScrollView
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(appState.config.userName.isEmpty ? "Make room for your thoughts." : "Welcome back, \(appState.config.userName).")
                    .font(MuesliTheme.displayTitle())
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Speak an idea. Capture a conversation. Find it all here.")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MuesliTheme.spacing12) {
                    voiceNoteAction
                    meetingAction
                }
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    voiceNoteAction
                    meetingAction
                }
            }

            Button {
                appState.selectedTab = .shortcuts
            } label: {
                HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
                    Image(systemName: "keyboard")
                    Text(appState.config.resolvedOnboardingUseCase.includesVoiceNotes
                         ? "Hold \(appState.config.dictationHotkey.label), speak, then release to save a voice note."
                         : "To write in another app, hold \(appState.config.dictationHotkey.label), speak, then release.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("View your keyboard shortcuts")
        }
        .padding(MuesliTheme.spacing24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.welcomeSurface)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL))
    }

    private var voiceNoteAction: some View {
        Button {
            controller.toggleVoiceNoteRecording()
        } label: {
            Label(voiceNoteLabel, systemImage: appState.isVoiceNoteRecording ? "stop.fill" : "mic")
                .font(MuesliTheme.callout().weight(.medium))
                .fixedSize()
                .padding(.horizontal, MuesliTheme.spacing16)
                .frame(height: 38)
                .foregroundStyle(MuesliTheme.backgroundBase)
                .background(MuesliTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(appState.isMeetingRecording || appState.isMeetingStarting
                  || (appState.dictationState != .idle && !appState.isVoiceNoteRecording))
        .accessibilityIdentifier("home.recordVoiceNote")
        .help("Record a voice note and save it to your history")
    }

    private var voiceNoteLabel: String {
        if appState.isVoiceNoteRecording { return "Stop voice note" }
        switch appState.dictationState {
        case .idle: return "Record a voice note"
        case .preparing: return "Preparing microphone…"
        case .recording: return "Dictation in progress"
        case .transcribing: return "Transcribing…"
        }
    }

    private var meetingAction: some View {
        Button {
            if appState.isMeetingRecording || appState.isMeetingStarting {
                if let id = appState.liveMeetingTranscriptOwnerID {
                    controller.showMeetingDocument(id: id)
                } else {
                    controller.showMeetingsHome()
                }
            } else {
                controller.startMeetingRecordingFromEntryPoint()
            }
        } label: {
            Label(appState.isMeetingRecording || appState.isMeetingStarting ? "Open live meeting" : "Start a meeting", systemImage: "person.2")
                .font(MuesliTheme.callout().weight(.medium))
                .fixedSize()
                .padding(.horizontal, MuesliTheme.spacing16)
                .frame(height: 38)
                .foregroundStyle(MuesliTheme.textPrimary)
                .background(MuesliTheme.backgroundBase.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(appState.dictationState != .idle && !appState.isMeetingRecording && !appState.isMeetingStarting)
        .accessibilityIdentifier("home.startMeeting")
    }

    private var hasActiveFilters: Bool {
        appState.timelineOriginFilter != .all || appState.timelineApplicationFilter != nil
            || appState.timelineDateFilter != .all
    }

    private var historyHeading: some View {
        HStack {
            Text("Recent activity")
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textPrimary)
            Spacer()
            Button {
                showsFilters.toggle()
            } label: {
                Label(hasActiveFilters ? "Filters applied" : "Filters", systemImage: "line.3.horizontal.decrease")
                    .font(MuesliTheme.captionMedium())
                    .foregroundStyle(hasActiveFilters ? MuesliTheme.accent : MuesliTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(showsFilters || hasActiveFilters ? MuesliTheme.surfacePrimary : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsFilters ? "Hide history filters" : "Show history filters")
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            RecordOriginPicker(selection: Binding(
                get: { appState.timelineOriginFilter },
                set: { controller.filterTimeline(origin: $0) }
            ))
            HStack(spacing: MuesliTheme.spacing12) {
              if !appState.dictationTargetApplications.isEmpty || appState.timelineApplicationFilter != nil {
                TargetApplicationFilterMenu(
                    applications: appState.dictationTargetApplications,
                    selection: appState.timelineApplicationFilter,
                    onSelect: { controller.filterTimeline(application: $0) }
                )
                .featureTourTarget(.timelineApplications)
              }
            Spacer(minLength: 0)
            dateFilterMenu
            }
            if hasActiveFilters {
                Button("Clear filters") {
                    controller.filterTimeline(origin: .all)
                    controller.filterTimeline(application: nil)
                    controller.filterTimeline(dateFilter: .all)
                }
                .buttonStyle(.plain)
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.accent)
            }
        }
    }

    private var dateFilterMenu: some View {
        Menu {
            ForEach(HistoryDateFilter.allCases, id: \.self) { filter in
                Button {
                    controller.filterTimeline(dateFilter: filter)
                } label: {
                    HStack {
                        Text(filter.label)
                        if appState.timelineDateFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                Text(appState.timelineDateFilter == .all ? "All time" : appState.timelineDateFilter.label)
                    .font(MuesliTheme.caption())
            }
            .foregroundStyle(
                appState.timelineDateFilter == .all
                    ? MuesliTheme.textTertiary
                    : MuesliTheme.accent
            )
            .padding(.horizontal, appState.timelineDateFilter == .all ? 0 : 8)
            .padding(.vertical, 3)
            .background(
                appState.timelineDateFilter == .all
                    ? Color.clear
                    : MuesliTheme.accent.opacity(0.12)
            )
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Filter activity by date")
    }

    private var emptyState: some View {
        VStack(spacing: MuesliTheme.spacing12) {
            Image(systemName: hasActiveFilters ? "magnifyingglass" : "waveform")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(emptyStateTitle)
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(hasActiveFilters ? "Try another source, app, or time range." : "Your voice notes, dictations, and meetings will appear here. Start with an idea above.")
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateTitle: String {
        if let application = appState.timelineApplicationFilter {
            return "No dictations for \(application.name)"
        }
        switch appState.timelineOriginFilter {
        case .all: return "No activity yet"
        case .thisMac: return "No activity from this Mac"
        case .fromIPhone: return "No activity from iPhone"
        }
    }

    private var timelineScrollView: some View {
      ScrollViewReader { scrollProxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
                welcomeCard

                StatsHeaderView(
                    dictationStats: appState.dictationStats,
                    meetingStats: appState.meetingStats,
                    showsMeetingStat: true,
                    tracksInsightsFeatureTour: true,
                    horizontalPadding: 0,
                    onSelect: { controller.openInsights(section: $0) }
                )
                .id("home.insights")

                if appState.config.showIOSCompanionPrompt {
                    MimoAccountSyncCard(appState: appState, controller: controller)
                }

                historyHeading
                if showsFilters || hasActiveFilters
                    || appState.activeFeatureTourTarget == .timelineApplications
                    || appState.activeFeatureTourTarget == .timelineFilters {
                    filterBar
                        .id("home.filters")
                }
                if appState.timelineRows.isEmpty {
                    emptyState
                }

                ForEach(groupedEntries) { group in
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                        Text(group.header)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .padding(.leading, MuesliTheme.spacing4)

                        VStack(spacing: 1) {
                            ForEach(group.entries) { entry in
                                timelineRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .scrollTargetLayout()
                        .background(MuesliTheme.surfaceBorder)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                }

                if appState.hasMoreTimelineEntries {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { controller.loadMoreTimelineEntries() }
                }
            }
            .frame(maxWidth: 960)
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.bottom, MuesliTheme.spacing24)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: Binding(
            get: { appState.timelineScrollAnchor },
            set: { appState.timelineScrollAnchor = $0 }
        ), anchor: .top)
        .onChange(of: appState.activeFeatureTourTarget, initial: true) { _, target in
            switch target {
            case .insightsEntry:
                scrollProxy.scrollTo("home.insights", anchor: .top)
            case .timelineApplications, .timelineFilters:
                scrollProxy.scrollTo("home.filters", anchor: .top)
            default:
                break
            }
        }
      }
    }

    @ViewBuilder
    private func timelineRow(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .dictation(let record):
            DictationRowView(
                record: record,
                timeOnly: Self.formatTime(record.timestamp),
                onCopy: { controller.copyToClipboard(record.rawText) },
                onCopyOriginal: record.originalText == nil ? nil : {
                    if let original = record.originalText {
                        controller.copyToClipboard(original)
                    }
                },
                onCopyTrace: record.computerUseTrace == nil ? nil : {
                    controller.copyToClipboard(ComputerUseTraceFormatter.debugText(for: record))
                },
                onDelete: { controller.deleteDictation(id: record.id) }
            )
        case .meeting(let record):
            TimelineMeetingRow(record: record) {
                controller.showTimelineMeetingDocument(id: record.id)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "hh:mm a"
        return formatter
    }()

    fileprivate static func formatTime(_ raw: String) -> String {
        guard let date = MeetingBrowserLogic.parseDate(raw) else {
            return MeetingBrowserLogic.formatStartTime(raw)
        }
        return timeFormatter.string(from: date)
    }
}

private struct TimelineMeetingRow: View {
    let record: MeetingRecord
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var rowWidth: CGFloat = 0

    private var isCompact: Bool { rowWidth < 560 }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if isCompact {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        timestamp
                        meetingContent
                    }
                } else {
                    HStack(alignment: .top, spacing: MuesliTheme.spacing16) {
                        timestamp
                            .frame(width: 64, alignment: .leading)
                            .padding(.top, 2)
                        meetingContent
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MuesliTheme.spacing20)
            .padding(.vertical, MuesliTheme.spacing16)
            .background(isHovered ? MuesliTheme.backgroundHover : MuesliTheme.backgroundBase)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rowWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in
                        rowWidth = width
                    }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open meeting")
    }

    private var timestamp: some View {
        Text(TimelineView.formatTime(record.startTime))
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textSecondary)
    }

    private var meetingContent: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.accent)
                    .accessibilityLabel("Meeting")
                Text(record.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineLimit(isCompact ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MuesliTheme.spacing8) {
                    metadataBadges
                    Spacer(minLength: 0)
                    duration
                }
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    HStack(spacing: MuesliTheme.spacing8) { metadataBadges }
                    duration
                }
            }

            Text(previewText)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var metadataBadges: some View {
        if record.status != .completed {
            Text(record.status.displayLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(record.status.displayColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(record.status.displayColor.opacity(0.12))
                .clipShape(Capsule())
                .fixedSize()
        }
        if let label = SyncOriginDisplay.badgeLabel(forMeetingSource: record.source) {
            SyncOriginBadge(label: label)
                .fixedSize()
        }
    }

    private var duration: some View {
        Text(Self.formatDuration(record.durationSeconds))
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textSecondary)
            .fixedSize()
    }

    private var previewText: String {
        let content: String
        if !record.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           record.status != .completed {
            content = record.manualNotes
        } else if !record.formattedNotes.isEmpty {
            content = record.formattedNotes
        } else {
            content = record.rawTranscript
        }
        let preview = MeetingPreviewText.snippet(from: content)
        return preview.isEmpty ? "No transcript or notes yet" : preview
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 60 {
            let minutes = rounded / 60
            let remainingSeconds = rounded % 60
            return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
        }
        return "\(rounded)s"
    }

}
