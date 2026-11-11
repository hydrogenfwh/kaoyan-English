# Kaoyan English · 第一阶段 MVP

原生 SwiftUI 考研英语个人知识库。iOS 17+，默认离线运行，系统 SQLite，无第三方运行时依赖、账号、服务器、AI 接口或自动上传。

## 打开与运行

项目根目录：`/Users/bytedance/Desktop/kaoyan/kaoyan-English/KaoyanEnglish`

工程：`KaoyanEnglish.xcodeproj`，共享 Scheme：`KaoyanEnglish`。

1. 用 Xcode 打开工程，选择 iPhone Simulator，点击 Run。
2. 首页选择“导入内置示例”，确认后得到 3 个词汇记录、2 道原创模拟题、1 条写作表达和 2 篇文章。
3. 在“原文”按分类浏览原始文章，打开后查看正文及关联词汇、写作表达和题目；在词汇库收藏、编辑、搜索或筛选；在题库打开改编文章，选择阅读单选题并提交；在写作库查看跨主题表达。
4. 导入自己的资料时，点击“导入学习资料”，在文件选择器中选择一个或多个 JSON。也可从其他 App 打开 JSON。
5. 真机运行需在 Xcode Signing & Capabilities 选择自己的开发团队；模拟器构建不需要开发者账号。

最低部署版本为 iOS 17。本机只有 iOS 26.5 Simulator runtime；未在 iOS 17 runtime 或实体 iPhone 上验证。

## 本阶段功能

- 五个原生 Tab：首页、原文、词汇库、模拟题库、写作库，支持系统深色模式和动态字体。
- 三个 SQLite 文件、稳定 UUID、原文与改编文关系、多来源追踪。
- 原文目录只列 `kind=original` 文章，支持分类筛选，无分类显示“未分类”。原文详情展示正文，并汇总直接关联及改编文关联的词汇、写作表达和题目；题目按 ID 去重，改编文题目标注对应文章。原文页面没有关联内容时逐项显示空状态。
- 题库只列改编文章作为答题入口；原始文章及其关联数据仍保留在数据库中，可继续从“原文”访问。
- 首页“词汇 / 模拟题 / 写作表达”三个入口分别切换到对应 Tab；“最近导入”为单栏列表，每条记录可进入详情。新版导入逐项保存来源、文章、词汇、题目和表达的加入/合并结果；旧记录没有逐项数据时明确显示“不可用”，不做推测。
- 词汇按原形归并展示：受控屈折表与显式 `lemma` 把单复数、时态等形式归入同一词条，同时合并大小写和空白差异；不同词性、不同措辞的释义分别展示，各来源文章、原文词形和例句逐条保留。完全相同的释义去重；措辞不同的释义不进行语义合并。同根词作为独立词条保留，仅在显式词组标识或已确认词族内互链，可从详情页跳转。
- 词汇支持搜索原形、原文词形和中英文释义，表达支持中英文搜索，二者均支持主题筛选、收藏；词汇难度筛选；默认十类主题，可在编辑页新增主题。
- 导入后可手工新增词汇/表达（必须选择已有文章），编辑和删除；文章可编辑正文/标题/主题；题目提交后可编辑，避免通过编辑入口提前泄露答案。
- 文章、题目、来源、词汇和表达的新增由 JSON 导入服务处理；服务层提供主要知识实体的更新/删除接口。引用中的文章不能被误删。
- 阅读理解单选题：独立选项状态、保存提交、正确性判断、解析/原文依据/干扰项分析、重新练习、答题记录持久化。
- 其他七种题型已具备模型与展示，可文本作答后对照参考答案自评，未实现专门的排序/拖拽/作文评分交互。
- 完整备份、JSON 内容导出、成功导入历史与逐项导入明细、SQLite/外键/跨库引用检查。

## 项目结构

```text
KaoyanEnglish.xcodeproj/             Xcode 工程及共享 Scheme
KaoyanEnglish/
  App/                              入口、Tab、Info.plist
  Models/                           Codable 模型、答题状态、原文导航、词汇归并
  Views/                            首页、原文、词汇、题库、写作、导入、公共视图
  ViewModels/                       主线程 UI 状态和后台串行 actor
  Services/Database/                SQLite 封装、迁移、CRUD、跨库关联
  Services/Import/                  解码、字段与引用完整校验
  Services/Backup/                  SQLite Backup API、备份验证与恢复
  Utilities/                        JSON 编码、归一化、时间、错误
  Resources/                        Schema 和完整示例
KaoyanEnglishTests/                 XCTest
Support/                            无第三方依赖的工程/资源生成器及测试脚本
Package.swift                       独立运行核心 XCTest
Build/                              本机日志、派生数据和隔离模拟器（不应提交）
tmp/                                本地测试临时数据库（不应提交）
FILE_MANIFEST.txt                   实际交付源码文件清单
```

额外提供 Swift Package，是为了在没有可用模拟器时也能真实运行持久化和导入测试。App 与 Package 使用同一份核心代码，不维护两套实现。Apple SDK 已提供 SQLite3 模块，不再增加自定义 SQLite 模块。

## JSON 格式

- Schema：`KaoyanEnglish/Resources/learning-package.schema.json`
- 完整示例：`KaoyanEnglish/Resources/sample-package.json`
- 当前版本：`schema_version: "1.0"`，UTF-8，支持中文与英文。
- 顶层必填：`schema_version`、`package_id`、`created_at`、`sources`、`articles`、`vocabulary`、`questions`、`writing_expressions`。无内容的数组写 `[]`。
- 包和实体 ID 均为小写 UUID，生成后保持稳定；同包内实体 ID 全局唯一，不能跨实体类型重用。
- `created_at` 等时间使用带时区的 ISO-8601；可选实体时间缺失时采用导入时间。
- 可选字符串/数组可省略或为 `null`。缺失的难度为未提供，主题为空；难度取值 1–5。主题不限制在默认十类。
- 未知附加字段忽略，以保留扩展空间；未知 schema_version 明确拒绝，未来在版本分发层加入转换器。
- 单个文件最大 20 MB，最多 50,000 个实体。JSON Schema 描述形状；应用额外校验 ID、跨实体引用、日期、答案、唯一性及冲突。

### 实体字段

| 数组 | 必填字段 | 可选字段 |
| --- | --- | --- |
| sources | id, title | url（http/https）, note |
| articles | id, title, body, kind（original/adapted） | source_id, original_article_id, theme, created_at |
| vocabulary | id, expression, meaning, source_article_ids | lemma, part_of_speech, word_family, origin_id, phonetic, english_definition, original_sentence, sentence_translation, collocations, uncommon_meaning, difficulty, topics, writing_value, created_at, updated_at |
| questions | id, article_id, type, stem, correct_answer, explanation, provenance | options（对象数组：id/text）, evidence, distractor_analysis（选项 ID→分析）, tested_skill, difficulty, created_at |
| writing_expressions | id, expression, meaning, source_article_ids | topics, expression_type, context, original_sentence, essay_sentence, translation, alternatives, usage_notes, created_at |

`adapted` 文章必须用 `original_article_id` 指向另一篇 `original` 文章；原始文章不能再指向上游文章。词汇和表达至少关联一篇文章；来源引用可以指向同一文件、同批次前面的文件或库中已有记录。不能引用尚未导入的后续包；按原文包在前、衍生包在后的顺序导入，或合并成单个包。

题型标识：`reading_single_choice`、`cloze`、`seven_choose_five`、`ordering`、`heading_match`、`translation`、`practical_writing`、`essay_writing`。所有题目必须含 `provenance: "original_simulation"`，UI 统一显示“原创模拟题”。阅读单选题至少两个选项，选项 ID 唯一，`correct_answer` 必须等于其中一个选项 ID，例如 `"C"`。

### 可以交给 ChatGPT 的生成要求

> 请按随附 learning-package.schema.json 生成 UTF-8 JSON 学习资料。使用 schema_version 1.0，为 package 和所有实体生成并保持小写 UUID；保留 sources、原文 articles、改编文及 original_article_id 关系。词汇/表达关联 source_article_ids，同词不同义分别列出。每个词汇尽量提供 phonetic 音标和 english_definition 英文释义，结合上下文给出准确含义。所有题目为原创模拟题，provenance 写 original_simulation。阅读题 correct_answer 写选项 ID，解释与证据分字段保存。只输出一个可解析的 JSON 文件，不使用 Markdown 围栏，不编造来源网址。内容不确定的可选字段省略。

应用只读取用户选择的文件，不直接访问 ChatGPT 私有聊天记录。

## 去重与导入安全

- 单个包先解码并完成字段、文章关系、选项、全局 ID 和内容冲突校验，再写入。
- 多文件导入由一个外层事务包裹，各包依次验证；后续文件失败时，前面文件在事务中的写入也全部回滚。只有整个批次成功才发布 UI 结果。
- package_id 是不可变身份：首次导入保存规范化 JSON 的 SHA-256；相同 ID/相同内容重复导入跳过，内容改变则拒绝并要求使用新 ID。重新导入不会恢复用户已经删除的词条。
- 词汇以“原形/显式 `lemma` + 释义 + 词性 + 完整语境”为去重边界：完全相同的记录只保留一份并记录别名；同一词义但来源文章或例句不同，保存为独立语境记录，展示层再归入同一词条。表达按“归一化表达 + 实际含义”；题目按“文章 ID + 题型 + 归一化题干”。归一化做 Unicode 兼容组合、大小写/宽度折叠、空白折叠；不做词干提取或语义推断。
- 同词不同义可以并存。完全相同的词汇记录只合并别名；词义相同但语境不同的导入会新增语境记录，保留各自的来源、例句、音标和释义，不覆盖首次内容。表达仍合并来源文章与主题。重复题目保留首次内容和已有答题记录。
- 每条成功导入记录保存汇总数量，并为新版本导入保存逐项明细（最多 200 条，超出部分以截断提示说明）。旧版本产生的导入记录没有逐项数据，详情页显示“不可用”，不根据当前词库反推。
- 相同实体 ID 指向不同去重身份时拒绝覆盖。修改已有学习资料请用编辑功能；新内容使用新的实体 UUID。
- 失败以用户可读错误报告展示；不记录为成功导入，不留下半成品。成功结果包含新增三类数量、去重数量、失败数量（全有或全无模式下为 0）、时间；重复包显示首次导入时间。

### 三库事务与崩溃恢复

App 使用一条 SQLite 连接，将 `questions.sqlite` 作为磁盘主库，以 ATTACH 挂接 `vocabulary.sqlite` 和 `writing.sqlite`。三个文件都强制并验证 `journal_mode=DELETE`，`synchronous=FULL`，开启外键检查；导入用 `BEGIN IMMEDIATE`，嵌套批量导入用 SAVEPOINT。

这里依靠的是满足前提的 SQLite ATTACH 回滚日志/超级日志协议，**不是三个独立连接各自 COMMIT**，也不使用 WAL 跨库事务。异常执行 ROLLBACK；进程中断后，SQLite 在再次打开时处理热日志，随后应用执行完整性与跨库引用检查。不应在其他进程中同时直接编辑这些数据库，或切换 WAL。已测试“写入所有三个库后抛错”的整批回滚；未做断电/文件系统故障注入，因此不宣称经过硬件级故障验证。

## SQLite 表结构

文件位于 App 沙盒 `Library/Application Support/KaoyanEnglish/`，真实路径由 FileManager 获取。iOS 文件保护使用 `completeUntilFirstUserAuthentication`，不自行上传。

三个文件均以 `PRAGMA user_version=2` 管理结构版本。迁移入口在 `DatabaseSchema.migrate`：首次从 v1 升级时，在单事务中把 `vocabulary.sqlite` 的旧词汇表、别名、文章关联和主题复制到 v2 的 `records` 系列表，旧表按原样保留为迁移归档，不删除任何行；遇到更高版本立即报错，不降级、不重建空库。

为兼顾稳定字段与未来扩展，每个实体使用**索引列 + 完整 Codable JSON payload**：音标、例句、释义细节、题目答案、解析、写作语境等完整字段均保存在 payload；常用身份、检索关联、主题、收藏单独建列/表。payload 使用上表字段命名，不是丢弃未建立独立 SQL 列的内容。

| 文件 | 表 | 列 / 约束 |
| --- | --- | --- |
| questions.sqlite | sources | id PK, payload NOT NULL |
| questions.sqlite | articles | id PK, title, body, kind, source_id FK→sources, original_article_id 延迟 FK→articles, payload |
| questions.sqlite | questions | id PK, article_id FK→articles, type, stem, dedup_key UNIQUE, payload |
| questions.sqlite | question_aliases | alias_id PK, entity_id FK→questions，级联删除 |
| questions.sqlite | import_history | package_id PK, digest, imported_at, payload（ImportReport） |
| questions.sqlite | attempts | id PK, question_id FK→questions，级联删除, payload（答案/当时判断/时间） |
| vocabulary.sqlite | records | 当前读写表：id PK, expression, meaning, difficulty, dedup_key（非唯一）, favorite 0/1 CHECK, payload |
| vocabulary.sqlite | record_aliases | alias_id PK, entity_id FK→records，级联删除 |
| vocabulary.sqlite | record_article_links | entity_id FK→records，article_id；联合 PK |
| vocabulary.sqlite | record_topics | entity_id FK→records，topic；联合 PK，topic 索引 |
| vocabulary.sqlite | vocabulary / aliases / article_links / topics | v1 迁移归档：id, expression, meaning, difficulty, dedup_key UNIQUE, favorite, payload；只读保留，不再写入 |
| writing.sqlite | expressions | id PK, expression, meaning, difficulty（预留，当前不用）, dedup_key UNIQUE, favorite 0/1 CHECK, payload |
| writing.sqlite | aliases | alias_id PK, entity_id FK→expressions，级联删除 |
| writing.sqlite | article_links | entity_id FK→expressions，article_id；联合 PK |
| writing.sqlite | topics | entity_id FK→expressions，topic；联合 PK，topic 索引 |

外键只约束同一文件内的表。`record_article_links.article_id` 与 `article_links.article_id` 的跨文件存在性由服务层在导入、编辑、删除和完整性检查时验证。来源文章的全局 ID 始终来自 questions.sqlite 的 articles；不是各库分别分配自增 ID。`records.dedup_key` 不设唯一约束，因为同一词义允许保留多条不同语境的记录；完全相同的记录由导入服务合并别名。

## 备份、导出与恢复

首页“创建完整备份”使用 **SQLite Backup API**，不直接复制正在写入的数据库。串行锁排除本应用写入，读取事务固定快照；分别检查生成的数据库，将三个完整文件和各自 SHA-256 包装为 `.kaoyanbackup`（版本 1 的 JSON 容器，文件内容 Base64 编码）。收藏、答题记录、别名和导入历史都包含在内。临时文件仅存在于本次新建目录，完成或失败后清理。

“导出学习资料 JSON”仅导出学习内容，产生新 package_id，可再次导入；不包含收藏、答题记录或历史。不要把内容导出当作完整备份。

两种文件先生成在 App 的 Application Support/KaoyanEnglish/Exports，再由用户选择“保存到文件或分享”。仅留在 App 内的导出副本无法防止卸载丢失，需另存到 App 外。

基础恢复接口：

```swift
let data = try Data(contentsOf: backupURL)
try BackupService.restore(data, toNewDirectory: newDirectory)
let restored = try LibraryStore(directory: newDirectory)
try restored.checkIntegrity()
```

恢复先验证版本、白名单文件名及校验和，**只允许新目录**，绝不覆盖正在使用的数据库。实际恢复已有 App 数据的交互与切换流程尚未实现，不能将 .kaoyanbackup 当作普通学习 JSON 导入。恢复接口已经通过 XCTest 验证；下一阶段应提供用户可操作的完整恢复界面。

## 验证

第一阶段（2026-11-10）在 macOS 26.5、Xcode 26.6（17F113）、Swift 6.3.3 下编译并执行 22 项 macOS 核心 XCTest，构建 iOS App 与 iOS XCTest target，并做过模拟器启动与数据库检查，详见 `VALIDATION.md`。

本轮改动（2026-11-12）所在环境只有 Command Line Tools，没有 Xcode / XCTest，因此：

- `swift build` 编译 `KaoyanCore` 通过。
- 用与核心库同模块编译的临时 harness 覆盖导入去重、词汇归并、原文与改编题关联、答题隐藏、导出、备份恢复和 v1→v2 迁移，全部通过；细节与命令见 `VALIDATION.md`。
- `Support/test.sh` 依赖 `xcodebuild`，当前环境会因缺少 XCTest 模块失败；本轮未重新执行 XCTest，也未重新构建 iOS App。

运行 `./Support/test.sh` 会先执行 macOS 核心 XCTest，再编译 iOS App 和 iOS XCTest target；脚本不自动启动模拟器，也不安装依赖。测试使用每次新建的独立临时目录，完成后仅删除自己的目录；Swift Package 测试通过 `KAOYAN_TEST_ROOT` 定位到本项目 tmp，绝不使用正式 Application Support 数据库。完整 Xcode 环境下的测试和模拟器验证详见 `VALIDATION.md`。主要覆盖：数据库初始化、读写/编辑/删除、同词不同义、语义键去重、多来源、跨主题、关联约束、JSON 导入/导出、重复 package_id、错误数据拒绝、跨库写入失败回滚、多文件整体回滚、完整备份与恢复/防覆盖/篡改拒绝、重启持久化、答题答案隐藏、未知版本拒绝。

构建时可能出现 Xcode 系统 XCTest 框架“已签名不剥离”以及无 AppIntents 的元数据提示；不影响构建。测试执行情况以日志为准，不把 build-for-testing 当作已在 iPhone Simulator 执行 XCTest。

## 已知限制与下一阶段

- 第一阶段没有 App 内完整备份恢复流程，只有经测试的安全恢复接口；优先补充恢复预览、确认和切换。
- 未在真机、iOS 17 runtime、真实 iCloud Drive/其他 App 分享场景中逐项验收；当前环境具备对应原生入口，但实际文件提供方行为需设备验证。
- 非阅读单选题仅展示/文本作答/自评，不自动评分。没有间隔重复、OCR 或 AI 自动处理。
- 本地搜索在后台载入快照后内存筛选，适合个人 MVP；大量数据应加入分页、FTS 和性能基准，仍保持三库与稳定 ID。
- 词汇按原形归并依赖受控屈折表、显式 `lemma` 和已确认同根词组标识；未收录且没有显式 `lemma` 的词形不会靠后缀或拼写猜测自动合并，可在编辑页补全。同根词只做跳转关联，不合并词条。
- 词汇“合并”是展示层聚合，不物理改写旧记录：收藏、编辑、删除仍按具体语境记录执行；同一词条任一条收藏即显示为收藏。不同措辞的释义不会自动做语义合并。
- 新版导入记录保存逐项明细，最多 200 条；旧版本生成的导入记录只有汇总数量，详情页明确显示逐项数据不可用。
- 第一版数据库无历史版本可迁移样本；已提供 v1→v2 迁移和拒绝未来版本测试，但不能宣称已验证所有真实升级样本。
- 全量备份在内存中打包，超大知识库应改为流式归档；导出副本暂不自动清理。App 图标暂使用系统默认占位，发布前补充正式图标和真机验收。

不包含登录、云服务、付费、社区、AI API、OCR、复杂动画或自动读取聊天记录。

词汇详情将音标直接放在单词下方，英文释义放在中文释义上方；旧数据缺少音标或英文释义时显示“未提供”或直接省略，不编造内容。`uncommon_meaning` 和 `writing_value` 仍保留在数据模型与导入导出中，但不再在词汇界面展示或编辑。应用不包含牛津词典词库，也不联网自动查询；重新导入重复词条不会覆盖原内容，如需补全已有记录请在编辑页填写。
