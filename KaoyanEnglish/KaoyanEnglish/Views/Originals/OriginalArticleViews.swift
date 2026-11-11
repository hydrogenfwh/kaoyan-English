import SwiftUI

struct OriginalArticleListView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @State private var category: String? = nil
    @State private var search = ""
    private var articles: [Article] { ArticleNavigation.originals(in: model.snapshot, category: category, search: search) }

    var body: some View {
        List {
            Section {
                Picker("分类", selection: $category) {
                    Text("全部分类").tag(String?.none)
                    ForEach(ArticleNavigation.categories(in: model.snapshot), id: \.self) { value in
                        Text(value).tag(Optional(value))
                    }
                }.accessibilityIdentifier("originalCategoryFilter")
            }
            Section("原文目录 · \(articles.count) 篇") {
                ForEach(articles) { article in
                    NavigationLink { ArticleDetailView(id: article.id) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(article.title).font(.headline)
                            Text(ArticleNavigation.category(of: article)).font(.caption).foregroundStyle(.teal)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("originalArticle_\(article.id)")
                }
                if articles.isEmpty {
                    ContentUnavailableView("暂无匹配原文", systemImage: "book.pages", description: Text("导入包含原始文章的资料，或调整分类与搜索条件。"))
                }
            }
        }.navigationTitle("原文").searchable(text: $search, prompt: "搜索原文标题或正文")
    }
}

struct OriginalAssociatedSections: View {
    @EnvironmentObject private var model: LibraryViewModel
    let originalId: String
    private var relatedIds: Set<String> { ArticleNavigation.relatedArticleIds(to: originalId, in: model.snapshot) }
    private var vocabulary: [VocabularyEntry] {
        VocabularyGrouping.entries(model.snapshot.vocabulary).filter { entry in
            entry.records.contains { !Set($0.sourceArticleIds).isDisjoint(with: relatedIds) }
        }
    }
    private var writing: [WritingExpression] { model.snapshot.writing.filter { !Set($0.sourceArticleIds).isDisjoint(with: relatedIds) } }
    private var questions: [Question] { ArticleNavigation.questions(for: originalId, in: model.snapshot) }

    var body: some View {
        Section("关联词汇") {
            ForEach(vocabulary) { word in
                NavigationLink { VocabularyDetailView(id: word.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(word.lemma).font(.headline)
                        Text(Array(Set(word.records.map(\.meaning))).sorted().joined(separator: "；"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if vocabulary.isEmpty { Text("此原文及其改编文章暂无关联词汇。").foregroundStyle(.secondary) }
        }
        Section("关联写作表达") {
            ForEach(writing) { expression in
                NavigationLink { WritingDetailView(id: expression.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(expression.expression).font(.headline)
                        Text(expression.meaning).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if writing.isEmpty { Text("此原文及其改编文章暂无关联写作表达。").foregroundStyle(.secondary) }
        }
        Section("关联原创模拟题") {
            ForEach(questions) { question in
                NavigationLink { QuestionPracticeView(question: question) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.type.title).font(.caption).foregroundStyle(.teal)
                        if question.articleId == originalId {
                            Text("对应本文原文").font(.caption).foregroundStyle(.secondary)
                        } else if let article = model.snapshot.articles.first(where: { $0.id == question.articleId }) {
                            Text("改编文章：\(article.title)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(question.stem).font(.subheadline)
                    }.padding(.vertical, 3)
                }.accessibilityIdentifier("originalQuestion_\(question.id)")
            }
            if questions.isEmpty { Text("此原文及其改编文章暂无关联题目。").foregroundStyle(.secondary) }
        }
        let adaptations = ArticleNavigation.adaptations(of: originalId, in: model.snapshot)
        if !adaptations.isEmpty {
            Section("改编文章") {
                ForEach(adaptations) { article in
                    NavigationLink(article.title) { ArticleDetailView(id: article.id) }
                }
            }
        }
    }
}
