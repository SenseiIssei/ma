import SwiftUI

/// Browse the community gallery and add decks to your topics. Meant to be
/// presented as a sheet, for example from the + menu in Learn:
///
///     .sheet(isPresented: $showingGallery) { GalleryView() }
struct GalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var entries: [GalleryEntry] = []
    @State private var query = ""
    /// "en", "de", or "" for every language. Starts with the app language.
    @State private var locale = Loc.code
    /// nil shows every shelf.
    @State private var shelf: DeckCategory?
    @State private var previewing: GalleryEntry?
    @State private var adding: Set<String> = []
    @State private var justAdded: Set<String> = []
    @State private var banner: GalleryBanner?

    private enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    private var store: DeckStore { model.decks }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    filters
                    content
                    webLink
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .navigationTitle(tr("Community gallery", "Community-Galerie"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: tr("Search topics", "Themen suchen"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Fertig")) { dismiss() }
                }
            }
            .refreshable { await load() }
            .task {
                if entries.isEmpty { await load() }
            }
            .sheet(item: $previewing) { entry in
                GalleryPreviewSheet(entry: entry, isAdded: isAdded(entry)) { data in
                    await add(entry, data: data)
                }
            }
            .safeAreaInset(edge: .bottom) { bannerView }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Illustration(name: "IllustrationLearn", height: 150)
            Text(tr("Topics written by people who use Ma. Each one teaches first and practises after, with examples and short notes.",
                    "Themen von Menschen, die Ma nutzen. Jedes erklärt zuerst und übt danach, mit Beispielen und kurzen Notizen."))
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: tr("All", "Alle"), selected: shelf == nil) { shelf = nil }
                    ForEach(presentShelves) { item in
                        Chip(title: item.title, selected: shelf == item) {
                            shelf = shelf == item ? nil : item
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            HStack(spacing: 8) {
                ForEach(localeChoices) { choice in
                    Chip(title: choice.title, selected: locale == choice.code) { locale = choice.code }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .tint(Zen.shu)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        case .failed(let text):
            VStack(spacing: 14) {
                Illustration(name: "IllustrationEmpty", height: 150)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await load() }
                } label: {
                    Label(tr("Try again", "Noch einmal"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.quiet)
            }
            .frame(maxWidth: .infinity)
            .zenCard()
        case .loaded:
            let groups = grouped
            if groups.isEmpty {
                VStack(spacing: 12) {
                    Illustration(name: "IllustrationEmpty", height: 150)
                    Text(tr("No topic matches. Try another word, shelf or language.", "Kein Thema passt. Versuch ein anderes Wort, Regal oder eine andere Sprache."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .zenCard()
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(icon: group.shelf.icon, title: group.shelf.title)
                        ForEach(group.entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var webLink: some View {
        Link(destination: GalleryClient.webURL) {
            Label(tr("Write your own topic for the gallery", "Eigenes Thema für die Galerie schreiben"), systemImage: "square.and.pencil")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Zen.shu)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func row(_ entry: GalleryEntry) -> some View {
        let added = isAdded(entry)
        let busy = adding.contains(entry.path)
        return HStack(alignment: .center, spacing: 12) {
            Button {
                Haptics.tap()
                previewing = entry
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Hanko(text: entry.symbol, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.display(17, weight: .semibold))
                            .foregroundStyle(Zen.ink)
                        if !entry.subtitle.isEmpty {
                            Text(entry.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Zen.inkSoft)
                                .lineLimit(2)
                        }
                        Text(entry.facts)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Zen.inkFaint)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Shows a preview", "Zeigt eine Vorschau"))

            Button {
                Task { await add(entry) }
            } label: {
                Group {
                    if busy {
                        ProgressView().tint(Zen.shu)
                    } else {
                        Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(added ? Zen.matcha : Zen.shu)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(added || busy)
            .accessibilityLabel(added ? tr("\(entry.title) added", "\(entry.title) hinzugefügt") : tr("Add \(entry.title)", "\(entry.title) hinzufügen"))
        }
        .zenCard(padding: 14)
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Label(banner.text, systemImage: banner.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(banner.ok ? Zen.ink : Zen.negative)
                .fixedSize(horizontal: false, vertical: true)
                .zenCard(padding: 14)
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { withAnimation { self.banner = nil } }
        }
    }

    // MARK: Data

    private var filtered: [GalleryEntry] {
        entries.filter { entry in
            (locale.isEmpty || entry.locale == locale)
                && (shelf == nil || entry.shelf == shelf)
                && entry.matches(query)
        }
    }

    private var grouped: [GalleryGroup] {
        let list = filtered
        return DeckCategory.allCases.compactMap { item in
            let inShelf = list
                .filter { $0.shelf == item }
                .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            return inShelf.isEmpty ? nil : GalleryGroup(shelf: item, entries: inShelf)
        }
    }

    private var presentShelves: [DeckCategory] {
        let present = Set(entries.map(\.shelf))
        return DeckCategory.allCases.filter { present.contains($0) }
    }

    private var localeChoices: [GalleryLocaleChoice] {
        let german = GalleryLocaleChoice(code: "de", title: "Deutsch")
        let english = GalleryLocaleChoice(code: "en", title: "English")
        let all = GalleryLocaleChoice(code: "", title: tr("All languages", "Alle Sprachen"))
        return Loc.isGerman ? [german, english, all] : [english, german, all]
    }

    /// Added in this session, or already among the learner's own topics.
    private func isAdded(_ entry: GalleryEntry) -> Bool {
        if justAdded.contains(entry.path) { return true }
        return store.custom.contains { deck in
            (deck.locale ?? "") == entry.locale && (deck.id == entry.deckID || deck.title == entry.title)
        }
    }

    private func load() async {
        if entries.isEmpty { phase = .loading }
        do {
            entries = try await GalleryClient.fetchIndex()
            phase = .loaded
        } catch {
            if entries.isEmpty {
                phase = .failed(GalleryImport.message(for: error))
            } else {
                show(GalleryImport.message(for: error), ok: false)
            }
        }
    }

    private func add(_ entry: GalleryEntry, data: Data? = nil) async {
        guard !adding.contains(entry.path), !isAdded(entry) else { return }
        adding.insert(entry.path)
        defer { adding.remove(entry.path) }
        do {
            let text = try await GalleryImport.add(entry, data: data, into: store)
            justAdded.insert(entry.path)
            Haptics.success()
            show(text, ok: true)
        } catch {
            Haptics.warning()
            show(GalleryImport.message(for: error), ok: false)
        }
    }

    private func show(_ text: String, ok: Bool) {
        let next = GalleryBanner(text: text, ok: ok)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { banner = next }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if banner == next {
                withAnimation { banner = nil }
            }
        }
    }
}

// MARK: - Preview sheet

/// A look inside a gallery deck before adding it: the first cards with
/// their answers and notes.
struct GalleryPreviewSheet: View {
    let entry: GalleryEntry
    let isAdded: Bool
    let onAdd: (Data) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var data: Data?
    @State private var deck: Deck?
    @State private var failure: String?
    @State private var adding = false

    private let shown = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 16) {
                        Hanko(text: entry.symbol, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.display(26))
                                .foregroundStyle(Zen.ink)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Zen.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 8)

                    HStack(spacing: 8) {
                        fact(icon: "rectangle.stack.fill", text: deck.map { tr("\($0.cards.count) cards", "\($0.cards.count) Karten") } ?? entry.cardsText)
                        fact(icon: "globe", text: entry.languageName)
                        fact(icon: entry.shelf.icon, text: entry.shelf.title)
                    }

                    Button {
                        guard let data else { return }
                        adding = true
                        Task {
                            await onAdd(data)
                            adding = false
                            dismiss()
                        }
                    } label: {
                        Label(isAdded ? tr("Already in your topics", "Schon in deinen Themen") : tr("Add to my topics", "Zu meinen Themen hinzufügen"),
                              systemImage: isAdded ? "checkmark" : "plus")
                    }
                    .buttonStyle(.primary)
                    .disabled(isAdded || data == nil || adding)

                    SectionHeader(icon: "sparkles", title: tr("First cards", "Die ersten Karten"))
                    cards

                    Text(tr("Community topics are written by people who use Ma and checked before they go online. Found a mistake? Tell us on GitHub.",
                            "Community-Themen schreiben Menschen, die Ma nutzen, und sie werden geprüft, bevor sie online gehen. Einen Fehler gefunden? Sag es uns auf GitHub."))
                        .font(.system(size: 13))
                        .foregroundStyle(Zen.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Schließen")) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if let deck {
            VStack(spacing: 0) {
                let first = Array(deck.cards.prefix(shown))
                ForEach(first) { card in
                    GalleryCardRow(card: card)
                    if card.id != first.last?.id {
                        Divider().overlay(Zen.line)
                    }
                }
            }
            .zenCard(padding: 6)
            if deck.cards.count > shown {
                Text(tr("and \(deck.cards.count - shown) more", "und \(deck.cards.count - shown) weitere"))
                    .font(.system(size: 13))
                    .foregroundStyle(Zen.inkSoft)
                    .frame(maxWidth: .infinity)
            }
        } else if let failure {
            VStack(spacing: 12) {
                Text(failure)
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    self.failure = nil
                    Task { await load() }
                } label: {
                    Label(tr("Try again", "Noch einmal"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.quiet)
            }
            .frame(maxWidth: .infinity)
            .zenCard()
        } else {
            ProgressView()
                .tint(Zen.shu)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }

    private func fact(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Zen.inkSoft)
            .lineLimit(1)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(Zen.sand, in: Capsule())
    }

    private func load() async {
        guard data == nil else { return }
        do {
            let fetched = try await GalleryClient.fetch(try GalleryClient.deckURL(for: entry))
            let decks = try GalleryClient.decodeDecks(fetched)
            deck = decks.first
            data = fetched
        } catch {
            failure = GalleryImport.message(for: error)
        }
    }
}

// MARK: - Pieces

private struct GalleryCardRow: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.prompt)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.answer)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Zen.matcha)
            if let note = card.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct GalleryGroup: Identifiable {
    let shelf: DeckCategory
    let entries: [GalleryEntry]
    var id: String { shelf.rawValue }
}

private struct GalleryLocaleChoice: Identifiable {
    let code: String
    let title: String
    var id: String { code }
}

private struct GalleryBanner: Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
}
