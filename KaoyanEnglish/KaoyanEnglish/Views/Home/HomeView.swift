import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @Binding var selectedTab: AppTab
    @State private var importing = false
    @State private var confirmSample = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("KAOYAN ENGLISH").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.teal)
                    Text("让每一次精读，\n成为长期积累。").font(.title2.bold())
                    Text("离线知识库 · 词汇 / 阅读 / 写作").font(.subheadline).foregroundStyle(.secondary)
                    Button { importing = true } label: {
                        Label("导入学习资料", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).disabled(model.busy || !model.ready).accessibilityIdentifier("importMaterials")
                }.padding(.vertical, 8)
            }
            Section("我的积累") {
                HStack(spacing: 0) {
                    metric("词汇", VocabularyGrouping.entries(model.snapshot.vocabulary).count, "character.book.closed", destination: .vocabulary)
                    Divider()
                    metric("模拟题", model.snapshot.questions.count, "doc.text", destination: .questions)
                    Divider()
                    metric("写作表达", model.snapshot.writing.count, "pencil.and.outline", destination: .writing)
                }.padding(.vertical, 8)
            }
            if !model.ready && !model.busy {
                Section { Button("重新打开知识库") { Task { await model.load() } } }
            }
            Section("最近导入") {
                if model.snapshot.history.isEmpty {
                    Text("还没有导入记录。可以先体验内置示例，再导入你的学习资料。").foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.history.prefix(5)) { report in
                    NavigationLink { ImportRecordDetailView(report: report) } label: { ImportHistoryRow(report: report) }
                        .accessibilityIdentifier("recentImport_\(report.packageId)")
                }
                if !model.snapshot.history.isEmpty {
                    NavigationLink("全部导入记录（\(model.snapshot.history.count)）") { ImportHistoryView() }
                }
            }
            Section("数据管理") {
                Button { Task { await model.export(backup: true) } } label: { Label("创建完整备份", systemImage: "externaldrive") }
                Button { Task { await model.export(backup: false) } } label: { Label("导出学习资料 JSON", systemImage: "square.and.arrow.up") }
                Button {
                    Task { if await model.perform({ try await model.worker.check() }) { model.message = "三个数据库及跨库文章关联均通过完整性检查。" } }
                } label: { Label("检查数据完整性", systemImage: "checkmark.shield") }
                Button { confirmSample = true } label: { Label("导入内置示例", systemImage: "book.closed") }.accessibilityIdentifier("importSample")
                NavigationLink { ImportHelpView() } label: { Label("资料格式与备份说明", systemImage: "questionmark.circle") }
            }.disabled(model.busy || !model.ready)
            Section { Text("资料默认只保存在本机。本应用不调用 AI、不读取 ChatGPT 聊天记录，也不自动上传数据。").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("学习空间")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.importFiles(urls) }
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .confirmationDialog("将导入 3 个词汇、2 道模拟题和 1 条写作表达。", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("导入示例") { Task { await model.importSample() } }
        }
    }
    private func metric(_ title: String, _ value: Int, _ icon: String, destination: AppTab) -> some View {
        Button { selectedTab = destination } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.teal)
                Text(value.formatted()).font(.title2.bold()).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("打开\(title)，\(value)项")
            .accessibilityIdentifier("homeMetric_\(title)")
    }
}
func displayDate(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
}
