# DigUp Test UI Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为独立 DigUp Test 提供跟随 macOS 应用语言的英文/简中界面及可靠英文回退。

**Architecture:** 应用内不可变 `Localization` 统一解析 `.strings`/`.stringsdict`，SwiftUI 与 AppKit 共用；helper 协议不变。SwiftPM 资源 bundle 显式打入 app，权限用途资源位于主 bundle，最终搬迁包验证运行时读取。

**Tech Stack:** Swift 6.2、macOS 14+、SwiftUI/AppKit/Foundation、Swift Testing、Python 3；沿用 Xcode 26.0.1 的标准 `macos-26` Actions runner，无新增依赖。

**Spec:** `docs/superpowers/specs/2026-10-12-ui-localization-design.md`（已批准；其“待审阅”是编写时状态）。设计提交基线 `b8850fb28dc40ef0a1d6174e521310c818250640`。

## Global Constraints

- “发布范围只有 `en`、`zh-Hans`”；“缺译测试验证逐 key 回退”。不增加语言选择器或运行中热切换。
- “用户文件内容、文件名、路径、代码和搜索输入原样显示”；`code:`、内部快捷键 spec、协议/数据库值不翻译。
- “CLI、诊断日志、第三方框架内部界面及其错误原文不要求完整汉化”；中文检索、IME、源目录别名限制不扩展。
- “`DigUpTest.app`、`digup-test`、现有 bundle ID、独立设置/索引/模型/临时文件路径和禁用更新策略均保持”。
- “所有资源复制在最终 codesign 之前完成”；“打包运行不得偷偷退回开发机的 `.build` 绝对路径”。
- 只在 Devin 自身 `/workspace/shared/DigUp` 工作；不新建用户环境任务、不操作用户 Mac。当前交付仅计划，执行方式待用户确认。

## Review Focus

1. 缺译或未知 key：返回英文安全文案而非内部 key；任务 1 加测试。
2. 语言与区域不同（简中 + 德国数字区域）、含 `%`/引号的文件名：不崩溃、不改写用户数据；任务 2、4 加测试。
3. 英文菜单标题变成中文：调试菜单仍执行相同动作，快捷键不漂移；任务 2 加测试。
4. 资源包移出仓库或缺失：不误读 `.build`，缺包检查明确失败；任务 5 加测试。
5. 多个计数和长状态同时出现：复数、占位、降级原因不遗漏，视觉截断另列未验证；任务 4、6 加测试/验收步骤。

---

## 文件地图与验证约定

新建 `Localization.swift`、两语言的 `Localizable.strings/stringsdict`、主 app `InfoPlist.strings`；按下列任务修改现有界面文件，不重构界面层。新增测试集中在 `Tests/DigUpAppTests/LocalizationTests.swift`、`LocalizationUITests.swift`、`LocalizedStatusTests.swift`；新增 `scripts/check-localization.py`、`scripts/test-localization-checker.py`、`scripts/smoke-test-localization.py`。资源检查脚本同时维护显式的 UI key/用途清单，遗漏字面量只生成待审报告，不能声称正则证明全覆盖。

所有任务先写失败断言，再最小实现、验证、按任务提交。Linux 可运行 Python、`git diff --check`、`bash -n build.sh`；不能运行的 Swift/macOS 命令必须交给现有 `.github/workflows/macos-build.yml`，记录对应提交和真实结果，不把预计失败/静态检查写成 Swift 测试通过。需要红绿证据的 Swift 检查在 macOS CI 保留测试先行提交与修复提交的结果；可合并同阶段检查，避免每条文案触发一次完整构建。当前写计划不触发任何 CI。

### Task 1: 建立资源与显式回退入口

**Files:** 新建 `Sources/DigUpApp/Localization.swift`、`Sources/DigUpApp/Resources/{en,zh-Hans}.lproj/Localizable.strings` 与 `Localizable.stringsdict`、上述两个 checker 脚本；修改 `Package.swift`；测试 `LocalizationTests.swift`。

**Interfaces:** 产出不可变 `nonisolated struct Localization`：`init(bundle: Bundle, preferredLanguages: [String], formattingLocale: Locale)`、`static let current: Localization`、`text(_ key: String, fallback: String) -> String`、`format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String`、`var language: String`、`var formattingLocale: Locale`。采用 Foundation 支持语言匹配；业务调用必须给英文 fallback，常用动态文案在所属任务封装类型化方法。checker 命令 `python3 scripts/check-localization.py`，失败非零退出。

- [ ] 写 `languageSelectionAndFallback` 测试，断言 `zh-Hans-CN → zh-Hans`、`en → en`、仅 `ja → en`；合成 bundle 中中文缺译读到英文，完全未知 key 返回传入英文而非 key。不为 `zh-Hant` 硬编码简中映射。
- [ ] 写 checker 自测 fixture：重复 key、缺英文、占位 `%@/%lld` 不匹配、缺复数 other 均失败；完整两语言 fixture 成功。先运行 `python3 scripts/test-localization-checker.py`，预期新实现前 FAIL；macOS 运行 `swift test --jobs 2 --filter LocalizationTests` 确认对应红测。
- [ ] 实现入口和资源声明 `defaultLocalization: "en"`，仅 DigUpApp `.process("Resources")`；先落地 `common.cancel`、`search.empty.title` 和结果数复数资源及注释。纯资源读取/格式化不得要求 MainActor。
- [ ] 重跑上述命令及 checker，预期全部 PASS/退出 0；确认选语言与选区域分离，提交 `feat: add explicit app localization resources and fallback`。

### Task 2: 本地化菜单、搜索和预览

**Files:** 修改 `App.swift`、`StatusMenu.swift`、`DebugHooks.swift`、`SearchPanelView.swift`、`SearchWindow.swift`、`Results.swift`、`Previews.swift`、`Components.swift`、`Hotkey.swift`（均在 `Sources/DigUpApp/`）及两语言表；新增 `LocalizationUITests.swift`。

**Interfaces:** 消费任务 1 入口；`StatusMenu` 产出 `enum MenuActionID: String { case pauseIndexing, resumeIndexing }` 与 `performItem(id: MenuActionID)`，对应 NSMenuItem.identifier 稳定，不再按翻译标题查找。预览/结果类型继续返回 String，不改搜索返回结构。

- [ ] 添加 `menuActionsIgnoreTranslatedTitles`、`hotkeySpecsStayStable`、`resultContentIsVerbatim`：中文菜单仍调用一次暂停/恢复；`cmd+shift+space` 的 spec/keyEquivalent 与英文相同；合成名称 `100%「合同」.md`、路径及 excerpt 原样包含于结果，不能当格式串。先以 `swift test --jobs 2 --filter LocalizationUITests` 在 macOS 确认失败。
- [ ] 迁移菜单、标题、占位、示例、空状态、筛选、匹配原因、弱匹配、播放及辅助功能标签；翻译后的字符串不再 `lowercased/uppercased` 拼句。把 `DebugHooks` 调用改成稳定 ID；不翻译内部 Space/spec，不启用更新功能。
- [ ] 跑 checker 和上述 Swift 测试，预期 PASS；逐文件对照 UI key 清单，检查静态 Text 与动态 String 均已覆盖，提交 `feat: localize menus search and previews`。

### Task 3: 本地化设置与首次引导

**Files:** 修改 `SettingsWindow.swift`、`AddFolders.swift`、`FolderChoices.swift`、`AppSettings.swift`、`AppController.swift`、`CodeEditors.swift`、`Onboarding.swift`、两语言资源及 `LocalizationUITests.swift`。

**Interfaces:** 继续使用任务 1 的 `Localization`；`pickFolders(for:prompt:then:)` 保留函数结构，默认/调用方 prompt 改为已解析文案；不改变设置 key、路径、面板返回 URL 或用户选择。

- [ ] 添加 `settingsAndOnboardingCopyCovered`：资源清单枚举所有 tab、步骤、移除/关闭确认、重试、权限恢复、面板 prompt 和 VoiceOver key，两语言均存在且简中不返回 key。更新清单后先运行 checker，预期缺资源失败。
- [ ] 完成两语言资源和接入；品牌、编辑器名称保留，默认打开应用的描述可翻译；路径/扩展名输入原样保留，继续使用 `AppIdentity.bundledHelper`。引导仍使用原步骤和动作，不新增控件。
- [ ] checker 退出 0，macOS `swift test --jobs 2 --filter LocalizationUITests` PASS；将固定引导窗、长文案、拒绝权限后的页面列入任务 6 真机清单，提交 `feat: localize settings and onboarding`。

### Task 4: 完整句、复数与错误格式化

**Files:** 修改 `AppModel.swift`、`ModelDownload.swift`、`Engine.swift`、`PowerPolicy.swift`、`Hotkey.swift`、`Estimates.swift`、`Results.swift`、`SettingsWindow.swift`、`Localization.swift` 及语言表；新增 `LocalizedStatusTests.swift`。

**Interfaces:** 为常用组合添加 `Localization.resultsCount(_ count: Int) -> String`、`indexingProgress(done: Int, total: Int) -> String`、`waitingFiles(_ count: Int, reason: String?) -> String`、`durationEstimate(_ seconds: Double) -> String`；在同一文件 extension 实现，以便测试传入语言/区域。其他完整句直接调用 `format`，参数类型在资源注释声明。

- [ ] 写 `pluralCountsAndReorderedParameters`、`languageAndRegionAreIndependent`、`knownErrorsHaveLocalizedContext`：0/1/2/12345、done=1/total=2、中文加 `de_DE` 格式、小数时长、等待原因、未知原始错误字符串均有明确断言；英文单复数正确，中文数字和理由不丢失。macOS `swift test --jobs 2 --filter LocalizedStatusTests` 先 FAIL。
- [ ] 用完整模板与 `.stringsdict` 替换 file/files、字符串片段拼句，原始数值参与复数；格式与期望使用同 locale 的 Foundation formatter。日期、字节、百分比、时长统一检查；媒体时码/代码位置/URL 参数不变。
- [ ] 本地化已知索引/下载/快捷键/电源失败说明，未知系统错误附原文；禁止解析英文错误反推状态，helper JSON 和日志保持原契约。迁移多计数文案及下载进度，无新增全局可变 locale。
- [ ] checker 退出 0，上述 Swift 测试 PASS，执行已有数据隔离测试无回归，提交 `feat: localize status errors and numeric messages`。

### Task 5: 验证真实资源打包与权限用途

**Files:** 修改 `build.sh`、`Resources/Info.plist`、`Localization.swift`、`App.swift`；新增 `Resources/{en,zh-Hans}.lproj/InfoPlist.strings`、`Sources/DigUpApp/LocalizationSmoke.swift`、`scripts/smoke-test-localization.py`；扩展 `LocalizationTests.swift`。

**Interfaces:** `Localization.resourceBundle(appBundle: Bundle) throws -> Bundle` 显式区分打包 app/SwiftPM 测试。`LocalizationSmoke.runIfRequested(arguments: [String]) -> Int32?` 在 AppDelegate.main 最前识别 `--localization-smoke`，输出只含语言、资源路径、代表文案和权限值的 JSON 后退出；不创建 AppController、读写设置、启动 helper/GUI 或发网络请求。脚本调用 `python3 scripts/smoke-test-localization.py /absolute/DigUpTest.app`。

- [ ] 先写包测试：当前产物缺本地化 bundle/两语言用途说明应 FAIL；缺包合成 app 不允许回退到 `.build`；`--localization-smoke -AppleLanguages '(zh-Hans)'` 应返回中文代表文案及 app 内资源路径。
- [ ] 在 macOS 构建后检查实际 SwiftPM 产物及 accessor，确定精确 bundle basename，并使构建与 resolver 共用该确定值；完整复制到 Contents/Resources 后校验，不 glob 搬走无关 bundle。打包 app 缺资源抛出清晰错误，开发测试才用 Bundle.module。
- [ ] 主 app 单独复制 InfoPlist.strings；五项为 AppleEvents、DesktopFolder、DocumentsFolder、DownloadsFolder、RemovableVolumes 的 UsageDescription，保留英文 plist 默认；准确声明 `en/zh-Hans`。复制全部完成后才签名，不改 helper 身份/权限。
- [ ] macOS `SIGN_ID=- RELEASE=0 ./build.sh` 后运行包脚本：仅操作临时副本，移至仓库外执行英/简中/仅日语 smoke；临时隐藏构建产物并用 trap 恢复，证明不依赖 `.build`。检查五项值、只读 smoke 无设置/索引副作用；完整副本 `codesign --verify --deep --strict` 成功，资源缺失负例非零退出。提交 `build: package and verify app localization resources`。

### Task 6: CI 总体验证、独立审查与交付

**Files:** 修改 `.github/workflows/macos-build.yml`、`docs/ci-macos.md`；新增 `docs/ui-localization-acceptance.md`，必要时将其纳入现有包清单。

**Interfaces:** 复用 checker、全量 Swift tests、任务 5 包脚本及已有 `smoke-test-bundle.py`；不新建 runner/云环境，不新增依赖或完整媒体模型下载。

- [ ] 在标准 macOS workflow 接入 checker/自测及完整 `swift test --jobs 2`，并在 tar 解包后对解包 app 运行任务 5 smoke；缺资源/用途值/错误资源路径令 job 失败，保留每项日志及源提交。
- [ ] 顺序实施选择下请一位独立 reviewer 检查最终 diff，重点用 Review Focus 五项及设计覆盖表；修复实质问题后重跑受影响测试，不为每条字符串另开审查。
- [ ] 编写真机验收表：英语/简中各菜单、搜索、设置、引导、长路径/680×600布局、VoiceOver、系统切换语言重启、权限允许/拒绝/恢复及 helper 归属、下载失败重试/索引等待。未获用户 Mac 授权的项目全部标“未验证”；权限用途实呈不符则报告并审阅修订。
- [ ] 本地提交 `test: gate localization packaging and document acceptance`；在已有授权范围推送执行提交并跟踪对应 Actions run 至结束，验证原有隔离、helper、索引、worker、签名、归档和新增本地化检查。失败先诊断修复并提交后重跑，不宣称跳过的媒体/GUI测试通过。
- [ ] 交付源提交、Actions 链接、校验和/测试包及通过/跳过/未验证摘要。核实下载包与 CI 对应，保持原版数据隔离；用户真机授权另问，不以 CI 代替。

## 自审与执行选择

自审映射：设计§1/§6→全局约束及任务6；§2→任务1；§3→任务2–4；§4→任务5；§5→任务6。接口名称已对齐，未指定不存在的外部服务；命令中的新脚本均有所属创建任务。红测与绿测必须记录实际环境结果，本文不是测试通过报告。

建议 **Native 顺序实施，完成后一次独立总体审查**：六个任务共用资源/格式入口且相互依赖，逐任务新建实现和审查代理会重复上下文。另一选项为逐任务新代理实现和审查，最后再总体审查，更严格但成本更高。请确认本计划并选择执行方式；当前停在计划交付，不开始产品实现。
