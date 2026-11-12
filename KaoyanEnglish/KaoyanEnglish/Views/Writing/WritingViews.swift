import SwiftUI

struct WritingListView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @State private var search = ""
    @State private var topic = ""
    @State private var favoritesOnly = false
    @State private var creating = false
    private var filtered: [WritingExpression] {
        model.snapshot.writing.filter {
            (search.isEmpty || TextKey.normalize($0.expression + " " + $0.meaning).contains(TextKey.normalize(search))) &&
            (topic.isEmpty || ($0.topics ?? []).contains(topic)) && (!favoritesOnly || model.snapshot.favoriteWriting.contains($0.id))
        }
    }
    var body: some View {
        List {
            Section {
                Picker("主题", selection: $topic) { Text("全部主题").tag(""); ForEach(model.topics, id: \.self) { Text($0).tag($0) } }
                Toggle("只看收藏", isOn: $favoritesOnly)
            }
            Section("\(filtered.count) 条表达") {
                ForEach(filtered) { expression in
                    NavigationLink { WritingDetailView(id: expression.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(expression.expression).font(.headline); if model.snapshot.favoriteWriting.contains(expression.id) { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) } }
                            Text(expression.meaning).font(.subheadline)
                            Text((expression.topics ?? []).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
                if filtered.isEmpty { ContentUnavailableView("暂无匹配表达", systemImage: "pencil.and.outline", description: Text("导入学习资料，积累可用于作文的表达。")) }
            }
        }.navigationTitle("写作库").searchable(text: $search, prompt: "搜索表达或中文释义")
            .toolbar { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增写作表达").disabled(model.busy || model.snapshot.articles.isEmpty) }
            .sheet(isPresented: $creating) { WritingEditor(initial: WritingExpression(id: UUID().uuidString.lowercased(), expression: "", meaning: "", sourceArticleIds: []), isNew: true) }
    }
}
struct WritingDetailView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var editing = false
    @State private var deleting = false
    var body: some View {
        Group {
            if let value = model.snapshot.writing.first(where: { $0.id == id }) {
                List {
                    Section {
                        Text(value.expression).font(.title2.bold()).textSelection(.enabled)
                        Text(value.meaning).textSelection(.enabled)
                        OptionalText(value.expressionType)
                        Text((value.topics ?? []).joined(separator: " · ")).font(.caption).foregroundStyle(.teal)
                    }
                    DetailSection(title: "适用语境", text: value.context)
                    DetailSection(title: "原文例句", text: value.originalSentence)
                    DetailSection(title: "作文改写例句", text: value.essaySentence, secondary: value.translation)
                    DetailSection(title: "可替换表达", text: value.alternatives?.joined(separator: "\n"))
                    DetailSection(title: "使用注意事项", text: value.usageNotes)
                    OriginalArticleLinks(ids: value.sourceArticleIds)
                    Section { Button("删除表达", role: .destructive) { deleting = true } }
                }.navigationTitle("表达详情").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        Button { Task { await model.favorite(id, kind: .writing, value: !model.snapshot.favoriteWriting.contains(id)) } } label: { Image(systemName: model.snapshot.favoriteWriting.contains(id) ? "star.fill" : "star") }.accessibilityLabel("收藏表达")
                        Button("编辑") { editing = true }
                    }
                    .sheet(isPresented: $editing) { WritingEditor(initial: value, isNew: false) }
            } else { ContentUnavailableView("此表达已删除", systemImage: "pencil") }
        }.confirmationDialog("删除此表达及其收藏？此操作不可撤销。", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除表达", role: .destructive) { Task { if await model.delete(id, kind: .writing) { dismiss() } } }
        }
    }
}
struct WritingEditor: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WritingExpression
    @State private var topics: String
    @State private var alternatives: String
    let isNew: Bool
    init(initial: WritingExpression, isNew: Bool) {
        _draft = State(initialValue: initial); _topics = State(initialValue: (initial.topics ?? []).joined(separator: "，"))
        _alternatives = State(initialValue: (initial.alternatives ?? []).joined(separator: "\n")); self.isNew = isNew
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("表达") {
                    TextField("英文表达", text: $draft.expression, axis: .vertical).textInputAutocapitalization(.never)
                    TextField("中文释义", text: $draft.meaning, axis: .vertical)
                    TextField("主题，用逗号分隔；支持新增主题", text: $topics, axis: .vertical)
                    TextField("表达类型", text: optionalText($draft.expressionType))
                    TextField("使用语境", text: optionalText($draft.context), axis: .vertical)
                }
                Section("例句与用法") {
                    TextField("原文例句", text: optionalText($draft.originalSentence), axis: .vertical)
                    TextField("作文改写例句", text: optionalText($draft.essaySentence), axis: .vertical)
                    TextField("中文翻译", text: optionalText($draft.translation), axis: .vertical)
                    TextField("可替换表达，每行一项", text: $alternatives, axis: .vertical)
                    TextField("使用注意事项", text: optionalText($draft.usageNotes), axis: .vertical)
                }
                SourcePicker(ids: $draft.sourceArticleIds)
            }.navigationTitle(isNew ? "新增表达" : "编辑表达").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            draft.topics = splitTags(topics); draft.alternatives = alternatives.split(separator: "\n").map(String.init)
                            Task { if await model.perform({ try await model.worker.save(draft, isNew: isNew) }) { dismiss() } }
                        }.disabled(model.busy || TextKey.normalize(draft.expression).isEmpty || TextKey.normalize(draft.meaning).isEmpty || draft.sourceArticleIds.isEmpty)
                    }
                }
        }.interactiveDismissDisabled(model.busy)
    }
}
