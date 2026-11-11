import SwiftUI

@main
struct KaoyanEnglishApp: App {
    @StateObject private var model = LibraryViewModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).task { await model.load() }
                .onOpenURL { url in Task { await model.importFiles([url]) } }
        }
    }
}
struct RootView: View {
    @EnvironmentObject private var model: LibraryViewModel
    @State private var selectedTab: AppTab = .home
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView(selectedTab: $selectedTab) }.tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
            NavigationStack { OriginalArticleListView() }.tabItem { Label("原文", systemImage: "book.pages") }.tag(AppTab.originals)
            NavigationStack { VocabularyListView() }.tabItem { Label("词汇库", systemImage: "character.book.closed") }.tag(AppTab.vocabulary)
            NavigationStack { QuestionLibraryView() }.tabItem { Label("题库", systemImage: "doc.text") }.tag(AppTab.questions)
            NavigationStack { WritingListView() }.tabItem { Label("写作库", systemImage: "pencil.and.outline") }.tag(AppTab.writing)
        }
        .tint(.teal)
        .overlay(alignment: .top) {
            if model.busy { ProgressView("正在处理…").padding(10).background(.regularMaterial, in: Capsule()).padding(.top, 8).accessibilityIdentifier("busyIndicator") }
        }
        .alert("操作结果", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .sheet(isPresented: $model.showImportReport) { ImportReportView(reports: model.reports) }
        .sheet(item: $model.exportItem) { item in
            NavigationStack {
                VStack(spacing: 24) {
                    Image(systemName: item.isBackup ? "externaldrive.badge.checkmark" : "doc.badge.arrow.up").font(.system(size: 56)).foregroundStyle(.teal)
                    Text(item.isBackup ? "完整备份已生成" : "学习资料已导出").font(.title2.bold())
                    Text(item.isBackup ? "包含三个数据库、收藏、答题记录和导入历史。请存入“文件”App，并保留在 App 外。" : "JSON 包含文章、词汇、题目和写作表达。收藏、答题和导入历史请通过完整备份保存。")
                        .foregroundStyle(.secondary)
                    ShareLink(item: item.url) { Label("保存到文件或分享", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    Text("仅在你选择保存或分享位置后，文件才会交给该位置。").font(.footnote).foregroundStyle(.secondary)
                }.padding(28).navigationTitle("导出")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { model.exportItem = nil } } }
            }.presentationDetents([.medium, .large])
        }
    }
}
