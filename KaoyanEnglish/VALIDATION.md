# 实际验证记录

日期：2026-11-10（Asia/Shanghai）。只在本项目内创建源码、测试数据、构建日志和隔离模拟器设备。

| 验证 | 实际结果 | 证据 |
| --- | --- | --- |
| 最小工程 iOS Simulator 构建 | 通过 | Build/initial-build.log |
| 最终核心 XCTest（macOS，实际执行） | **22 项，0 失败** | Build/final-validation.log |
| 示例内容最后校正后重新导入/重复导入测试 | 1 项通过 | Build/sample-validation.log |
| 最终 iOS App + iOS XCTest target 编译 | **TEST BUILD SUCCEEDED** | Build/final-ios-build.log |
| 隔离 iPhone 17 Pro / iOS 26.5 安装、启动 | 成功启动应用 | simctl launch 返回进程 ID，首页截图 |
| 浅色 / 深色首页渲染 | 已查看截图，内容和四个 Tab 可见 | Build/home-light.png、Build/home-dark.png |
| App 运行后的三个数据库文件检查 | 全部 integrity_check=ok、user_version=1、journal_mode=delete | Build/simulator-database-check.json |
| iOS Simulator 内执行 XCTest | **未执行**，只编译了 iOS 测试目标；实际 22 项运行于 macOS 的同一核心源码 | 不将 build-for-testing 当成已执行测试 |
| 真机 / iOS 17 runtime / 真实 iCloud 或其他 App 文件提供方 | 未验证 | 当前无本轮设备验收 |
| 全界面点按、VoiceOver、大字号、横屏自动化 | 未执行完整 UI 自动化 | 仅启动与首页浅/深色视觉检查 |
| 模拟硬断电、磁盘损坏 | 未做故障注入 | 已覆盖事务中途抛错、重开库、校验和篡改拒绝 |

## 已执行的 22 项 XCTest

1. 数据库初始化和三个文件完整性。
2. 词汇新增读取、同词不同义分别保存。
3. 文章题目关联、写作跨主题、阻止删除被引用文章。
4. 关闭重开后的内容与收藏持久化。
5. 词汇编辑保留收藏、删除及约束清理。
6. JSON 导入和内容导出往返。
7. 重复 package_id 跳过、不重新创建已删除词汇。
8. 词汇归一化去重、多个来源合并、收藏和已有字段保留。
9. 错误 JSON、必填字段缺失、悬空引用、答案不存在时拒绝且原库不变。
10. 三库均写入之后注入失败，所有内容与导入历史整体回滚，重开可重试。
11. 同一 package_id 内容改变、实体 ID 指向不同词义时拒绝覆盖。
12. 可选字段缺失处理、未知 JSON Schema 版本拒绝。
13. 题目与写作表达语义键去重。
14. SQLite Backup API 完整备份和恢复，保留学习记录；禁止覆盖恢复目录，拒绝错误校验和。
15. 答案/解析/依据/干扰项在提交前隐藏，持久化成功后显示；重置再次隐藏。
16. 提交持久化失败时保持答案隐藏。
17. 内置完整示例成功导入、重复导入与原文/改编文关系。
18. 多文件后续包错误导致前面包整体回滚。
19. 多文件后续包可引用前面包的文章。
20. 全局 ID 类型冲突、缺少原文关系的改编文章拒绝。
21. 高于应用支持的数据库版本拒绝打开、不降级。
22. 写作表达、题目、文章编辑和删除流程。

## 运行过程中的问题与处理

- 初次 Swift Package 编译遇到自定义 SQLite3 模块与 Apple SDK 自带模块重名，已删除自定义模块声明，直接使用系统 SQLite3，后续构建/测试通过。
- 初次编译还修正了一个 Swift 可抛错布尔表达式；最终日志无项目编译错误。
- 将隔离模拟器放在项目所在的“文稿”目录，引发 macOS 文稿权限请求。向用户解释后，用户明确回复“允许了”。未改动已有模拟器设备。
- 第一次模拟器启动失败；授权后再次启动，首次系统数据迁移报告错误，但设备随后处于 Booted，App 安装、启动、两种外观截图和数据库检查均成功。保留该环境事实，不据此宣称完整系统环境或全部 UI 流程已通过验收。
- 最终示例校正只补充了词汇例句对应的原文，并单独重跑示例导入测试、重新构建 iOS target；未改变运行逻辑。

隔离模拟器名称：KaoyanEnglish-MVP-Isolated；设备数据位于 Build/SimulatorDevices/。验证结束关闭该隔离设备，不删除或修改用户原有设备。

## 交付前确认

- 未安装第三方全局依赖，未配置开发者账号或签名证书。
- 未连接 AI/付费 API，没有网络上传代码。
- 测试不使用 App 正式数据库；模拟器 App 数据也位于项目内的独立设备沙盒。
- 未修改目标文件夹外的其他项目；工作区 Git 状态仅新增 KaoyanEnglish/。
- 第一阶段未运行 git commit 或推送；源码可直接审阅。

---

# 2026-11-12 功能调整验证记录

本阶段完成原文入口、首页入口与导入明细、词汇归并展示与同根词、导入报告逐项记录，并更新文档。

## 环境事实

- 本轮所在机器只有 Command Line Tools：`xcode-select -p` 为 `/Library/Developer/CommandLineTools`，不存在 `/Applications/Xcode.app`，`xcodebuild -version` 报错要求安装 Xcode。
- 因此 `Support/test.sh` 在 `swift test` 阶段失败：`no such module 'XCTest'`。本轮**未**执行 XCTest，也**未**重新编译 iOS App。
- 未安装任何第三方依赖，未联网下载包。

## 实际执行的验证

| 验证 | 实际结果 | 说明 |
| --- | --- | --- |
| `swift build`（KaoyanCore） | 通过 | 13 个核心源文件编译成功 |
| 同模块临时 harness | **46 项检查全部通过**（`ALL CORE CHECKS PASSED`） | 用 `swiftc` 把 Models/Services/Utilities 与 `tmp/main.swift` 一起编译，链接系统 `-lsqlite3`，数据目录指向 `tmp/` |
| `Support/test.sh` | 未通过（环境限制） | `no such module 'XCTest'`，非代码错误 |

harness 通过 `swiftc -o tmp/verify-core $(find KaoyanEnglish/Models KaoyanEnglish/Services KaoyanEnglish/Utilities -name '*.swift') tmp/main.swift -lsqlite3` 编译，`KAOYAN_TEST_ROOT=tmp ./tmp/verify-core` 运行。`tmp/` 已被 `.gitignore` 忽略。

## harness 覆盖内容

1. 导入计数：4 个新词义、2 条同义不同语境、2 道题、1 条写作表达。
2. 导入报告逐项明细：6 条词汇条目、2 条 `contextAdded`，并可从导入历史按 packageId 取回。
3. 词汇归并：study/studies/studied 四条记录归入一个词条、两个词义；保留具体词形、两篇原文来源和四条例句。
4. 同根词：reflect 与 reflection 通过显式 `word_family` 关联但不合并。
5. 收藏：任意一条记录收藏后整个词条显示为收藏。
6. 原文目录：只列 `kind=original`；空白主题显示“未分类”；分类筛选正确；仅出现在改编文上的主题不进入分类列表。
7. 原文关联题目：同时包含直接题和改编文题目，重复题目去重；改编关系可从原文反查。
8. 题库只列改编文；答题提交前答案与解析为空，持久化成功后显示，答题记录写入数据库。
9. 旧导入报告 JSON 解码后 `items == nil`，详情页按“不可用”展示。
10. 相同语境重复导入合并别名、不新增记录；同一词义不同语境新增独立记录并标记 `contextAdded`。
11. 导出保留全部 7 条语境记录与 7 条例句。
12. 备份恢复保留全部词汇记录、答题记录和 3 条导入历史。
13. 删除单条词义记录后词条仍有 3 条记录，收藏状态保留。
14. v1→v2 迁移：词汇、收藏、别名全部保留，`user_version=2`，旧 `vocabulary` 表作为归档保留。

## 本阶段发现并修正的问题

- 旧测试 `testDuplicateWordMergesMultipleSourcesAndPreservesLearning` 期望不同来源语境合并为一条记录，与新需求“同一释义来自多篇原文时保留各自来源及例句”冲突。已重写为 `testDuplicateWordKeepsSeparateContextsAndLearningState`，期望保留两条记录、同一词条同一词义、收藏保留、首条记录不被覆盖。第一阶段记录的“22 项”仍是对当时代码的真实结果，但第 8 项描述的行为已按新语义调整。
- 新增导入明细相关测试 3 项（历史明细解码、outcome 区分、200 条上限截断），因环境限制未执行，仅由同模块 harness 覆盖了前两项的数据层行为。

## 本轮未验证

- 未编译 iOS App 与 SwiftUI 视图（原文页、词汇详情、导入详情、首页入口）；这些改动只做了静态审阅。
- 未运行 XCTest、未启动模拟器、未做真机或 iOS 17 runtime 验收。
- 未做无障碍、大字号、横屏与完整点按流程验证。
- 备份恢复的 App 内交互入口仍未实现，与第一阶段限制相同。

## 提交与推送

本轮改动提交到 `main` 并推送到 `git@github.com:hydrogenfwh/kaoyan-English.git`；具体提交哈希与推送结果见最终回复及 `git log`。构建产物、`tmp/` harness 与临时数据库不纳入提交。
