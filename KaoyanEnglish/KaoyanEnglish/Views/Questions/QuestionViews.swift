import SwiftUI

struct QuestionLibraryView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @State private var type = ""
    @State private var search = ""
    private var articles: [Article] {
        ArticleNavigation.questionArticles(in: model.snapshot, type: type, search: search)
    }
    var body: some View {
        List {
            Section {
                Picker("题型", selection: $type) { Text("全部题型").tag(""); ForEach(QuestionType.allCases) { Text($0.title).tag($0.rawValue) } }
                Label("所有题目均为原创模拟题", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
            Section("按文章浏览 · \(articles.count) 篇") {
                ForEach(articles) { article in
                    NavigationLink { ArticleDetailView(id: article.id, typeFilter: type) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("改编文章").font(.caption.weight(.medium)).foregroundStyle(.teal)
                            Text(article.title).font(.headline)
                            Text(article.body).lineLimit(2).font(.subheadline).foregroundStyle(.secondary)
                            Text("\(ArticleNavigation.category(of: article)) · \(model.snapshot.questions.filter { $0.articleId == article.id }.count) 道题").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if articles.isEmpty { ContentUnavailableView("暂无匹配改编文章", systemImage: "doc.text", description: Text("导入改编文章后可在这里答题。原始文章及其直接关联题目可从“原文”查看。")) }
            }
        }.navigationTitle("模拟题库").searchable(text: $search, prompt: "搜索文章标题或正文")
    }
}
struct ArticleDetailView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    let id: String
    var typeFilter: String = ""
    @State private var editing = false
    @State private var deleting = false
    var body: some View {
        Group {
            if let article = model.snapshot.articles.first(where: { $0.id == id }) {
                List {
                    Section {
                        Text(article.title).font(.title2.bold()).textSelection(.enabled)
                        Text("\(article.kind == .adapted ? "改编文章" : "原始文章") · \(ArticleNavigation.category(of: article))").font(.caption).foregroundStyle(.teal)
                        ReadingTextView(text: article.body)
                    }
                    if let original = article.originalArticleId { OriginalArticleLinks(ids: [original]) }
                    if article.kind == .original {
                        OriginalAssociatedSections(originalId: article.id)
                    } else {
                      Section("原创模拟题") {
                        let questions = model.snapshot.questions.filter { $0.articleId == id && (typeFilter.isEmpty || $0.type.rawValue == typeFilter) }
                        ForEach(questions) { question in
                            NavigationLink { QuestionPracticeView(question: question) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(question.type.title).font(.caption).foregroundStyle(.teal)
                                    Text(question.stem).font(.subheadline)
                                    if model.snapshot.attempts.contains(where: { $0.questionId == question.id }) { Text("已练习 · 可再次作答").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 4)
                            }
                        }
                        if questions.isEmpty { Text("此文章暂无该题型。").foregroundStyle(.secondary) }
                      }
                    }
                    Section { Button("删除文章", role: .destructive) { deleting = true } }
                }.navigationTitle("阅读文章").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("编辑文章") { editing = true } }
                    .sheet(isPresented: $editing) { ArticleEditor(initial: article) }
            } else { ContentUnavailableView("文章不存在", systemImage: "doc") }
        }.confirmationDialog("仅可删除没有题目、词汇、表达或改编文章引用的文章。", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除文章", role: .destructive) { Task { if await model.delete(id, kind: .article) { dismiss() } } }
        }
    }
}
struct QuestionPracticeView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    let question: Question
    @State private var session: QuestionSession
    @State private var deleting = false
    @State private var editing = false
    init(question: Question) { self.question = question; _session = State(initialValue: QuestionSession(question: question)) }
    var body: some View {
        List {
            Section {
                Label(question.provenanceLabel, systemImage: "doc.text").font(.caption.bold()).foregroundStyle(.teal)
                Text(question.type.title + (question.difficulty.map { " · 难度 \($0)/5" } ?? "")).font(.caption).foregroundStyle(.secondary)
                Text(question.stem).font(.headline).textSelection(.enabled)
                if let article = model.snapshot.articles.first(where: { $0.id == question.articleId }) {
                    DisclosureGroup("阅读文章") { Text(article.body).lineSpacing(6).textSelection(.enabled) }
                }
            }
            Section("独立作答") {
                if question.type == .readingSingleChoice {
                    ForEach(question.options ?? []) { option in
                        Button {
                            session.selectedAnswer = option.id
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: session.selectedAnswer == option.id ? "largecircle.fill.circle" : "circle")
                                Text(option.id).bold()
                                Text(option.text).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 6)
                        }.disabled(session.submitted || model.busy).accessibilityIdentifier("answerOption_\(option.id)")
                    }
                } else {
                    Text("此题型暂提供内容展示和文本作答，提交后对照参考答案自评。").font(.footnote).foregroundStyle(.secondary)
                    ForEach(question.options ?? []) { option in Text("\(option.id). \(option.text)") }
                    TextEditor(text: $session.selectedAnswer).frame(minHeight: 140).disabled(session.submitted || model.busy).accessibilityLabel("我的答案")
                }
                if !session.submitted {
                    Button {
                        Task {
                            do {
                                let attempt = try session.makeAttempt()
                                if await model.perform({ try await model.worker.submit(attempt) }) { session.markSubmitted() }
                            } catch { model.message = error.localizedDescription }
                        }
                    } label: { Text("提交答案").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.borderedProminent).disabled(!session.canSubmit || model.busy).accessibilityIdentifier("submitAnswer")
                    Text("提交后才显示正确答案、解析与原文依据。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if session.submitted {
                Section("答题结果") {
                    if question.type == .readingSingleChoice {
                        Label(session.selectedAnswer == session.revealedAnswer ? "回答正确" : "再想一想", systemImage: session.selectedAnswer == session.revealedAnswer ? "checkmark.circle" : "xmark.circle").foregroundStyle(session.selectedAnswer == session.revealedAnswer ? .green : .orange)
                    }
                    Text("你的答案：\(session.selectedAnswer)")
                    Text("参考答案：\(session.revealedAnswer ?? "")").accessibilityIdentifier("revealedAnswer").textSelection(.enabled)
                }
                DetailSection(title: "答案解析", text: session.revealedExplanation)
                DetailSection(title: "原文依据", text: session.revealedEvidence)
                if let distractors = session.revealedDistractors, !distractors.isEmpty {
                    Section("错误选项分析") { ForEach(distractors.keys.sorted(), id: \.self) { key in Text("\(key)：\(distractors[key] ?? "")").textSelection(.enabled) } }
                }
                DetailSection(title: "考查能力", text: question.testedSkill)
                Section {
                    Button("重新练习") { session.reset() }
                    Button("编辑题目") { editing = true }
                }
            }
        }.navigationTitle("\(question.type.title)练习").navigationBarTitleDisplayMode(.inline)
            .toolbar { Menu { Button("删除题目", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis.circle") } }
            .confirmationDialog("删除此题及其所有答题记录？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除题目", role: .destructive) { Task { if await model.delete(question.id, kind: .question) { dismiss() } } }
            }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) { QuestionEditor(initial: question) }
    }
}
struct ArticleEditor: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Article
    init(initial: Article) { _draft = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $draft.title, axis: .vertical)
                TextField("主题", text: optionalText($draft.theme))
                Section("正文") { TextEditor(text: $draft.body).frame(minHeight: 300) }
            }.navigationTitle("编辑文章").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { if await model.perform({ try await model.worker.save(draft) }) { dismiss() } } }.disabled(model.busy || TextKey.normalize(draft.title).isEmpty || TextKey.normalize(draft.body).isEmpty) }
            }
        }
    }
}
struct QuestionEditor: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Question
    init(initial: Question) { _draft = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            Form {
                Section("原创模拟题") {
                    TextField("题干", text: $draft.stem, axis: .vertical)
                    ForEach(Array((draft.options ?? []).indices), id: \.self) { index in
                        TextField("选项 \(draft.options?[index].id ?? "")", text: Binding(get: { draft.options?[index].text ?? "" }, set: { draft.options?[index].text = $0 }), axis: .vertical)
                    }
                    TextField("正确答案（单选题填写选项 ID）", text: $draft.correctAnswer, axis: .vertical)
                    TextField("解析", text: $draft.explanation, axis: .vertical)
                    TextField("原文依据", text: optionalText($draft.evidence), axis: .vertical)
                    TextField("考查能力", text: optionalText($draft.testedSkill))
                    Picker("难度", selection: Binding(get: { draft.difficulty ?? 0 }, set: { draft.difficulty = $0 == 0 ? nil : $0 })) { Text("未提供").tag(0); ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                }
                Section { Text("已有答题记录会保留当时的答案与判断。保存后请重新进入练习。").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("编辑题目").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { if await model.perform({ try await model.worker.save(draft) }) { dismiss() } } }.disabled(model.busy) }
            }
        }
    }
}
