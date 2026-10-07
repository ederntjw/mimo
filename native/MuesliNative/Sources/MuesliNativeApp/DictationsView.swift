import SwiftUI
import MuesliCore

struct DictationsView: View {
    let appState: AppState
    let controller: MuesliController
    @State private var selectedFilter: HistoryDateFilter = .all

    private var groupedDictations: [(id: Date, header: String, records: [DictationRecord])] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let dateHeaderFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEE, d MMM"
            return f
        }()

        var groups: [(key: Date, header: String, records: [DictationRecord])] = []
        var currentDayStart: Date?
        var currentRecords: [DictationRecord] = []
        var currentHeader = ""

        for record in appState.dictationRows {
            let date = parseDate(record.timestamp) ?? now
            let dayStart = calendar.startOfDay(for: date)

            if dayStart != currentDayStart {
                if !currentRecords.isEmpty, let key = currentDayStart {
                    groups.append((key: key, header: currentHeader, records: currentRecords))
                }
                currentDayStart = dayStart
                currentRecords = []

                if dayStart == today {
                    currentHeader = "Today"
                } else if dayStart == yesterday {
                    currentHeader = "Yesterday"
                } else {
                    currentHeader = dateHeaderFormatter.string(from: date)
                }
            }
            currentRecords.append(record)
        }
        if !currentRecords.isEmpty, let key = currentDayStart {
            groups.append((key: key, header: currentHeader, records: currentRecords))
        }

        return groups.map { (id: $0.key, header: $0.header, records: $0.records) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                DashboardPageHeader(
                    title: "Dictations",
                    appState: appState,
                    controller: controller
                )
                Text("Find, copy, and revisit everything you’ve dictated.")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.top, MuesliTheme.pageTop)

            StatsHeaderView(
                dictationStats: appState.filteredDictationStats,
                meetingStats: appState.meetingStats,
                showsMeetingStat: false,
                onSelect: { controller.openInsights(section: $0) }
            )

            if appState.config.showIOSCompanionPrompt {
                MimoAccountSyncCard(appState: appState, controller: controller)
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.bottom, MuesliTheme.spacing12)
            }

            if appState.config.resolvedOnboardingUseCase.includesVoiceNotes {
                HStack {
                    Spacer()
                    voiceNoteButton
                }
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.bottom, MuesliTheme.spacing12)
            }

            dictationFilterBar
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.bottom, MuesliTheme.spacing12)

            if appState.dictationRows.isEmpty {
                Spacer()
                VStack(spacing: MuesliTheme.spacing16) {
                    Image(systemName: hasActiveFilters ? "magnifyingglass" : "waveform")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                        .frame(width: 64, height: 64)
                        .background(MuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
                    Text(emptyStateTitle)
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(emptyStateInstruction)
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 360)
                    if !hasActiveFilters {
                        Label(appState.config.dictationHotkey.label, systemImage: "keyboard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .padding(.horizontal, MuesliTheme.spacing12)
                            .padding(.vertical, MuesliTheme.spacing8)
                            .background(MuesliTheme.backgroundRaised)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                            .overlay {
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                            }
                            .accessibilityLabel("Dictation shortcut: \(appState.config.dictationHotkey.label)")
                    }
                }
                .padding(MuesliTheme.spacing24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
                        ForEach(groupedDictations, id: \.id) { group in
                            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                                HStack {
                                    Text(group.header)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(MuesliTheme.textSecondary)
                                        .padding(.leading, MuesliTheme.spacing4)
                                }

                                VStack(spacing: 1) {
                                    ForEach(group.records) { record in
                                        DictationRowView(
                                            record: record,
                                            timeOnly: formatTimeOnly(record.timestamp),
                                            onCopy: {
                                                controller.copyToClipboard(record.rawText)
                                            },
                                            onCopyOriginal: record.originalText == nil ? nil : {
                                                if let original = record.originalText {
                                                    controller.copyToClipboard(original)
                                                }
                                            },
                                            onCopyTrace: record.computerUseTrace == nil ? nil : {
                                                controller.copyToClipboard(ComputerUseTraceFormatter.debugText(for: record))
                                            },
                                            onDelete: {
                                                controller.deleteDictation(id: record.id)
                                            }
                                        )
                                        .contextMenu {
                                            Button {
                                                controller.copyToClipboard(record.rawText)
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                            if record.computerUseTrace != nil {
                                                Button {
                                                    controller.copyToClipboard(ComputerUseTraceFormatter.debugText(for: record))
                                                } label: {
                                                    Label("Copy action details", systemImage: "list.bullet.clipboard")
                                                }
                                            }
                                        }
                                    }
                                }
                                .background(MuesliTheme.surfaceBorder.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                                )
                            }
                        }

                        // Infinite scroll trigger
                        if appState.hasMoreDictations {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    controller.loadMoreDictations()
                                }
                        }
                    }
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.bottom, MuesliTheme.spacing24)
                }
            }
        }
    }

    private var hasActiveFilters: Bool {
        appState.dictationOriginFilter != .all
            || selectedFilter != .all
            || appState.dictationApplicationFilter != nil
    }

    private var emptyStateInstruction: String {
        if hasActiveFilters {
            return "Try a different device, app, or time range to find your words."
        }
        return appState.config.resolvedOnboardingUseCase.includesVoiceNotes
            ? "Record a voice note, or hold the shortcut below, speak, and release to save your words here."
            : "Click a text field in any app, hold the shortcut below, and speak. Your words will appear here."
    }

    private var emptyStateTitle: String {
        if let application = appState.dictationApplicationFilter {
            return "No dictations for \(application.name)"
        }
        switch appState.dictationOriginFilter {
        case .all: return selectedFilter == .all ? "Your words, all in one place" : "No dictations in this time range"
        case .thisMac: return "No dictations from this Mac"
        case .fromIPhone: return "No dictations from iPhone"
        }
    }

    private var dictationFilterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MuesliTheme.spacing12) {
                originPicker
                applicationFilter
                Spacer(minLength: 0)
                dateFilterButton
            }
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                originPicker
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MuesliTheme.spacing12) {
                        applicationFilter
                        Spacer(minLength: 0)
                        dateFilterButton
                    }
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                        applicationFilter
                        dateFilterButton
                    }
                }
            }
        }
    }

    private var originPicker: some View {
        RecordOriginPicker(selection: Binding(
            get: { appState.dictationOriginFilter },
            set: { controller.filterDictations(origin: $0) }
        ))
    }

    @ViewBuilder
    private var applicationFilter: some View {
        if !appState.dictationTargetApplications.isEmpty || appState.dictationApplicationFilter != nil {
            TargetApplicationFilterMenu(
                applications: appState.dictationTargetApplications,
                selection: appState.dictationApplicationFilter,
                onSelect: { controller.filterDictations(application: $0) }
            )
        }
    }

    private var voiceNoteButton: some View {
        let isRecording = appState.isVoiceNoteRecording
        return Button {
            controller.toggleVoiceNoteRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isRecording ? "Stop Voice Note" : "Record Voice Note")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing16)
            .frame(height: 36)
            .background(isRecording ? MuesliTheme.recording : MuesliTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(alignment: .topTrailing) {
                MuesliPrimaryActionThemeAccents()
                    .offset(x: 5, y: -5)
            }
        }
        .buttonStyle(.plain)
        .disabled(appState.dictationState == .transcribing)
        .opacity(appState.dictationState == .transcribing ? 0.55 : 1)
    }

    @ViewBuilder
    private var dateFilterButton: some View {
        Menu {
            ForEach(availableFilters, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                    applyFilter(filter)
                } label: {
                    HStack {
                        Text(filter.label)
                        if selectedFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                Text(selectedFilter.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selectedFilter != .all ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(selectedFilter != .all ? MuesliTheme.accentSubtle : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter dictations by time range")
        .accessibilityLabel("Time range")
        .accessibilityValue(selectedFilter.label)
    }

    /// Build filter options dynamically based on the date range of actual data.
    private var availableFilters: [HistoryDateFilter] {
        var filters: [HistoryDateFilter] = [.all]
        let calendar = Calendar.current
        let now = Date()

        // Check oldest dictation to determine which filters make sense
        let oldestDate: Date? = appState.dictationRows.last.flatMap { parseDate($0.timestamp) }
            ?? appState.dictationRows.first.flatMap { parseDate($0.timestamp) }

        guard let oldest = oldestDate else { return filters }
        let daysSinceOldest = calendar.dateComponents([.day], from: oldest, to: now).day ?? 0

        // Always show "Last 2 days" if data spans more than today
        if daysSinceOldest >= 1 { filters.append(.last2Days) }
        if daysSinceOldest >= 3 { filters.append(.lastWeek) }
        if daysSinceOldest >= 8 { filters.append(.last2Weeks) }
        if daysSinceOldest >= 15 { filters.append(.lastMonth) }
        if daysSinceOldest >= 31 { filters.append(.last3Months) }

        return filters
    }

    private func applyFilter(_ filter: HistoryDateFilter) {
        if filter == .all {
            controller.clearDictationFilter()
        } else {
            controller.filterDictations(from: filter.fromDate(), to: nil)
        }
    }

    // MARK: - Date parsing

    private static let parsers: [DateFormatterProtocol] = {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        let local1: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            return f
        }()
        let local2: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
        return [iso1, iso2, local1, local2]
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "hh:mm a"
        return f
    }()

    private func parseDate(_ raw: String) -> Date? {
        for parser in Self.parsers {
            if let date = parser.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private func formatTimeOnly(_ raw: String) -> String {
        guard let date = parseDate(raw) else {
            let clean = raw.replacingOccurrences(of: "T", with: " ")
            return clean.count > 5 ? String(clean.suffix(8).prefix(5)) : clean
        }
        return Self.timeFormatter.string(from: date)
    }
}

private protocol DateFormatterProtocol {
    func date(from string: String) -> Date?
}

extension DateFormatter: DateFormatterProtocol {}
extension ISO8601DateFormatter: DateFormatterProtocol {}
