import SwiftUI

struct VocabularyListView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @State private var search = ""
    @State private var topic = ""
    @State private var difficulty = 0
    @State private var favoritesOnly = false
    @State private var creating = false
    private var filtered: [VocabularyEntry] {
        VocabularyGrouping.filteredEntries(model.snapshot.vocabulary, search: search, topic: topic,
            difficulty: difficulty, favoritesOnly: favoritesOnly, favoriteIDs: model.snapshot.favoriteVocabulary)
    }
    var body: some View {
        List {
            Section {
                Picker("主题", selection: $topic) { Text("全部主题").tag(""); ForEach(model.topics, id: \.self) { Text($0).tag($0) } }
                Picker("难度", selection: $difficulty) { Text("全部难度").tag(0); ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) } }
                Toggle("只看收藏", isOn: $favoritesOnly)
            }
            Section("\(filtered.count) 个词条") {
                ForEach(filtered) { entry in
                    NavigationLink { VocabularyDetailView(id: entry.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.lemma).font(.headline)
                                if entry.isFavorite(model.snapshot.favoriteVocabulary) { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                            }
                            Text(entry.senses.map(\.meaning).joined(separator: "；")).font(.subheadline).lineLimit(2)
                            Text("\(entry.senses.count) 个词义 · " + entry.topics.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.vertical, 3)
                    }.accessibilityIdentifier("vocabularyEntry_" + entry.id)
                }
                if filtered.isEmpty { ContentUnavailableView("暂无匹配词汇", systemImage: "character.book.closed", description: Text("从首页导入资料，或调整搜索与筛选条件。")) }
            }
        }.navigationTitle("词汇库").searchable(text: $search, prompt: "搜索原形、原文词形、中英文释义")
            .toolbar { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增词汇").disabled(model.busy || model.snapshot.articles.isEmpty) }
            .sheet(isPresented: $creating) { VocabularyEditor(initial: Vocabulary(id: UUID().uuidString.lowercased(), expression: "", meaning: "", sourceArticleIds: []), isNew: true) }
    }
}

struct VocabularyDetailView: View {
    @EnvironmentObject private var model: LibraryViewModel
    let id: String
    @State private var resolvedEntryID: String?
    @State private var editing: Vocabulary?
    @State private var deleting: Vocabulary?
    private var entries: [VocabularyEntry] { VocabularyGrouping.entries(model.snapshot.vocabulary) }
    private var entry: VocabularyEntry? {
        entries.first { $0.id == id || $0.records.contains { $0.id == id } } ?? entries.first { $0.id == resolvedEntryID }
    }
    var body: some View {
        Group {
            if let entry {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.lemma).font(.largeTitle.bold()).textSelection(.enabled)
                            let pronunciations = pronunciationLabels(entry)
                            if pronunciations.isEmpty {
                                Text("音标未提供").font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(pronunciations, id: \.self) { Text($0).foregroundStyle(.secondary).textSelection(.enabled) }
                            }
                        }.padding(.vertical, 4).accessibilityIdentifier("vocabularyHeader")
                        Text("\(entry.senses.count) 个词义 · \(entry.records.count) 条来源记录").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(entry.senses.enumerated()), id: \.element.id) { index, sense in
                        Section("词义 \(index + 1) · \(sense.partOfSpeech ?? "词性未提供")") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(sense.englishDefinitions, id: \.self) { definition in
                                    Text(definition).textSelection(.enabled)
                                }
                                Text(sense.meaning).font(.title3).textSelection(.enabled)
                            }.padding(.vertical, 4)
                            ForEach(sense.records) { record in
                                VocabularyContextView(record: record, showDefinition: sense.englishDefinitions.count > 1,
                                    edit: { editing = record }, delete: { deleting = record })
                            }
                        }
                    }
                    let related = VocabularyGrouping.related(to: entry, in: entries)
                    Section("同根词") {
                        if related.isEmpty { Text("词库中暂无已确认的同根词。").foregroundStyle(.secondary) }
                        ForEach(related) { other in
                            NavigationLink { VocabularyDetailView(id: other.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(other.lemma).font(.headline)
                                    Text(other.senses.map(\.meaning).joined(separator: "；")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .toolbar {
                    Button {
                        Task { await model.favoriteVocabulary(ids: entry.records.map(\.id), value: !entry.isFavorite(model.snapshot.favoriteVocabulary)) }
                    } label: { Image(systemName: entry.isFavorite(model.snapshot.favoriteVocabulary) ? "star.fill" : "star") }
                        .accessibilityLabel(entry.isFavorite(model.snapshot.favoriteVocabulary) ? "取消收藏词条" : "收藏词条").disabled(model.busy)
                }
                .onAppear { resolvedEntryID = entry.id }
            } else { ContentUnavailableView("此词条已没有词义记录", systemImage: "book") }
        }
        .navigationTitle("词汇详情").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { VocabularyEditor(initial: $0, isNew: false) }
        .confirmationDialog("删除这一条词义来源记录？其他词义和来源记录会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let deleting {
                Button("删除这条记录", role: .destructive) {
                    let recordID = deleting.id
                    Task { _ = await model.delete(recordID, kind: .vocabulary); self.deleting = nil }
                }
            }
        }
    }
    private func pronunciationLabels(_ entry: VocabularyEntry) -> [String] {
        Array(Set(entry.records.compactMap { word -> String? in
            guard let phonetic = word.phonetic, !phonetic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TextKey.normalize(word.expression) == entry.lemma ? phonetic : "\(word.expression)  \(phonetic)"
        })).sorted()
    }
}

/// Each saved context remains independently editable. Old multi-source rows do not
/// assert which article supplied the single legacy sentence when that was not recorded.
private struct VocabularyContextView: View {
    @EnvironmentObject private var model: LibraryViewModel
    let record: Vocabulary
    let showDefinition: Bool
    let edit: () -> Void
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("原文词形：\(record.expression)").font(.subheadline.bold()).textSelection(.enabled)
            OptionalText(record.phonetic)
            if let pos = record.partOfSpeech, !pos.isEmpty { Text("词性：" + pos).font(.caption).foregroundStyle(.secondary) }
            if showDefinition, let definition = record.englishDefinition, !definition.isEmpty {
                Text(definition).font(.subheadline).textSelection(.enabled)
            }
            if let sentence = record.originalSentence, !sentence.isEmpty {
                Text(sentence).lineSpacing(4).textSelection(.enabled)
                OptionalText(record.sentenceTranslation)
            } else { Text("此记录未保存原文例句").font(.caption).foregroundStyle(.secondary) }
            if let collocations = record.collocations, !collocations.isEmpty {
                Text("常见搭配：" + collocations.joined(separator: " · ")).font(.subheadline).textSelection(.enabled)
            }
            Text(record.difficulty.map { "难度 \($0) / 5" } ?? "难度未提供").font(.caption).foregroundStyle(.secondary)
            if !(record.topics ?? []).isEmpty { Text((record.topics ?? []).joined(separator: " · ")).font(.caption).foregroundStyle(.teal) }
            if record.sourceArticleIds.count > 1 {
                Text("此记录关联多篇文章；已有数据未逐篇标注例句归属。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(record.sourceArticleIds, id: \.self) { articleID in
                if let article = model.snapshot.articles.first(where: { $0.id == articleID }) {
                    NavigationLink { ArticleDetailView(id: articleID) } label: {
                        Label("\(article.kind == .original ? "原文" : "改编文")：\(article.title)", systemImage: "doc.text").font(.subheadline)
                    }
                }
            }
            HStack {
                Button("编辑此词义与来源", action: edit).accessibilityIdentifier("editVocabularyRecord_" + record.id)
                Spacer()
                Button("删除此记录", role: .destructive, action: delete).accessibilityIdentifier("deleteVocabularyRecord_" + record.id)
            }.font(.subheadline).buttonStyle(.borderless).disabled(model.busy)
        }.padding(.vertical, 6)
    }
}

struct VocabularyEditor: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Vocabulary
    @State private var topics: String
    @State private var collocations: String
    let isNew: Bool
    init(initial: Vocabulary, isNew: Bool) {
        _draft = State(initialValue: initial); _topics = State(initialValue: (initial.topics ?? []).joined(separator: "，"))
        _collocations = State(initialValue: (initial.collocations ?? []).joined(separator: "\n")); self.isNew = isNew
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("词汇与释义") {
                    TextField("原文出现的词形或表达", text: $draft.expression).textInputAutocapitalization(.never)
                    TextField("音标", text: optionalText($draft.phonetic))
                    TextField("英文释义", text: optionalText($draft.englishDefinition), axis: .vertical)
                    TextField("中文释义（不同措辞分别保留）", text: $draft.meaning, axis: .vertical)
                    TextField("词性，例如 noun / verb / 形容词", text: optionalText($draft.partOfSpeech))
                    Picker("难度", selection: Binding(get: { draft.difficulty ?? 0 }, set: { draft.difficulty = $0 == 0 ? nil : $0 })) { Text("未提供").tag(0); ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                    TextField("主题，用逗号分隔；支持新增主题", text: $topics, axis: .vertical)
                }
                Section {
                    TextField("已确认的原形（可选）", text: optionalText($draft.lemma)).textInputAutocapitalization(.never)
                    TextField("已确认的同根词组标识（可选）", text: optionalText($draft.wordFamily)).textInputAutocapitalization(.never)
                } header: { Text("词条归类") } footer: {
                    Text("只有确认词形关系时才填写原形。同根词填写相同的组标识只建立跳转关联，不合并词条；不确定时留空。")
                }
                Section("来源语境") {
                    TextField("原文例句", text: optionalText($draft.originalSentence), axis: .vertical)
                    TextField("例句翻译", text: optionalText($draft.sentenceTranslation), axis: .vertical)
                    TextField("常见搭配，每行一项", text: $collocations, axis: .vertical)
                }
                SourcePicker(ids: $draft.sourceArticleIds)
            }.navigationTitle(isNew ? "新增词汇" : "编辑词义记录").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            draft.topics = splitTags(topics); draft.collocations = collocations.split(separator: "\n").map(String.init)
                            Task { if await model.perform({ try await model.worker.save(draft, isNew: isNew) }) { dismiss() } }
                        }.disabled(model.busy || TextKey.normalize(draft.expression).isEmpty || TextKey.normalize(draft.meaning).isEmpty || draft.sourceArticleIds.isEmpty)
                    }
                }
        }.interactiveDismissDisabled(model.busy)
    }
}
