import SwiftUI

struct OptionalText: View {
    let value: String?
    init(_ value: String?) { self.value = value }
    var body: some View { if let value, !value.isEmpty { Text(value).foregroundStyle(.secondary).textSelection(.enabled) } }
}
struct DetailSection: View {
    let title: String
    let text: String?
    var secondary: String? = nil
    var body: some View {
        if let text, !text.isEmpty {
            Section(title) {
                Text(text).lineSpacing(5).textSelection(.enabled)
                OptionalText(secondary)
            }
        }
    }
}
struct SourceArticleSection: View {
    @EnvironmentObject private var model: LibraryViewModel
    let ids: [String]
    var body: some View {
        Section("来源文章（\(ids.count)）") {
            ForEach(ids, id: \.self) { id in
                if let article = model.snapshot.articles.first(where: { $0.id == id }) {
                    NavigationLink { ArticleDetailView(id: id) } label: {
                        Label(article.title, systemImage: article.kind == .adapted ? "doc.text" : "doc.plaintext")
                    }
                }
            }
        }
    }
}
struct SourcePicker: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Binding var ids: [String]
    var body: some View {
        Section("关联来源文章（至少一篇）") {
            ForEach(model.snapshot.articles) { article in
                Toggle(article.title, isOn: Binding(get: { ids.contains(article.id) }, set: { chosen in
                    if chosen { ids = Array(Set(ids + [article.id])).sorted() } else { ids.removeAll { $0 == article.id } }
                }))
            }
        }
    }
}
func optionalText(_ value: Binding<String?>) -> Binding<String> {
    Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
}
func splitTags(_ text: String) -> [String] {
    Array(Set(text.components(separatedBy: CharacterSet(charactersIn: ",，\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
}
