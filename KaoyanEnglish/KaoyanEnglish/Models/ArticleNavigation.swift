import Foundation

/// Shared selection for both the bottom tabs and the three home shortcuts.
enum AppTab: Hashable {
    case home, originals, vocabulary, questions, writing
}

enum ArticleNavigation {
    static func category(of article: Article) -> String {
        let category = article.theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return category.isEmpty ? "未分类" : category
    }

    static func originals(in snapshot: LibrarySnapshot, category: String? = nil, search: String = "") -> [Article] {
        snapshot.articles.filter { article in
            article.kind == .original &&
            (category == nil || self.category(of: article) == category) &&
            (search.isEmpty || TextKey.normalize(article.title + " " + article.body).contains(TextKey.normalize(search)))
        }.sorted { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
    }

    static func categories(in snapshot: LibrarySnapshot) -> [String] {
        Array(Set(snapshot.articles.filter { $0.kind == .original }.map { category(of: $0) })).sorted()
    }

    static func adaptations(of originalId: String, in snapshot: LibrarySnapshot) -> [Article] {
        snapshot.articles.filter { $0.kind == .adapted && $0.originalArticleId == originalId }
            .sorted { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
    }

    static func relatedArticleIds(to originalId: String, in snapshot: LibrarySnapshot) -> Set<String> {
        Set([originalId] + adaptations(of: originalId, in: snapshot).map(\.id))
    }

    static func questions(for originalId: String, in snapshot: LibrarySnapshot) -> [Question] {
        let articleIds = relatedArticleIds(to: originalId, in: snapshot)
        var seen = Set<String>()
        return snapshot.questions.filter { articleIds.contains($0.articleId) && seen.insert($0.id).inserted }
            .sorted { $0.articleId == $1.articleId ? $0.id < $1.id : $0.articleId < $1.articleId }
    }

    static func questionArticles(in snapshot: LibrarySnapshot, type: String = "", search: String = "") -> [Article] {
        snapshot.articles.filter { article in
            article.kind == .adapted &&
            (search.isEmpty || TextKey.normalize(article.title + " " + article.body).contains(TextKey.normalize(search))) &&
            (type.isEmpty || snapshot.questions.contains { $0.articleId == article.id && $0.type.rawValue == type })
        }.sorted { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
    }
}
