import SwiftUI

@MainActor
struct SnippetsView: View {
    @ObservedObject var store: SpokenSnippetStore
    var usesLiveDictation: Bool = false
    @State private var search = ""
    @State private var editor: SnippetEditorDraft?
    @State private var pendingDeletion: SpokenSnippet?
    @State private var errorMessage: String?

    private var visibleSnippets: [SpokenSnippet] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.snippets.filter {
            query.isEmpty || $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.expansion.localizedCaseInsensitiveContains(query)
        }.sorted { $0.trigger.localizedStandardCompare($1.trigger) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                header
                if let error = store.loadError {
                    loadFailure(error)
                } else if store.snippets.isEmpty {
                    emptyState
                } else {
                    searchField
                    if visibleSnippets.isEmpty {
                        Text("No snippets match your search.")
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .padding(.vertical, MuesliTheme.spacing24)
                    } else {
                        LazyVStack(spacing: MuesliTheme.spacing12) {
                            ForEach(visibleSnippets) { snippet in snippetRow(snippet) }
                        }
                    }
                }
            }
            .padding(.horizontal, MuesliTheme.spacing32)
            .padding(.top, MuesliTheme.pageTop)
            .padding(.bottom, MuesliTheme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MuesliTheme.backgroundBase)
        .sheet(item: $editor) { draft in
            SpokenSnippetEditor(store: store, draft: draft)
        }
        .alert("Delete snippet?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let snippet = pendingDeletion else { return }
                do { try store.delete(id: snippet.id) }
                catch { errorMessage = error.localizedDescription }
                pendingDeletion = nil
            }
        } message: {
            Text("“\(pendingDeletion?.trigger ?? "")” will no longer insert your saved text.")
        }
        .alert("Couldn't save snippets", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack {
                Text("Snippets")
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Spacer()
                Button { editor = SnippetEditorDraft() } label: {
                    Label("Add snippet", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(store.loadError != nil)
            }
            Text("Say a short phrase to insert text you use often.")
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text("Speak the phrase on its own. Your saved text is inserted exactly as written.")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
            if usesLiveDictation {
                Text("While snippets are saved, hands-free dictation inserts text after you stop recording so the whole phrase can be matched.")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MuesliTheme.textTertiary)
            TextField("Search phrases or saved text", text: $search)
                .textFieldStyle(.plain)
                .font(MuesliTheme.body())
                .accessibilityLabel("Search snippets")
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Image(systemName: "text.quote")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(MuesliTheme.textSecondary)
            Text("A few words, a whole message.")
                .font(MuesliTheme.title2())
                .foregroundStyle(MuesliTheme.textPrimary)
            Text("Save an email signature, an address, or a reply you send often. For example, say “my email signature” to insert your sign-off.")
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Create your first snippet") { editor = SnippetEditorDraft() }
                .buttonStyle(.bordered)
        }
        .padding(MuesliTheme.spacing24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
    }

    private func snippetRow(_ snippet: SpokenSnippet) -> some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing16) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(snippet.trigger)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(snippet.expansion)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { editor = SnippetEditorDraft(snippet: snippet) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(snippet.trigger)")
            .help("Edit snippet")
            Button { pendingDeletion = snippet } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(snippet.trigger)")
            .help("Delete snippet")
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay {
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        }
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text("Your snippets couldn't be loaded.").font(MuesliTheme.headline())
            Text(message).font(MuesliTheme.body())
            Button("Retry") { try? store.reload() }
                .buttonStyle(.bordered)
        }
        .foregroundStyle(MuesliTheme.textSecondary)
        .padding(MuesliTheme.spacing24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
    }
}

private struct SnippetEditorDraft: Identifiable {
    let snippet: SpokenSnippet
    let isNew: Bool
    var id: UUID { snippet.id }

    init(snippet: SpokenSnippet? = nil) {
        self.snippet = snippet ?? SpokenSnippet(trigger: "", expansion: "")
        isNew = snippet == nil
    }
}

@MainActor
private struct SpokenSnippetEditor: View {
    @ObservedObject var store: SpokenSnippetStore
    let draft: SnippetEditorDraft
    @Environment(\.dismiss) private var dismiss
    @State private var trigger: String
    @State private var expansion: String
    @State private var errorMessage: String?
    @FocusState private var triggerFocused: Bool

    init(store: SpokenSnippetStore, draft: SnippetEditorDraft) {
        self.store = store
        self.draft = draft
        _trigger = State(initialValue: draft.snippet.trigger)
        _expansion = State(initialValue: draft.snippet.expansion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            Text(draft.isNew ? "New snippet" : "Edit snippet")
                .font(MuesliTheme.title2())
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text("When I say").font(MuesliTheme.headline())
                TextField("my email signature", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .focused($triggerFocused)
                    .accessibilityLabel("Spoken phrase")
                Text("Choose a memorable phrase you'll say on its own.")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text("Insert this text").font(MuesliTheme.headline())
                TextEditor(text: $expansion)
                    .font(MuesliTheme.body())
                    .scrollContentBackground(.hidden)
                    .frame(height: 170)
                    .padding(MuesliTheme.spacing8)
                    .background(MuesliTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay {
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    }
                    .accessibilityLabel("Saved text")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.destructive)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Add snippet" : "Save changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .foregroundStyle(MuesliTheme.textPrimary)
        .padding(MuesliTheme.spacing24)
        .frame(width: 500)
        .background(MuesliTheme.backgroundBase)
        .onAppear { triggerFocused = true }
    }

    private func save() {
        do {
            try store.save(SpokenSnippet(id: draft.snippet.id, trigger: trigger, expansion: expansion))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
