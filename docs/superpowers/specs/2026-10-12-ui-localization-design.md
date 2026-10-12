# DigUp Test 界面本地化设计

日期：2026-10-12 · 基线：`d94fad822fb8472552230bd98a96b509ccd7fe37`

状态：**书面设计待审阅，尚未实施。** 已确认聊天方案；本文件获批准后才编写实施计划，计划及执行方式另行确认。本次仅提交设计，不推送、不触发 CI，不操作用户的 Mac。

## 1. 目标、范围与完成标准

让 DigUp Test 的应用界面完整支持英语和简体中文，跟随 macOS 为该应用选择的语言；保留英文回退，为后续语言扩展提供同一资源入口。优先采用系统语言选择，不增加应用内选择器或运行中热切换。语言设置变化后重新启动应用。

本批覆盖菜单、搜索与预览、设置、首次引导、应用自有错误/状态文字、无障碍标签，以及应用提供给 macOS 的权限用途说明。用户文件内容、文件名、路径、代码和搜索输入原样显示；`code:` 前缀、快捷键内部 spec、协议字段和数据库值不翻译。CLI、诊断日志、第三方框架内部界面及其错误原文不要求完整汉化。中文检索与 IME 不属于本批。

独立测试版身份不变：`DigUpTest.app`、`digup-test`、现有 bundle ID、独立设置/索引/模型/临时文件路径和禁用更新策略均保持。品牌名保持英文，不另做品牌重命名；本地化不改写存储内容或触发重新索引。

完成须同时满足：两种语言的自有界面文案覆盖、未支持语言和缺译条目的英文回退、最终打包资源可独立读取、原有隔离回归通过，以及明确区分自动化已验证项和尚待真机验收项。

## 2. 技术选择与资源边界

采用 `.strings` / `.stringsdict` 和应用内轻量 `Localization` 入口，贴合当前 SwiftPM + `build.sh` 手动构建 app 的流程。暂不引入 String Catalog 编译链、新依赖或共享本地化模块。直接只向主 app 复制字符串会使 SwiftPM 单测与产品走不同资源入口；因此采用 SwiftPM 资源 bundle，并显式处理 app 打包位置。

拟新增资源：

- `Sources/DigUpApp/Localization.swift`：资源解析、英文回退及少量带参数的方法。
- `Sources/DigUpApp/Resources/{en,zh-Hans}.lproj/Localizable.strings`。
- 同目录的 `Localizable.stringsdict`：计数和复数模板。
- `Resources/{en,zh-Hans}.lproj/InfoPlist.strings`：主 app 权限用途说明。
- `Tests/DigUpAppTests/LocalizationTests.swift` 及必要的资源/最终包验证脚本。

`Package.swift` 设置 `defaultLocalization: "en"`，只向 `DigUpApp` target 添加资源声明。英文为完整基准表；采用稳定语义 key，如 `search.empty.title`。翻译注释解释参数、场景与长度约束，不将英文句子或 UI 标题用作业务标识。

运行时使用系统提供的首选语言匹配支持列表，不自行用字符串前缀判断所有中文都等于简中。发布范围只有 `en`、`zh-Hans`；例如 `zh-Hans-CN` 应匹配简中，未匹配的语言使用英文。macOS 若提供了其他受支持的次选语言，遵循其匹配结果。主 app 和资源 bundle 的语言声明必须一致。

解析顺序为选中语言条目、英文条目、明确的英文兜底文案。缺译测试验证逐 key 回退，不能假定目录级回退自动涵盖每个 key。发布构建不能裸露内部 key；完整英文表或资源 bundle 缺失应在构建/打包校验阶段失败。测试可注入语言和资源，不修改全局系统语言。

## 3. 界面接入与动态文案

所有自有文案通过同一入口解析。静态和动态文案都需盘点：`Text(variable)`、`Button(variable)`、条件字符串、字符串拼接以及 AppKit 属性不会因新增文件自动完整本地化。SwiftUI 显示解析后的 String，必要时用 `Text(verbatim:)` 明确避免再次解释；AppKit 显式赋值。用户内容始终作为数据参数，不能再次当作本地化 key 或格式串。

主要接入位置：

- **菜单/窗口：** `App.swift`、`StatusMenu.swift`，含标题、暂停/恢复、设置、更新相关自有文字和 tooltip；不启用已禁用的更新功能。
- **搜索/预览：** `SearchPanelView.swift`、`SearchWindow.swift`、`Results.swift`、`Previews.swift`、`Components.swift`，含占位、示例、空状态、分类、结果数、弱匹配、命中原因、播放及无障碍文字。
- **设置/文件夹：** `SettingsWindow.swift`、`AddFolders.swift`、`FolderChoices.swift`、`AppSettings.swift`、`AppController.swift`、`CodeEditors.swift`，含面板提示、删除确认、权限恢复、模型和存储说明。
- **引导/状态：** `Onboarding.swift`、`AppModel.swift`、`ModelDownload.swift`、`Engine.swift`、`PowerPolicy.swift`、`Hotkey.swift`、`Estimates.swift`，含步骤、下载/索引、估算、电源等待、快捷键冲突和失败提示。

动态文字按完整语义句组织，参数可调整顺序。文件、结果、页、行、单元格等计数通过 `.stringsdict` 处理，传入原始数值；英文验证 one/other，简中验证 other。禁止以 `file/files` 分支、类别标题小写或大写转换拼接句子。带多个数量的文案需独立参数，不复用一个已经渲染的英文片段。

数字、百分比、日期、大小和估算时长采用 locale-aware 格式；UI 语言跟随应用语言，区域数值习惯遵循系统区域设置。参数签名需避免格式类型不匹配；覆盖零、单数、复数、大数、小数及含 `%` 的用户路径。媒体时码、代码位置及 URL 参数保留其结构语义。示例里的自然语言可以翻译，`code:` 不变。

应用已知错误提供可操作的本地化说明；未知系统/第三方错误允许附原始诊断，不能承诺其全为中文。不要靠匹配英文错误文本决定行为，也不因 UI 翻译改 helper JSON 协议。读取入口保持不可变、可从现有 `nonisolated`/后台路径安全调用，不新增全局可变语言状态。

两项必须随接入处理的逻辑耦合：

1. `StatusMenu.performItem(titled:)` 和 `DebugHooks` 当前按英文暂停/恢复标题找菜单。改为稳定 action ID；显示标题只负责显示，并验证两种语言调用同一行为。
2. `Hotkey.menuEquivalent` 当前依赖显示值中的 `Space`。本批内部键名、spec 和符号维持原样，只翻译操作说明；不得直接翻译该内部值而破坏快捷键。

## 4. 最终 app 打包与权限说明

当前 `build.sh` 没有复制 SwiftPM 本地化资源。实施时以锁定工具链的实际产物及生成的 resource accessor 为依据，确认唯一的应用资源 bundle 名称；禁止依赖猜测或宽泛复制所有 `.bundle`。

最终布局契约：SwiftPM bundle 完整置于 `DigUpTest.app/Contents/Resources/`，内部语言目录和 Info.plist 均保留。`Localization` 在打包 app 中显式定位该 bundle，开发/单测使用 `Bundle.module`；打包运行不得偷偷退回开发机的 `.build` 绝对路径。该边界必须由搬离仓库后的产物测试证明。

主 app 的 `Resources/{en,zh-Hans}.lproj/InfoPlist.strings` 另行复制到 `Contents/Resources/{en,zh-Hans}.lproj/`，不能只放在子资源 bundle。主 Info.plist 保留 `CFBundleDevelopmentRegion=en` 并准确声明受支持语言。所有资源复制在最终 codesign 之前完成，归档解包后再次验证资源与签名。

用途说明覆盖现有五项：`NSAppleEventsUsageDescription`、`NSDesktopFolderUsageDescription`、`NSDocumentsFolderUsageDescription`、`NSDownloadsFolderUsageDescription`、`NSRemovableVolumesUsageDescription`。保留 plist 中的英文默认值。系统控制权限框的按钮和外层文案，本设计只控制应用用途说明。

helper 本批不新增 UI 资源依赖：继续传结构化事件，由主 app 显示翻译。目录读取实际发生在 helper，权限归属及用途文案来源需在签名后的完整 app 上确认；若系统实际归给 helper 且忽略主 app 用途说明，停止宣称该项已完成，记录观察并审阅针对性的后续修订，不预先扩大 helper 身份/权限设计。

## 5. 验证矩阵与交付界限

**可自动验证，实施后纳入现有 macOS CI：**

- 资源语法、重复/遗漏 key、英文基准、占位类型/数量、复数分支及可疑遗漏字面量；日志、协议和用户数据需明确排除。
- 解析器英文/简中/未支持语言、故意缺译、数字与动态参数测试；稳定菜单 action ID、快捷键不变量回归。
- `swift test`、实际 `build.sh` 产物资源布局、语言声明、五项用途说明读取、复制到仓库外的资源解析 smoke；不能仅测源码旁的资源。
- 最终 tar 解包后检查资源、可执行文件和 `codesign --verify`，继续既有 helper 估算、索引/worker、发布禁用和数据隔离回归；合成 fixture 不访问用户原版数据。

**仍需后续经授权的 macOS 图形会话/用户真机验收：**

- 英文及简中完整菜单、搜索/预览、全部设置页、全部引导步骤；关注固定 680×600 引导窗口、窄状态栏、长路径和无障碍标签。
- 在系统中切换应用语言并重启，确认窗口/菜单一致；无匹配语言时英文正常显示。
- 真实权限允许/拒绝与恢复、helper 权限归属、五项用途说明的实际呈现；系统权限提示不能靠静态 plist 读取证明。
- 下载失败/重试、索引失败/等待状态及相关文字可见性。CI 绿色不等于 GUI 或权限验收通过。

当前未获授权操作用户 Mac；本设计阶段也未运行上述新增检查。未来若真机步骤尚未完成，交付报告必须逐项注明“未验证”，不得称为完整验收。

## 6. 基线、风险与审批

基线已修复早期估算器使用旧 helper 名的问题：本批保持统一 `AppIdentity.bundledHelper` 路径，不恢复兼容别名。沿用 `docs/startup-path-audit.md` 已披露的源目录别名限制及其他未验证范围，不在翻译中顺带修搜索/索引逻辑。

主要风险是漏译动态 String、资源 bundle 在开发目录外失效、英文复数模板与中文参数不匹配、长文案截断，以及 helper 权限归属与预想不同。上面的资源、产物和真机验证分别作为对应验收门槛。

本批不指定第三种语言；批准书面设计只进入实施计划编写。产品实现、CI 推送及用户环境操作仍按各阶段授权进行。

参考：[Apple 包资源本地化](https://developer.apple.com/documentation/xcode/localizing-package-resources)；[Apple InfoPlist.strings 与复数资源指南](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/LocalizingYourApp/LocalizingYourApp.html)。
