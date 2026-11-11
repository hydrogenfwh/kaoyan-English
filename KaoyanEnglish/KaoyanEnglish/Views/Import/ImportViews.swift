import SwiftUI

struct ImportReportView: View {
    @Environment(\.dismiss) private var dismiss
    let reports: [ImportReport]
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("导入已完成", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.teal)
                    Text("本批次共 \(reports.count) 个资料包。重复内容保留原有学习记录，新增来源会合并。").foregroundStyle(.secondary)
                    Text("逐项明细已保存，可在首页“最近导入”中查看。").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(reports.enumerated()), id: \.offset) { _, report in
                    Section(report.alreadyImported ? "已导入过，安全跳过" : "新增资料") {
                        LabeledContent("新增词汇", value: "\(report.vocabularyAdded)")
                        LabeledContent("新增题目", value: "\(report.questionsAdded)")
                        LabeledContent("新增写作表达", value: "\(report.writingAdded)")
                        LabeledContent("去重数量", value: "\(report.duplicates)")
                        LabeledContent("失败数量", value: "\(report.failed)")
                        LabeledContent(report.alreadyImported ? "首次导入时间" : "导入时间", value: displayDate(report.importedAt))
                    }
                }
            }.navigationTitle("导入结果")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
struct ImportHistoryView: View {
    @EnvironmentObject private var model: LibraryViewModel
    var body: some View {
        List(model.snapshot.history) { report in
            NavigationLink { ImportRecordDetailView(report: report) } label: { ImportHistoryRow(report: report) }
        }.navigationTitle("导入历史")
    }
}

struct ImportHistoryRow: View {
    let report: ImportReport
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayDate(report.importedAt)).font(.subheadline.bold())
            Text("词汇 +\(report.vocabularyAdded) · 题目 +\(report.questionsAdded) · 表达 +\(report.writingAdded)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}

struct ImportRecordDetailView: View {
    let report: ImportReport
    var body: some View {
        List {
            Section("已保存的导入信息") {
                LabeledContent("导入时间", value: displayDate(report.importedAt))
                LabeledContent("新增词汇记录", value: "\(report.vocabularyAdded)")
                LabeledContent("新增题目", value: "\(report.questionsAdded)")
                LabeledContent("新增写作表达", value: "\(report.writingAdded)")
                LabeledContent("去重数量", value: "\(report.duplicates)")
                LabeledContent("失败数量", value: "\(report.failed)")
            }
            Section("资料包 ID") { Text(report.packageId).font(.caption.monospaced()).textSelection(.enabled) }
            Section(report.items.map { "条目明细（\($0.count)）" } ?? "条目明细") {
                if let items = report.items {
                    if items.isEmpty {
                        Text("本次导入没有新增或合并的条目。").foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(item.kind.label).font(.caption.bold()).foregroundStyle(.teal)
                                Text(item.outcome.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.title).font(.subheadline)
                            OptionalText(item.detail)
                        }.padding(.vertical, 3)
                    }
                    if report.itemsTruncated == true {
                        Text("仅保存前 \(ImportReport.maximumItems) 条明细；其余条目以汇总数量为准。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("不可用：此导入记录没有保存逐项清单、文件名或文章数量。")
                        .foregroundStyle(.secondary).accessibilityIdentifier("importItemsUnavailable")
                    Text("上方数量来自当时保存的记录，不根据当前词库或文章反推。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("导入详情").navigationBarTitleDisplayMode(.inline)
    }
}
struct ImportHelpView: View {
    var body: some View {
        List {
            Section("从 ChatGPT 到本地知识库") {
                Text("1. 将项目提供的 JSON Schema 和示例交给 ChatGPT，要求生成 schema_version 为 1.0 的 JSON 文件。")
                Text("2. 检查内容后，将文件保存到 iPhone“文件”或 iCloud Drive。")
                Text("3. 点击首页“导入学习资料”，可一次选择多个 JSON；整个批次成功后才会保存。")
            }
            Section("格式与来源") {
                Text("每个资料包和实体使用稳定的小写 UUID。相同资料包再次导入会跳过；更改内容需使用新的 package_id。词汇按词形与释义共同去重，同词不同义可分别保存。")
                Text("词汇和写作表达必须关联至少一篇文章。改编文章须关联原始文章。所有题目均标记为原创模拟题。")
                Text("可选字段缺失时显示为未提供，难度可为 1–5。每个文件最多 20 MB。格式或关联错误会取消整个批次，不保存半成品。")
            }
            Section("备份与导出") {
                Text("JSON 导出用于学习内容的迁移与再次导入；完整备份另含收藏、答题记录和导入历史。请用分享菜单将完整备份另存到 App 外。")
                Text("卸载 App 会移除本地数据。第一阶段的完整备份恢复由项目中的恢复接口支持，暂未提供 App 内恢复按钮；请保留原始备份文件。")
            }
        }.navigationTitle("使用说明")
    }
}
