import SwiftUI

/// "Make more cards like these": ten new cards in the style of one of your
/// own decks. Shown as a preview first, added only on confirmation.
struct MoreCardsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deckID: String

    private enum Phase: Equatable {
        case idle
        case working
        case failed(String)
        case preview
    }

    @State private var phase: Phase = .idle
    @State private var cards: [Card] = []
    @State private var job: Task<Void, Never>?
    @State private var status: MaAI.Status = .ready

    private var deck: Deck? { model.decks.deck(id: deckID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    if !status.isReady {
                        AIUnavailableNote(status: status)
                    }
                    content
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .navigationTitle(tr("More cards", "Mehr Karten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) {
                        job?.cancel()
                        dismiss()
                    }
                }
                if phase == .preview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Add", "Hinzufügen"), action: add)
                            .fontWeight(.semibold)
                            .disabled(cards.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(phase == .working || phase == .preview)
        }
        .onAppear { status = MaAI.status }
        .onDisappear { job?.cancel() }
    }

    private var intro: some View {
        let title = deck?.title ?? ""
        return HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: "sparkles", tint: Zen.ai, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Ten more for \(title)", "Zehn weitere für \(title)"))
                    .displayFont(19, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("Apple Intelligence looks at your cards and writes new ones in the same style, without repeating a question.",
                        "Apple Intelligence schaut sich deine Karten an und schreibt neue im selben Stil, ohne eine Frage zu wiederholen."))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                AIPrivacyLabel()
                    .padding(.top, 2)
            }
        }
        .zenCard()
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .failed:
            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.circle")
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Zen.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Button(action: write) {
                Label(tr("Write 10 cards", "10 Karten schreiben"), systemImage: "sparkles")
            }
            .buttonStyle(.primary)
            .disabled(!status.isReady || deck == nil)
            .opacity(status.isReady ? 1 : 0.4)
        case .working:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Zen.ai)
                    Text(tr("Writing ten new cards…", "Zehn neue Karten entstehen…"))
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Zen.ink)
                }
                Button(tr("Stop", "Anhalten")) {
                    job?.cancel()
                }
                .buttonStyle(.quiet)
            }
            .zenCard()
        case .preview:
            AICardPreviewList(cards: $cards)
            Button(action: add) {
                Label(tr("Add \(cards.count) cards", "\(cards.count) Karten hinzufügen"), systemImage: "plus")
            }
            .buttonStyle(.primary)
            .disabled(cards.isEmpty)
            .opacity(cards.isEmpty ? 0.4 : 1)
            Button(tr("Try other cards", "Andere Karten versuchen"), action: write)
                .buttonStyle(.quiet)
        }
    }

    private func write() {
        status = MaAI.status
        guard status.isReady, let source = deck else { return }
        phase = .working
        cards = []
        Haptics.tap()
        job = Task {
            defer { job = nil }
            do {
                let fresh = try await TopicWriter.writeMore(for: source)
                if Task.isCancelled {
                    phase = .idle
                    return
                }
                if fresh.isEmpty {
                    phase = .failed(tr("No new cards came back that fit. Try again.", "Es kamen keine passenden neuen Karten zurück. Versuch es nochmal."))
                    return
                }
                cards = fresh
                phase = .preview
                Haptics.success()
            } catch {
                phase = MaAI.isCancellation(error) ? .idle : .failed(MaAI.message(for: error))
            }
        }
    }

    private func add() {
        // Re-read the deck: it may have been edited while the model was writing.
        guard var current = deck, !cards.isEmpty else { return }
        let taken = Set(current.cards.map { Grader.normalize($0.prompt) })
        let fresh = cards.filter { !taken.contains(Grader.normalize($0.prompt)) }
        current.cards.append(contentsOf: fresh)
        model.decks.upsert(current)
        Haptics.success()
        dismiss()
    }
}
