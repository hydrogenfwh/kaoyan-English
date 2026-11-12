# Kaoyan English · 考研英语个人知识库

原生 SwiftUI 考研英语知识库。iOS 17+，默认离线运行，使用系统 SQLite 三个数据库，无第三方运行时依赖、账号、服务器、AI 接口或自动上传。

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [KaoyanEnglish/README.md](KaoyanEnglish/README.md) | 功能说明、打开与运行、JSON 格式、去重与导入规则、SQLite 表结构、备份恢复、已知限制 |
| [KaoyanEnglish/VALIDATION.md](KaoyanEnglish/VALIDATION.md) | 实际验证记录、环境事实、测试覆盖与未验证项 |
| [KaoyanEnglish/FILE_MANIFEST.txt](KaoyanEnglish/FILE_MANIFEST.txt) | 交付源码与文档清单 |

## 快速开始

1. 用 Xcode 打开 [KaoyanEnglish/KaoyanEnglish.xcodeproj](KaoyanEnglish/KaoyanEnglish.xcodeproj)，选择 iPhone Simulator 运行。
2. 首页选择“导入内置示例”，得到示例文章、词汇、题目和写作表达。
3. 通过底部“首页 / 原文 / 词汇库 / 题库 / 写作库”进入各功能；导入自己的资料时选择 JSON 文件。

## 目录结构

```text
KaoyanEnglish/            工程目录（源码、Xcode 工程、测试、Support 脚本与详细文档）
KaoyanEnglish/KaoyanEnglish/       App 源码：App、Models、Views、ViewModels、Services、Resources
KaoyanEnglish/KaoyanEnglishTests/  XCTest
KaoyanEnglish/Support/             test.sh 与无第三方依赖的资源/工程生成脚本
```

完整功能、数据格式和验证说明以 [KaoyanEnglish/README.md](KaoyanEnglish/README.md) 为准；本文件仅作为仓库入口索引，不重复维护细节。
