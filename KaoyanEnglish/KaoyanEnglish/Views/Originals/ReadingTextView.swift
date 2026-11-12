import SwiftUI
import UIKit

struct ReadingSelection: Identifiable {
    let id = UUID()
    let match: ReadingMatch
}

struct ReadingTextView: View {
    @EnvironmentObject private var model: LibraryViewModel
    let text: String
    @State private var selection: ReadingSelection?
    var body: some View {
        ReadingText(text: text, matches: ReadingMatches.find(in: text, vocabulary: model.snapshot.vocabulary, writing: model.snapshot.writing)) {
            selection = ReadingSelection(match: $0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(item: $selection, arrowEdge: .bottom) { item in
            ReadingLookup(match: item.match)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ReadingText: UIViewRepresentable {
    let text: String
    let matches: [ReadingMatch]
    let tapped: (ReadingMatch) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isScrollEnabled = false; view.isSelectable = true
        view.backgroundColor = .clear; view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0; view.delegate = context.coordinator
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let style = NSMutableParagraphStyle(); style.lineSpacing = 7
        let content = NSMutableAttributedString(string: text, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label, .paragraphStyle: style])
        for (index, match) in matches.enumerated() {
            content.addAttributes([.link: URL(string: "kaoyan-lookup://entry/\(index)")!,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash.rawValue,
                                   .underlineColor: UIColor.systemGray, .foregroundColor: UIColor.label], range: match.range)
        }
        view.linkTextAttributes = [.foregroundColor: UIColor.label, .underlineColor: UIColor.systemGray,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash.rawValue]
        view.attributedText = content
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReadingText
        init(parent: ReadingText) { self.parent = parent }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            guard URL.scheme == "kaoyan-lookup", let index = Int(URL.lastPathComponent), parent.matches.indices.contains(index) else { return false }
            parent.tapped(parent.matches[index]); return false
        }
    }
}

private struct ReadingLookup: View {
    @EnvironmentObject private var model: LibraryViewModel
    let match: ReadingMatch
    private var words: [VocabularyEntry] {
        VocabularyGrouping.entries(model.snapshot.vocabulary).filter { entry in
            entry.records.contains { match.vocabularyIDs.contains($0.id) }
        }
    }
    private var expressions: [WritingExpression] { model.snapshot.writing.filter { match.writingIDs.contains($0.id) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(words) { word in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(word.lemma).font(.headline)
                            Spacer()
                            Button {
                                Task { await model.favoriteVocabulary(ids: word.records.map(\.id), value: !word.isFavorite(model.snapshot.favoriteVocabulary)) }
                            } label: { Image(systemName: word.isFavorite(model.snapshot.favoriteVocabulary) ? "star.fill" : "star") }
                                .accessibilityLabel(word.isFavorite(model.snapshot.favoriteVocabulary) ? "取消收藏" : "收藏词汇")
                        }
                        ForEach(word.phonetics, id: \.self) { Text($0).foregroundStyle(.secondary) }
                        ForEach(word.senses) { sense in
                            ForEach(sense.englishDefinitions, id: \.self) { definition in
                                Text(definition).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text((sense.partOfSpeech.map { $0 + " · " } ?? "") + sense.meaning)
                        }
                    }
                }
                ForEach(expressions) { expression in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(expression.expression).font(.headline); Spacer()
                            Button {
                                Task { await model.favorite(expression.id, kind: .writing, value: !model.snapshot.favoriteWriting.contains(expression.id)) }
                            } label: { Image(systemName: model.snapshot.favoriteWriting.contains(expression.id) ? "star.fill" : "star") }
                                .accessibilityLabel(model.snapshot.favoriteWriting.contains(expression.id) ? "取消收藏" : "收藏表达")
                        }
                        Text(expression.meaning)
                    }
                }
            }.padding(18).frame(minWidth: 240, maxWidth: 340, alignment: .leading)
        }.frame(maxHeight: 420)
    }
}
