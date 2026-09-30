import SwiftUI

/// "Create a topic with AI": type a subject, pick a level and a size, and
/// the on-device model writes the deck. Nothing is saved until the learner
/// has looked at the cards and tapped Save.
struct CreateTopicView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Told about the saved deck, so the caller can say where it went.
    var onSaved: (Deck) -> Void = { _ in }

    private enum Phase: Equatable {
        case idle
        case working(cards: Int)
        case failed(String)
        case preview
    }

    @State private var topic = ""
    @State private var level: TopicLevel = .beginner
    @State private var count = 20
    @State private var phase: Phase = .idle
    @State private var draft: TopicDraft?
    @State private var job: Task<Void, Never>?
    @State private var status: MaAI.Status = .ready
    @FocusState private var typing: Bool

    private static let sizes = [10, 20, 30]

    private var working: Bool {
        if case .working = phase { return true }
        return false
    }

    private var canCreate: Bool {
        let filled = !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return filled && status.isReady && !working
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    if !status.isReady {
                        AIUnavailableNote(status: status)
                    }
                    if phase == .preview, let draft {
                        previewSection(draft)
                    } else {
                        form
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(tr("Topic with AI", "Thema mit KI"))
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
                        Button(tr("Save", "Sichern"), action: save)
                            .fontWeight(.semibold)
                            .disabled((draft?.cards.isEmpty ?? true))
                    }
                }
            }
            .interactiveDismissDisabled(working || phase == .preview)
        }
        .onAppear { status = MaAI.status }
        .onDisappear { job?.cancel() }
    }

    // MARK: Parts

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: "sparkles", tint: Zen.ai, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Let Apple Intelligence write the cards", "Lass Apple Intelligence die Karten schreiben"))
                    .displayFont(19, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("Questions, answers, wrong options, examples and short notes. You check them before anything is saved.",
                        "Fragen, Antworten, falsche Optionen, Beispiele und kurze Notizen. Du siehst sie dir an, bevor etwas gespeichert wird."))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                AIPrivacyLabel()
                    .padding(.top, 2)
            }
        }
        .zenCard()
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                fieldTitle(tr("What do you want to learn?", "Was möchtest du lernen?"))
                TextField(tr("e.g. Photosynthesis or Spanish food words", "z. B. Fotosynthese oder spanische Wörter fürs Essen"), text: $topic, axis: .vertical)
                    .scaledFont(size: 18, weight: .medium)
                    .lineLimit(1...3)
                    .focused($typing)
                    .submitLabel(.done)
                    .disabled(working)
                    .padding(16)
                    .background(Zen.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(typing ? Zen.shu : Zen.line, lineWidth: typing ? 2 : 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldTitle(tr("Level", "Niveau"))
                HStack(spacing: 8) {
                    ForEach(TopicLevel.allCases) { option in
                        Chip(title: option.title, selected: level == option) {
                            if !working { level = option }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldTitle(tr("Cards", "Karten"))
                HStack(spacing: 8) {
                    ForEach(Self.sizes, id: \.self) { size in
                        Chip(title: "\(size)", selected: count == size) {
                            if !working { count = size }
                        }
                    }
                }
                Text(tr("More cards take longer. Around half a minute per ten is normal.",
                        "Mehr Karten dauern länger. Etwa eine halbe Minute pro zehn ist normal."))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            progressBlock

            if working {
                Button(tr("Stop", "Anhalten")) {
                    job?.cancel()
                }
                .buttonStyle(.quiet)
            } else {
                Button(action: create) {
                    Label(tr("Create", "Erstellen"), systemImage: "sparkles")
                }
                .buttonStyle(.primary)
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.4)
            }
        }
    }

    @ViewBuilder
    private var progressBlock: some View {
        switch phase {
        case .working(let cards):
            let ratio = Double(cards) / Double(max(1, count))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Zen.ai)
                    Text(cards == 0
                         ? tr("Writing the first cards…", "Die ersten Karten entstehen…")
                         : tr("\(cards) of \(count) cards written…", "\(cards) von \(count) Karten geschrieben…"))
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Zen.ink)
                        .contentTransition(.numericText())
                }
                InkProgress(value: max(0.04, ratio), color: Zen.ai, height: 8)
                    // The line above already says how many cards are written.
                    .accessibilityHidden(true)
            }
            .zenCard()
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .scaledFont(size: 14)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        default:
            EmptyView()
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(Zen.inkSoft)
            .textCase(.uppercase)
    }

    // MARK: Preview

    private func previewSection(_ draft: TopicDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Hanko(text: draft.symbol, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    TextField(tr("Title", "Titel"), text: draftBinding(\.title))
                        .displayFont(22)
                        .foregroundStyle(Zen.ink)
                    TextField(tr("What is it about?", "Worum geht es?"), text: draftBinding(\.subtitle))
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                }
            }
            .zenCard()

            if let shortfall = draft.shortfall {
                Label(shortfall, systemImage: "info.circle")
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AICardPreviewList(cards: draftCardsBinding)

            Button(action: save) {
                Label(tr("Save and learn", "Sichern und lernen"), systemImage: "checkmark")
            }
            .buttonStyle(.primary)
            .disabled(draft.cards.isEmpty)
            .opacity(draft.cards.isEmpty ? 0.4 : 1)

            Button(tr("Start over", "Neu anfangen")) {
                self.draft = nil
                phase = .idle
            }
            .buttonStyle(.quiet)
        }
    }

    private func draftBinding(_ keyPath: WritableKeyPath<TopicDraft, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { draft?[keyPath: keyPath] = $0 }
        )
    }

    private var draftCardsBinding: Binding<[Card]> {
        Binding(
            get: { draft?.cards ?? [] },
            set: { draft?.cards = $0 }
        )
    }

    // MARK: Actions

    private func create() {
        typing = false
        status = MaAI.status
        guard canCreate else { return }
        let subject = topic
        let chosenLevel = level
        let size = count
        phase = .working(cards: 0)
        Haptics.tap()
        job = Task {
            defer { job = nil }
            do {
                let result = try await TopicWriter.writeTopic(topic: subject, level: chosenLevel, count: size) { written in
                    phase = .working(cards: written)
                }
                if Task.isCancelled {
                    phase = .idle
                    return
                }
                if result.cards.isEmpty {
                    phase = .failed(tr("No usable cards came back. Try a clearer topic.", "Es kamen keine brauchbaren Karten zurück. Versuch ein klareres Thema."))
                    return
                }
                draft = result
                phase = .preview
                Haptics.success()
            } catch {
                phase = MaAI.isCancellation(error) ? .idle : .failed(MaAI.message(for: error))
            }
        }
    }

    private func save() {
        guard var result = draft, !result.cards.isEmpty else { return }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.title = title.isEmpty ? topic.trimmingCharacters(in: .whitespacesAndNewlines) : title
        let deck = Deck(title: result.title, subtitle: result.subtitle, symbol: result.symbol, cards: result.cards)
        model.decks.upsert(deck)
        // A topic you just asked for should also show up before your next unlock.
        model.decks.profile.activeDeckIDs.insert(deck.id)
        Haptics.success()
        onSaved(deck)
        dismiss()
    }
}

// MARK: - Card preview

/// The cards the model wrote, before they are saved. Each one can be
/// dropped with a tap, so a weak card never reaches the deck.
struct AICardPreviewList: View {
    @Binding var cards: [Card]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "rectangle.stack.fill", title: tr("\(cards.count) cards", "\(cards.count) Karten"))
            Text(tr("Tap the cross to drop a card you do not want.", "Tipp aufs Kreuz, um eine Karte wegzulassen."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
            VStack(spacing: 10) {
                ForEach(cards) { card in
                    AICardPreviewRow(card: card) {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.2)) {
                            cards.removeAll { $0.id == card.id }
                        }
                    }
                }
            }
        }
    }
}

struct AICardPreviewRow: View {
    let card: Card
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.prompt)
                    .cardFont(for: card.prompt, kanji: 18, bold: true, size: 16, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.answer)
                    .cardFont(for: card.answer, kanji: 17, bold: true, size: 16, weight: .bold, design: .rounded)
                    .foregroundStyle(Zen.shu)
                if !card.distractors.isEmpty {
                    let wrong = card.distractors.joined(separator: " · ")
                    Label(wrong, systemImage: "xmark")
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(tr("Wrong options: \(card.distractors.joined(separator: ", "))",
                                               "Falsche Optionen: \(card.distractors.joined(separator: ", "))"))
                }
                if let example = card.example {
                    Text(TeachCard.highlighted(example, answer: card.answer))
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = card.note {
                    Text(note)
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Zen.inkFaint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Drop this card", "Diese Karte weglassen"))
        }
        .zenCard(padding: 14)
    }
}
